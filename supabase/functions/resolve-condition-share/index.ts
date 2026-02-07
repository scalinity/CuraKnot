import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Simple in-memory rate limiting
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 30;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;

function checkRateLimit(identifier: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(identifier);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(identifier, {
      count: 1,
      resetAt: now + RATE_LIMIT_WINDOW_MS,
    });
    return true;
  }
  entry.count++;
  return entry.count <= RATE_LIMIT_MAX;
}

// Token format: UUID v4 or base64url (32-128 chars alphanumeric/dash/underscore)
const TOKEN_FORMAT_REGEX = /^[a-zA-Z0-9_-]{8,128}$/;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Rate limit by IP
    const clientIP =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
    if (!checkRateLimit(clientIP)) {
      return renderErrorPage("Too many requests. Please try again later.", 429);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Extract token from query params
    const url = new URL(req.url);
    const token = url.searchParams.get("token");

    if (!token) {
      return renderErrorPage("Missing share token", 400);
    }

    // Validate token format
    if (!TOKEN_FORMAT_REGEX.test(token)) {
      return renderErrorPage("Invalid share token format.", 400);
    }

    // Look up share link
    const { data: shareLink, error: linkError } = await supabase
      .from("share_links")
      .select("*")
      .eq("token", token)
      .eq("object_type", "condition_photos")
      .single();

    if (linkError || !shareLink) {
      return renderErrorPage("Share link not found or invalid.", 404);
    }

    // Check if revoked
    if (shareLink.revoked_at) {
      return renderErrorPage("This share link has been revoked.", 410);
    }

    // Check expiration
    if (new Date(shareLink.expires_at) < new Date()) {
      const expDate = new Date(shareLink.expires_at).toLocaleDateString(
        "en-US",
        { year: "numeric", month: "long", day: "numeric" },
      );
      return renderErrorPage(
        `This share link expired on ${expDate}. Contact the care team for a new link.`,
        410,
      );
    }

    // Atomically check and increment access count (prevents TOCTOU race)
    if (shareLink.max_access_count !== null) {
      const { data: updated, error: updateError } = await supabase
        .from("share_links")
        .update({
          access_count: shareLink.access_count + 1,
          last_accessed_at: new Date().toISOString(),
        })
        .eq("id", shareLink.id)
        .lt("access_count", shareLink.max_access_count)
        .select("id")
        .single();

      if (updateError || !updated) {
        return renderErrorPage(
          "This share link has reached its access limit. Contact the care team for a new link.",
          410,
        );
      }
    } else {
      // No access limit, just increment
      await supabase
        .from("share_links")
        .update({
          access_count: shareLink.access_count + 1,
          last_accessed_at: new Date().toISOString(),
        })
        .eq("id", shareLink.id);
    }

    // Log access
    const ipHash = req.headers.get("x-forwarded-for") || "unknown";
    const userAgent = req.headers.get("user-agent") || "unknown";

    await supabase.from("share_link_access_log").insert({
      share_link_id: shareLink.id,
      ip_address_hash: await hashString(ipHash),
      user_agent_hash: await hashString(userAgent),
    });

    // Load condition
    const { data: condition } = await supabase
      .from("tracked_conditions")
      .select("condition_type, body_location, description, start_date")
      .eq("id", shareLink.object_id)
      .single();

    if (!condition) {
      return renderErrorPage("Condition no longer available.", 404);
    }

    // Load patient (first name only for privacy)
    const { data: patient } = await supabase
      .from("patients")
      .select("first_name")
      .eq(
        "id",
        (
          await supabase
            .from("tracked_conditions")
            .select("patient_id")
            .eq("id", shareLink.object_id)
            .single()
        ).data?.patient_id,
      )
      .single();

    // Load shared photos via junction
    const { data: sharedPhotos } = await supabase
      .from("condition_share_photos")
      .select(
        "condition_photo_id, include_annotations, condition_photos(id, storage_key, thumbnail_key, captured_at, notes, annotations_json, lighting_quality)",
      )
      .eq("share_link_id", shareLink.id)
      .order("created_at", { ascending: true });

    if (!sharedPhotos || sharedPhotos.length === 0) {
      return renderErrorPage("No photos available for this share link.", 404);
    }

    // Generate signed URLs for each photo (15-minute TTL)
    const photoEntries = [];
    for (const sp of sharedPhotos) {
      const photo = sp.condition_photos as any;
      if (!photo) continue;

      const { data: signedUrl } = await supabase.storage
        .from("condition-photos")
        .createSignedUrl(photo.storage_key, 900);

      const { data: thumbUrl } = await supabase.storage
        .from("condition-photos")
        .createSignedUrl(photo.thumbnail_key, 900);

      photoEntries.push({
        id: photo.id,
        url: signedUrl?.signedUrl || "",
        thumbnail_url: thumbUrl?.signedUrl || "",
        captured_at: photo.captured_at,
        notes: photo.notes,
        annotations: sp.include_annotations
          ? photo.annotations_json
          : undefined,
        lighting_quality: photo.lighting_quality,
      });
    }

    // Sort by captured_at ascending (oldest first for progression view)
    photoEntries.sort(
      (a, b) =>
        new Date(a.captured_at).getTime() - new Date(b.captured_at).getTime(),
    );

    // Log to photo_access_log
    for (const pe of photoEntries) {
      await supabase.from("photo_access_log").insert({
        circle_id: shareLink.circle_id,
        condition_photo_id: pe.id,
        accessed_by: null,
        access_type: "SHARE_VIEW",
        ip_hash: await hashString(ipHash),
        user_agent_hash: await hashString(userAgent),
      });
    }

    const expiresAt = new Date(shareLink.expires_at).toLocaleDateString(
      "en-US",
      { year: "numeric", month: "long", day: "numeric" },
    );

    // Check Accept header for JSON vs HTML
    const accept = req.headers.get("Accept") || "";
    if (accept.includes("application/json")) {
      return new Response(
        JSON.stringify({
          success: true,
          object_type: "condition_photos",
          condition: {
            type: condition.condition_type,
            body_location: condition.body_location,
            description: condition.description,
            start_date: condition.start_date,
          },
          photos: photoEntries.map(({ id, ...rest }) => rest),
          patient_label: patient?.first_name || "Patient",
          expires_at: shareLink.expires_at,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Return HTML page for browser access
    return renderPhotoPage({
      patientName: patient?.first_name || "Patient",
      conditionType: formatConditionType(condition.condition_type),
      bodyLocation: condition.body_location,
      description: condition.description,
      photos: photoEntries,
      expiresAt,
    });
  } catch (error) {
    console.error(
      "Unexpected error:",
      error instanceof Error ? error.name : "Unknown error",
    );
    return renderErrorPage("An unexpected error occurred.", 500);
  }
});

async function hashString(input: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function formatConditionType(type: string): string {
  const map: Record<string, string> = {
    WOUND: "Wound/Incision",
    RASH: "Rash",
    SWELLING: "Swelling",
    BRUISE: "Bruise",
    SURGICAL: "Surgical Site",
    OTHER: "Other",
  };
  return map[type] || type;
}

function renderErrorPage(message: string, status: number): Response {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CuraKnot - Share Link</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f7; color: #1d1d1f; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 20px; }
    .card { background: white; border-radius: 16px; padding: 40px; max-width: 480px; text-align: center; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }
    .icon { font-size: 48px; margin-bottom: 16px; }
    h1 { font-size: 20px; margin-bottom: 12px; }
    p { color: #86868b; line-height: 1.5; }
    .brand { margin-top: 24px; font-size: 12px; color: #86868b; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">&#128274;</div>
    <h1>Share Link Unavailable</h1>
    <p>${escapeHtml(message)}</p>
    <p class="brand">CuraKnot &mdash; Secure Care Coordination</p>
  </div>
</body>
</html>`;
  return new Response(html, {
    status,
    headers: { ...corsHeaders, "Content-Type": "text/html; charset=utf-8" },
  });
}

function renderPhotoPage(data: {
  patientName: string;
  conditionType: string;
  bodyLocation: string;
  description: string | null;
  photos: Array<{
    url: string;
    thumbnail_url: string;
    captured_at: string;
    notes: string | null;
    lighting_quality: string | null;
  }>;
  expiresAt: string;
}): Response {
  const photoCards = data.photos
    .map((photo, i) => {
      const date = new Date(photo.captured_at).toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
      });
      return `
      <div class="photo-card">
        <div class="photo-header">
          <span class="photo-date">${escapeHtml(date)}</span>
          <span class="photo-number">Photo ${i + 1} of ${data.photos.length}</span>
        </div>
        <img src="${escapeHtml(photo.url)}" alt="Condition photo ${i + 1}" loading="lazy" />
        ${photo.notes ? `<p class="photo-notes">${escapeHtml(photo.notes)}</p>` : ""}
      </div>`;
    })
    .join("\n");

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CuraKnot - Condition Photos</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f7; color: #1d1d1f; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; }
    .header { background: white; border-radius: 16px; padding: 24px; margin-bottom: 16px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }
    .header h1 { font-size: 20px; margin-bottom: 4px; }
    .header .meta { color: #86868b; font-size: 14px; margin-bottom: 8px; }
    .header .description { font-size: 14px; color: #1d1d1f; }
    .notice { background: #fff3cd; border-radius: 12px; padding: 12px 16px; margin-bottom: 16px; font-size: 13px; color: #856404; text-align: center; }
    .photo-card { background: white; border-radius: 16px; margin-bottom: 16px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }
    .photo-header { padding: 12px 16px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f0f0f0; }
    .photo-date { font-weight: 600; font-size: 14px; }
    .photo-number { color: #86868b; font-size: 12px; }
    .photo-card img { width: 100%; display: block; }
    .photo-notes { padding: 12px 16px; font-size: 14px; color: #1d1d1f; border-top: 1px solid #f0f0f0; }
    .footer { text-align: center; padding: 24px; color: #86868b; font-size: 12px; }
    .security { display: flex; align-items: center; gap: 6px; justify-content: center; margin-top: 8px; font-size: 11px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>${escapeHtml(data.conditionType)} &mdash; ${escapeHtml(data.bodyLocation)}</h1>
      <p class="meta">Patient: ${escapeHtml(data.patientName)} &bull; ${data.photos.length} photo${data.photos.length !== 1 ? "s" : ""}</p>
      ${data.description ? `<p class="description">${escapeHtml(data.description)}</p>` : ""}
    </div>
    <div class="notice">
      &#9888; This link expires ${escapeHtml(data.expiresAt)}. Photos are for clinical review only.
    </div>
    ${photoCards}
    <div class="footer">
      <p>Shared securely via CuraKnot</p>
      <div class="security">&#128274; End-to-end secure &bull; Access logged</div>
    </div>
  </div>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store, no-cache, must-revalidate",
      "X-Frame-Options": "DENY",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
