import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GenerateConditionShareRequest {
  condition_id: string;
  photo_ids: string[];
  expiration_days: number;
  single_use: boolean;
  recipient?: string;
  include_annotations?: boolean;
}

// Rate limiting
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 10; // stricter limit for share generation
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
let cleanupCounter = 0;

function cleanupRateLimitMap() {
  const now = Date.now();
  for (const [key, entry] of rateLimitMap.entries()) {
    if (now > entry.resetAt) {
      rateLimitMap.delete(key);
    }
  }
}

function checkRateLimit(identifier: string): boolean {
  cleanupCounter++;
  if (cleanupCounter >= 100) {
    cleanupCounter = 0;
    cleanupRateLimitMap();
  }

  const now = Date.now();
  const entry = rateLimitMap.get(identifier);

  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(identifier, {
      count: 1,
      resetAt: now + RATE_LIMIT_WINDOW_MS,
    });
    return true;
  }

  if (entry.count >= RATE_LIMIT_MAX) {
    return false;
  }

  entry.count++;
  return true;
}

// UUID validation
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUUID(str: string): boolean {
  return UUID_PATTERN.test(str);
}

// Sanitize recipient string (email or name, max 200 chars, no control chars)
function sanitizeRecipient(input: string): string {
  return input
    .replace(/[\x00-\x1f\x7f]/g, "") // strip control chars
    .trim()
    .substring(0, 200);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Rate limit by user (extracted after auth)
    const clientIP =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";

    if (!checkRateLimit(clientIP)) {
      return new Response(
        JSON.stringify({
          error: {
            code: "RATE_LIMIT_EXCEEDED",
            message: "Too many requests. Please try again later.",
          },
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Retry-After": "60",
          },
        },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: {
            code: "UNAUTHORIZED",
            message: "Missing Authorization header",
          },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(
        JSON.stringify({
          error: { code: "UNAUTHORIZED", message: "Invalid token" },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request
    const body: GenerateConditionShareRequest = await req.json();
    const {
      condition_id,
      photo_ids,
      expiration_days,
      single_use,
      recipient,
      include_annotations = true,
    } = body;

    // Validate inputs
    if (!condition_id || !photo_ids?.length) {
      return new Response(
        JSON.stringify({
          error: {
            code: "INVALID_INPUT",
            message: "condition_id and photo_ids are required",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate UUID formats
    if (!isValidUUID(condition_id)) {
      return new Response(
        JSON.stringify({
          error: {
            code: "INVALID_INPUT",
            message: "Invalid condition_id format",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    for (const pid of photo_ids) {
      if (!isValidUUID(pid)) {
        return new Response(
          JSON.stringify({
            error: {
              code: "INVALID_INPUT",
              message: "Invalid photo_id format",
            },
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (expiration_days < 1 || expiration_days > 7) {
      return new Response(
        JSON.stringify({
          error: {
            code: "INVALID_INPUT",
            message: "expiration_days must be between 1 and 7",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (photo_ids.length > 100) {
      return new Response(
        JSON.stringify({
          error: {
            code: "INVALID_INPUT",
            message: "Maximum 100 photos per share link",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Sanitize recipient
    const sanitizedRecipient = recipient ? sanitizeRecipient(recipient) : null;

    // Check FAMILY tier
    const { data: hasFeature } = await supabase.rpc("has_feature_access", {
      p_user_id: user.id,
      p_feature: "condition_photo_share",
    });

    if (!hasFeature) {
      return new Response(
        JSON.stringify({
          error: {
            code: "TIER_REQUIRED",
            message: "Photo sharing requires Family plan",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify condition exists and user has access
    const { data: condition, error: conditionError } = await supabase
      .from("tracked_conditions")
      .select("id, circle_id, patient_id")
      .eq("id", condition_id)
      .single();

    if (conditionError || !condition) {
      return new Response(
        JSON.stringify({
          error: { code: "NOT_FOUND", message: "Condition not found" },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify circle membership
    const { data: membership } = await supabase
      .from("circle_members")
      .select("role")
      .eq("circle_id", condition.circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership) {
      return new Response(
        JSON.stringify({
          error: { code: "UNAUTHORIZED", message: "Not a circle member" },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify all photo_ids belong to this condition
    const { data: photos, error: photosError } = await supabase
      .from("condition_photos")
      .select("id")
      .eq("condition_id", condition_id)
      .in("id", photo_ids);

    if (photosError || !photos || photos.length !== photo_ids.length) {
      return new Response(
        JSON.stringify({
          error: {
            code: "INVALID_INPUT",
            message: "One or more photos not found for this condition",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate token
    const tokenBytes = new Uint8Array(32);
    crypto.getRandomValues(tokenBytes);
    const token = Array.from(tokenBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + expiration_days);

    // Create share link
    const { data: shareLink, error: shareLinkError } = await supabase
      .from("share_links")
      .insert({
        circle_id: condition.circle_id,
        object_type: "condition_photos",
        object_id: condition_id,
        token: token,
        expires_at: expiresAt.toISOString(),
        max_access_count: single_use ? 1 : null,
        created_by: user.id,
      })
      .select()
      .single();

    if (shareLinkError || !shareLink) {
      console.error(
        JSON.stringify({
          context: "share_link_creation_failed",
          errorType: "database",
        }),
      );
      return new Response(
        JSON.stringify({
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to create share link",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create junction records
    const junctionRecords = photo_ids.map((photoId: string) => ({
      share_link_id: shareLink.id,
      condition_photo_id: photoId,
      include_annotations: include_annotations,
    }));

    const { error: junctionError } = await supabase
      .from("condition_share_photos")
      .insert(junctionRecords);

    if (junctionError) {
      console.error(
        JSON.stringify({
          context: "junction_creation_failed",
          errorType: "database",
        }),
      );
      // Clean up share link
      await supabase.from("share_links").delete().eq("id", shareLink.id);
      return new Response(
        JSON.stringify({
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to link photos to share",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Log audit event
    await supabase.from("audit_events").insert({
      circle_id: condition.circle_id,
      actor_user_id: user.id,
      event_type: "CONDITION_PHOTO_SHARED",
      object_type: "share_link",
      object_id: shareLink.id,
      metadata_json: {
        condition_id: condition_id,
        photo_count: photo_ids.length,
        expiration_days: expiration_days,
        single_use: single_use,
        has_recipient: !!sanitizedRecipient,
      },
    });

    const baseUrl = Deno.env.get("SUPABASE_URL") || "https://app.curaknot.com";
    const shareUrl = `${baseUrl}/functions/v1/resolve-share-link?token=${token}`;

    return new Response(
      JSON.stringify({
        success: true,
        share_link_id: shareLink.id,
        share_url: shareUrl,
        expires_at: expiresAt.toISOString(),
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error(
      JSON.stringify({
        context: "unexpected_error",
        errorType:
          error instanceof Error ? error.constructor.name : typeof error,
        message:
          error instanceof Error
            ? error.message.replace(/[0-9a-f-]{36}/gi, "[REDACTED]")
            : "Unknown error",
      }),
    );
    return new Response(
      JSON.stringify({
        error: {
          code: "INTERNAL_ERROR",
          message: "An unexpected error occurred",
        },
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
