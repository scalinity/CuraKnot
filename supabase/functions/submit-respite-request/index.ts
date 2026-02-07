import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface SubmitRequest {
  circleId: string;
  patientId: string;
  providerId: string;
  startDate: string;
  endDate: string;
  specialConsiderations?: string;
  shareMedications: boolean;
  shareContacts: boolean;
  shareDietary: boolean;
  shareFullSummary: boolean;
  contactMethod: "PHONE" | "EMAIL";
  contactValue: string;
}

function validationError(message: string): Response {
  return new Response(
    JSON.stringify({
      success: false,
      error: { code: "VALIDATION_ERROR", message },
    }),
    {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    },
  );
}

const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

function validateRequestBody(body: SubmitRequest): string | null {
  if (!body.circleId || !UUID_REGEX.test(body.circleId)) {
    return "Valid circleId is required";
  }
  if (!body.patientId || !UUID_REGEX.test(body.patientId)) {
    return "Valid patientId is required";
  }
  if (!body.providerId || !UUID_REGEX.test(body.providerId)) {
    return "Valid providerId is required";
  }
  if (
    !body.startDate ||
    !body.endDate ||
    !DATE_REGEX.test(body.startDate) ||
    !DATE_REGEX.test(body.endDate) ||
    isNaN(Date.parse(body.startDate)) ||
    isNaN(Date.parse(body.endDate))
  ) {
    return "Valid start and end dates (YYYY-MM-DD) are required";
  }
  if (!body.contactMethod || !["PHONE", "EMAIL"].includes(body.contactMethod)) {
    return "Contact method must be PHONE or EMAIL";
  }
  if (
    !body.contactValue ||
    body.contactValue.trim().length === 0 ||
    body.contactValue.trim().length > 200
  ) {
    return "Contact value is required and must be under 200 characters";
  }
  if (new Date(body.endDate) < new Date(body.startDate)) {
    return "End date must be on or after start date";
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Validate JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "Missing authorization",
          },
        }),
        {
          status: 401,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_INVALID_TOKEN", message: "Invalid token" },
        }),
        {
          status: 401,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limit check (20 requests per minute per user for submit)
    const { data: withinLimit } = await supabaseService.rpc(
      "check_rate_limit",
      {
        p_user_id: user.id,
        p_endpoint: "submit-respite-request",
        p_max_requests: 20,
        p_window_seconds: 60,
      },
    );

    if (withinLimit === false) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "RATE_LIMITED",
            message: "Too many requests. Please try again shortly.",
          },
        }),
        {
          status: 429,
          headers: {
            ...CORS_HEADERS,
            "Content-Type": "application/json",
            "Retry-After": "60",
          },
        },
      );
    }

    // Parse request
    const body: SubmitRequest | null = await req.json().catch(() => null);
    if (!body) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "VALIDATION_ERROR", message: "Invalid JSON body" },
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Validate all fields
    const validationMessage = validateRequestBody(body);
    if (validationMessage) {
      return validationError(validationMessage);
    }

    // Check subscription - requires PLUS or FAMILY with respite_requests feature
    const { data: hasFeature } = await supabaseService.rpc(
      "has_feature_access",
      {
        p_user_id: user.id,
        p_feature: "respite_requests",
      },
    );

    if (!hasFeature) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "FEATURE_NOT_AVAILABLE",
            message:
              "Availability requests require a Plus or Family subscription",
          },
          upgradeRequired: true,
        }),
        {
          status: 402,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Verify circle membership
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", body.circleId)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_NOT_MEMBER", message: "Not a circle member" },
        }),
        {
          status: 403,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Verify patient belongs to circle
    const { data: patient } = await supabaseService
      .from("patients")
      .select("id")
      .eq("id", body.patientId)
      .eq("circle_id", body.circleId)
      .single();

    if (!patient) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "NOT_FOUND",
            message: "Patient not found in this circle",
          },
        }),
        {
          status: 404,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Verify provider exists
    const { data: provider } = await supabaseService
      .from("respite_providers")
      .select("id, name")
      .eq("id", body.providerId)
      .eq("is_active", true)
      .single();

    if (!provider) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "NOT_FOUND", message: "Provider not found" },
        }),
        {
          status: 404,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Create request
    const { data: request, error: insertError } = await supabaseService
      .from("respite_requests")
      .insert({
        circle_id: body.circleId,
        patient_id: body.patientId,
        provider_id: body.providerId,
        created_by: user.id,
        start_date: body.startDate,
        end_date: body.endDate,
        special_considerations:
          body.specialConsiderations?.substring(0, 2000) || null,
        share_medications: body.shareMedications ?? false,
        share_contacts: body.shareContacts ?? false,
        share_dietary: body.shareDietary ?? false,
        share_full_summary: body.shareFullSummary ?? false,
        contact_method: body.contactMethod,
        contact_value: body.contactValue.trim().substring(0, 200),
        status: "PENDING",
      })
      .select("id, status, created_at")
      .single();

    if (insertError || !request) {
      console.error(
        "Respite request insert failed:",
        insertError?.code ?? "UNKNOWN",
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to create request",
          },
        }),
        {
          status: 500,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Create audit event (fail request if audit fails for security compliance)
    const { error: auditError } = await supabaseService
      .from("audit_events")
      .insert({
        circle_id: body.circleId,
        actor_user_id: user.id,
        event_type: "RESPITE_REQUEST_CREATED",
        object_type: "respite_request",
        object_id: request.id,
        metadata_json: {
          provider_id: body.providerId,
          provider_name: provider.name,
          share_medications: body.shareMedications,
          share_contacts: body.shareContacts,
          share_dietary: body.shareDietary,
          share_full_summary: body.shareFullSummary,
        },
      });

    if (auditError) {
      console.error(
        "CRITICAL: Audit event failed:",
        auditError.code ?? "UNKNOWN",
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUDIT_FAILED",
            message: "Failed to log security event",
          },
        }),
        {
          status: 500,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        request: {
          id: request.id,
          status: request.status,
          createdAt: request.created_at,
        },
      }),
      {
        status: 201,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Unexpected error in submit-respite-request");
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "INTERNAL_ERROR", message: "Internal server error" },
      }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});
