import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ResolveRequest {
  token: string;
}

interface ResolveResponse {
  success: boolean;
  object_type?: string;
  content?: any;
  patient_label?: string;
  expires_at?: string;
  error?: {
    code: string;
    message: string;
  };
}

// Simple in-memory rate limiting (per-function instance)
// For production, consider using Redis or database-backed rate limiting
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 30; // max requests per window
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute window

// Cleanup expired rate limit entries periodically (every 100 requests)
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
  // Periodically cleanup expired entries
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Extract client info for rate limiting and audit
    const clientIP =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
    const userAgent = req.headers.get("user-agent") || "unknown";

    // Rate limiting by IP
    if (!checkRateLimit(clientIP)) {
      return new Response(
        JSON.stringify({
          success: false,
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

    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      logSafeError("missing_env_vars", null);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CONFIG_ERROR",
            message: "Server configuration error",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Get token from URL params or body
    let token: string;

    if (req.method === "GET") {
      const url = new URL(req.url);
      token = url.searchParams.get("token") || "";
    } else {
      const body: ResolveRequest = await req.json();
      token = body.token;
    }

    // Validate token format (UUID or base64 token)
    const tokenPattern = /^[a-zA-Z0-9_-]{20,64}$/;
    if (!token || !tokenPattern.test(token)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "VALIDATION_ERROR", message: "Invalid token format" },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Hash IP and user agent for privacy

    const ipHash = await hashString(clientIP);
    const uaHash = await hashString(userAgent);

    // Resolve the link
    const { data: linkResult, error: linkError } = await supabaseService.rpc(
      "resolve_share_link",
      {
        p_token: token,
        p_ip_hash: ipHash,
        p_user_agent_hash: uaHash,
      },
    );

    if (linkError) {
      logSafeError("link_resolution_failed", linkError);
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "DATABASE_ERROR", message: "Failed to resolve link" },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (linkResult.error) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "LINK_ERROR", message: linkResult.error },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch the actual content based on object type
    let content: any = null;
    let patientLabel = "";

    if (linkResult.object_type === "condition_photos") {
      // Fetch shared condition photos
      const { data: condition } = await supabaseService
        .from("tracked_conditions")
        .select(
          "id, circle_id, condition_type, body_location, start_date, status, patient:patients(display_name, initials)",
        )
        .eq("id", linkResult.object_id)
        .single();

      if (condition) {
        // Fetch the specific photos linked to this share
        const { data: sharedPhotos } = await supabaseService
          .from("condition_share_photos")
          .select(
            "condition_photo_id, include_annotations, photo:condition_photos(id, captured_at, notes, lighting_quality, storage_key, annotations_json)",
          )
          .eq("share_link_id", linkResult.link_id);

        if (sharedPhotos && sharedPhotos.length > 0) {
          // Generate signed URLs for each photo (15-min TTL)
          const photosWithUrls = await Promise.all(
            sharedPhotos.map(async (sp: any) => {
              const photo = sp.photo;
              if (!photo) return null;

              const { data: signedUrl } = await supabaseService.storage
                .from("condition-photos")
                .createSignedUrl(photo.storage_key, 900);

              // Log access (non-blocking to avoid failing the request)
              try {
                await supabaseService.from("photo_access_log").insert({
                  circle_id: condition.circle_id,
                  condition_photo_id: photo.id,
                  access_type: "SHARE_VIEW",
                  ip_hash: ipHash,
                  user_agent_hash: uaHash,
                });
              } catch (auditError) {
                logSafeError("audit_log_insert_failed", auditError);
              }

              return {
                captured_at: photo.captured_at,
                notes: photo.notes,
                lighting_quality: photo.lighting_quality,
                url: signedUrl?.signedUrl || null,
                annotations: sp.include_annotations
                  ? photo.annotations_json
                  : null,
              };
            }),
          );

          const patient = condition.patient as {
            display_name?: string;
            initials?: string;
          } | null;
          patientLabel =
            patient?.initials || patient?.display_name || "Patient";

          content = sanitizeConditionContent(condition, photosWithUrls);
        }
      }
    } else if (linkResult.object_type === "appointment_pack") {
      const { data: pack } = await supabaseService
        .from("appointment_packs")
        .select("content_json, patient:patients(display_name, initials)")
        .eq("id", linkResult.object_id)
        .single();

      if (pack) {
        // Sanitize content - remove internal IDs and sensitive data
        content = sanitizePackContent(pack.content_json);
        const patient = pack.patient as {
          display_name?: string;
          initials?: string;
        } | null;
        patientLabel = patient?.initials || patient?.display_name || "Patient";
      }
    } else if (linkResult.object_type === "emergency_card") {
      const { data: card } = await supabaseService
        .from("emergency_cards")
        .select("snapshot_json, patient:patients(display_name, initials)")
        .eq("id", linkResult.object_id)
        .single();

      if (card) {
        content = card.snapshot_json;
        const patient = card.patient as {
          display_name?: string;
          initials?: string;
        } | null;
        patientLabel = patient?.initials || patient?.display_name || "Patient";
      }
    } else if (linkResult.object_type === "care_network") {
      const { data: networkExport } = await supabaseService
        .from("care_network_exports")
        .select(
          "content_snapshot_json, patient:patients(display_name, initials)",
        )
        .eq("id", linkResult.object_id)
        .single();

      if (networkExport) {
        content = sanitizeCareNetworkContent(
          networkExport.content_snapshot_json,
        );
        const patient = networkExport.patient as {
          display_name?: string;
          initials?: string;
        } | null;
        patientLabel = patient?.initials || patient?.display_name || "Patient";
      }
    }

    if (!content) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "NOT_FOUND", message: "Content not found" },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get link expiry
    const { data: link } = await supabaseService
      .from("share_links")
      .select("expires_at")
      .eq("token", token)
      .single();

    const response: ResolveResponse = {
      success: true,
      object_type: linkResult.object_type,
      content,
      patient_label: patientLabel,
      expires_at: link?.expires_at,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    logSafeError("request_processing_failed", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "INTERNAL_ERROR", message: "Internal server error" },
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

async function hashString(input: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .substring(0, 16);
}

// Safe error logging that redacts sensitive fields
function logSafeError(context: string, error: unknown) {
  const safeError = {
    context,
    errorType: error instanceof Error ? error.constructor.name : typeof error,
    message:
      error instanceof Error
        ? error.message.replace(/[0-9a-f-]{36}/gi, "[REDACTED-UUID]")
        : "Unknown error",
  };
  console.error(JSON.stringify(safeError));
}

function sanitizePackContent(content: any): any {
  // Remove internal IDs and potentially sensitive data
  const sanitized = { ...content };

  // Remove internal IDs from handoffs
  if (sanitized.handoffs) {
    sanitized.handoffs = sanitized.handoffs.map((h: any) => ({
      type: h.type,
      title: h.title,
      summary: h.summary,
      date: h.created_at,
    }));
  }

  // Remove internal IDs from tasks
  if (sanitized.open_tasks) {
    sanitized.open_tasks = sanitized.open_tasks.map((t: any) => ({
      title: t.title,
      priority: t.priority,
      due_at: t.due_at,
    }));
  }

  // Remove internal IDs from questions
  if (sanitized.questions) {
    sanitized.questions = sanitized.questions.map((q: any) => ({
      question: q.question,
      priority: q.priority,
    }));
  }

  // Remove patient ID
  if (sanitized.patient) {
    sanitized.patient = {
      name: sanitized.patient.name,
      initials: sanitized.patient.initials,
    };
  }

  return sanitized;
}

function sanitizeCareNetworkContent(content: any): any {
  // Use allowlist approach for care network content sanitization
  // Only include explicitly allowed fields to prevent data leakage

  const allowedPatientFields = ["name", "initials"];
  const allowedProviderFields = ["title", "type", "category"];
  const allowedContentFields = [
    "phone",
    "email",
    "address",
    "organization",
    "role",
    "unit_room",
    "visiting_hours",
    "provider",
    "plan_name",
    "member_id",
    "group_number",
    "fax",
  ];
  const allowedCountFields = ["total", "by_category"];

  const sanitized: Record<string, any> = {};

  // Sanitize patient info using allowlist
  if (content?.patient && typeof content.patient === "object") {
    sanitized.patient = {};
    for (const field of allowedPatientFields) {
      if (content.patient[field] !== undefined) {
        sanitized.patient[field] = content.patient[field];
      }
    }
  }

  // Sanitize providers using allowlist
  if (Array.isArray(content?.providers)) {
    sanitized.providers = content.providers.map((p: any) => {
      if (!p || typeof p !== "object") return {};

      const sanitizedProvider: Record<string, any> = {};

      // Copy allowed top-level fields
      for (const field of allowedProviderFields) {
        if (p[field] !== undefined) {
          sanitizedProvider[field] = p[field];
        }
      }

      // Sanitize content using allowlist
      if (p.content && typeof p.content === "object") {
        sanitizedProvider.content = {};
        for (const field of allowedContentFields) {
          if (p.content[field] !== undefined) {
            sanitizedProvider.content[field] = p.content[field];
          }
        }
      }

      return sanitizedProvider;
    });
  }

  // Sanitize counts using allowlist
  if (content?.counts && typeof content.counts === "object") {
    sanitized.counts = {};
    for (const field of allowedCountFields) {
      if (content.counts[field] !== undefined) {
        sanitized.counts[field] = content.counts[field];
      }
    }
  }

  // Include generated_at timestamp if present
  if (content?.generated_at) {
    sanitized.generated_at = content.generated_at;
  }

  return sanitized;
}

function sanitizeConditionContent(condition: any, photosWithUrls: any[]): any {
  // Allowlist approach: only include explicitly safe fields
  const allowedConditionFields = [
    "condition_type",
    "body_location",
    "start_date",
    "status",
  ];
  const allowedPhotoFields = [
    "captured_at",
    "notes",
    "lighting_quality",
    "url",
    "annotations",
  ];

  const sanitized: Record<string, any> = {};

  for (const field of allowedConditionFields) {
    if (condition[field] !== undefined) {
      sanitized[field] = condition[field];
    }
  }

  sanitized.photos = photosWithUrls.filter(Boolean).map((p: any) => {
    const sp: Record<string, any> = {};
    for (const field of allowedPhotoFields) {
      if (p[field] !== undefined) {
        sp[field] = p[field];
      }
    }
    return sp;
  });

  return sanitized;
}
