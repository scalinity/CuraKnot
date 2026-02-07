import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GenerateRequest {
  patient_id: string;
  included_types: string[]; // MEDICAL, FACILITY, PHARMACY, HOME_CARE, EMERGENCY, INSURANCE
  create_share_link?: boolean;
  share_link_ttl_days?: number;
}

interface GenerateResponse {
  success: boolean;
  export_id?: string;
  pdf_url?: string;
  share_link?: {
    token: string;
    url: string;
    expires_at: string;
  };
  provider_count?: number;
  error?: {
    code: string;
    message: string;
  };
}

interface ProviderData {
  id: string;
  title: string;
  type: string;
  category: string;
  content: Record<string, unknown>;
  updated_at: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "No authorization header",
          },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseServiceKey || !supabaseAnonKey) {
      console.error("Missing required environment variables");
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

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Verify user
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();

    if (userError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_INVALID_TOKEN", message: "Invalid token" },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: GenerateRequest = await req.json();
    const {
      patient_id,
      included_types: rawIncludedTypes = [
        "MEDICAL",
        "FACILITY",
        "PHARMACY",
        "HOME_CARE",
        "EMERGENCY",
      ],
      create_share_link = false,
      share_link_ttl_days = 7,
    } = body;

    if (!patient_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "patient_id is required",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate patient_id format (UUID)
    const uuidPattern =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(patient_id)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Invalid patient_id format",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate and sanitize included_types against allowed values
    const allowedTypes = [
      "MEDICAL",
      "FACILITY",
      "PHARMACY",
      "HOME_CARE",
      "EMERGENCY",
      "INSURANCE",
    ];
    const included_types = Array.isArray(rawIncludedTypes)
      ? rawIncludedTypes.filter(
          (t) => typeof t === "string" && allowedTypes.includes(t),
        )
      : allowedTypes.slice(0, 5); // Default if invalid

    if (included_types.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "At least one valid included_type is required",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate share link TTL (1-30 days)
    const validatedTtlDays = Math.min(Math.max(1, share_link_ttl_days), 30);

    // Get patient and verify circle membership in a single query to prevent IDOR
    // This joins patient with circle membership check to avoid leaking patient metadata
    const { data: patientWithMembership, error: patientError } =
      await supabaseService
        .from("patients")
        .select(
          `
        id,
        display_name,
        initials,
        circle_id,
        circle:circles!inner(
          members:circle_members!inner(role, status)
        )
      `,
        )
        .eq("id", patient_id)
        .eq("circle.members.user_id", user.id)
        .eq("circle.members.status", "ACTIVE")
        .single();

    if (patientError || !patientWithMembership) {
      // Return generic "not found" to prevent enumeration
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "NOT_FOUND", message: "Patient not found" },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const patient = {
      id: patientWithMembership.id,
      display_name: patientWithMembership.display_name,
      initials: patientWithMembership.initials,
      circle_id: patientWithMembership.circle_id,
    };

    // Check feature access (export requires PLUS+)
    const { data: hasExportAccess } = await supabaseService.rpc(
      "has_feature_access",
      {
        p_user_id: user.id,
        p_feature: "care_directory_export",
      },
    );

    if (!hasExportAccess) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "FEATURE_GATED",
            message: "Care Network export requires Plus or Family plan",
          },
        }),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create export using database function
    const { data: exportResult, error: exportError } =
      await supabaseService.rpc("create_care_network_export", {
        p_circle_id: patient.circle_id,
        p_patient_id: patient_id,
        p_user_id: user.id,
        p_included_types: included_types,
        p_create_share_link: create_share_link,
        p_share_link_ttl_hours: validatedTtlDays * 24,
      });

    if (exportError || exportResult?.error) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "EXPORT_FAILED",
            message:
              exportResult?.error ||
              exportError?.message ||
              "Failed to create export",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const exportId = exportResult.export_id;
    const content = exportResult.content;
    const providers: ProviderData[] = content.providers || [];

    // Sanitize provider data before report generation
    const sanitizedProviders = sanitizeProviderData(providers);

    // Generate text-based report content
    // Note: This produces a plain text document, not a binary PDF.
    // For true PDF generation, integrate a library like pdfkit or use a PDF service.
    const reportContent = generateReportContent({
      patientName: patient.display_name,
      patientInitials: patient.initials,
      providers: sanitizedProviders,
      generatedAt: new Date().toISOString(),
    });

    // Store as text file (labeled as .txt for transparency)
    const storageKey = `care-network/${patient.circle_id}/${exportId}.txt`;
    const reportBuffer = new TextEncoder().encode(reportContent);

    // Upload to storage
    const { error: uploadError } = await supabaseService.storage
      .from("exports")
      .upload(storageKey, reportBuffer, {
        contentType: "text/plain",
        upsert: true,
      });

    if (uploadError) {
      logSafeError("storage_upload_failed", uploadError);
      // Clean up the export record on upload failure
      await supabaseService
        .from("care_network_exports")
        .delete()
        .eq("id", exportId);

      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "UPLOAD_FAILED",
            message: "Failed to store export document",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update export with storage key
    const { error: updateError } = await supabaseService
      .from("care_network_exports")
      .update({ pdf_storage_key: storageKey })
      .eq("id", exportId);

    if (updateError) {
      logSafeError("database_update_failed", updateError);
      // Clean up the uploaded file on database update failure
      await supabaseService.storage.from("exports").remove([storageKey]);
      // Clean up the export record
      await supabaseService
        .from("care_network_exports")
        .delete()
        .eq("id", exportId);

      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to update export record",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get signed URL for download
    const { data: signedUrl, error: signedUrlError } =
      await supabaseService.storage
        .from("exports")
        .createSignedUrl(storageKey, 3600); // 1 hour expiry

    if (signedUrlError || !signedUrl?.signedUrl) {
      logSafeError("signed_url_generation_failed", signedUrlError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "URL_GENERATION_FAILED",
            message: "Failed to generate download URL",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build response
    // Note: pdf_url field kept for API compatibility but now serves text document
    const response: GenerateResponse = {
      success: true,
      export_id: exportId,
      pdf_url: signedUrl.signedUrl,
      provider_count: providers.length,
    };

    if (create_share_link && exportResult.share_link) {
      response.share_link = {
        token: exportResult.share_link.token,
        url: `${supabaseUrl}/functions/v1/resolve-share-link?token=${encodeURIComponent(exportResult.share_link.token)}`,
        expires_at: exportResult.share_link.expires_at,
      };
    }

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    logSafeError("unhandled_error", error);
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

// Add sanitization helper at top after corsHeaders
function sanitizeProviderData(providers: ProviderData[]): ProviderData[] {
  const allowedFields = ["title", "type", "category"];
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
    "type",
    "fax",
  ];

  return providers.map((p) => {
    const sanitized: Record<string, any> = {};

    // Copy only allowed top-level fields
    for (const field of allowedFields) {
      if ((p as any)[field] !== undefined) {
        sanitized[field] = (p as any)[field];
      }
    }

    // Sanitize content using allowlist
    if (p.content && typeof p.content === "object") {
      sanitized.content = {};
      for (const field of allowedContentFields) {
        if ((p.content as any)[field] !== undefined) {
          (sanitized.content as any)[field] = (p.content as any)[field];
        }
      }
    }

    return sanitized as ProviderData;
  });
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

interface ReportData {
  patientName: string;
  patientInitials: string;
  providers: ProviderData[];
  generatedAt: string;
}

function generateReportContent(data: ReportData): string {
  const lines: string[] = [];

  // Header
  lines.push("".padEnd(60, "="));
  lines.push(`CARE TEAM DIRECTORY`);
  lines.push(`For: ${data.patientName}`);
  lines.push(`Generated: ${new Date(data.generatedAt).toLocaleDateString()}`);
  lines.push("".padEnd(60, "="));
  lines.push("");

  // Group providers by category
  const grouped = groupProviders(data.providers);

  const categoryConfig: Record<string, { title: string; icon: string }> = {
    MEDICAL: { title: "MEDICAL PROVIDERS", icon: "+" },
    FACILITY: { title: "FACILITIES", icon: "#" },
    PHARMACY: { title: "PHARMACY", icon: "Rx" },
    HOME_CARE: { title: "HOME CARE", icon: "@" },
    EMERGENCY: { title: "EMERGENCY CONTACTS", icon: "!" },
    INSURANCE: { title: "INSURANCE", icon: "$" },
  };

  for (const [category, providers] of Object.entries(grouped)) {
    const config = categoryConfig[category] || { title: category, icon: "*" };

    lines.push("".padEnd(50, "-"));
    lines.push(`[${config.icon}] ${config.title}`);
    lines.push("".padEnd(50, "-"));

    for (const provider of providers) {
      const content = provider.content || {};
      lines.push("");
      lines.push(`  ${provider.title}`);

      if (content.role) {
        lines.push(`    Role: ${formatRole(content.role as string)}`);
      }
      if (content.organization) {
        lines.push(`    Organization: ${content.organization}`);
      }
      if (content.type) {
        lines.push(`    Type: ${formatFacilityType(content.type as string)}`);
      }
      if (content.phone) {
        lines.push(`    Phone: ${content.phone}`);
      }
      if (content.email) {
        lines.push(`    Email: ${content.email}`);
      }
      if (content.address) {
        lines.push(`    Address: ${content.address}`);
      }
      if (content.unit_room) {
        lines.push(`    Unit/Room: ${content.unit_room}`);
      }
      if (content.visiting_hours) {
        lines.push(`    Visiting Hours: ${content.visiting_hours}`);
      }
      // Insurance-specific fields
      if (content.provider) {
        lines.push(`    Provider: ${content.provider}`);
      }
      if (content.plan_name) {
        lines.push(`    Plan: ${content.plan_name}`);
      }
      if (content.member_id) {
        lines.push(`    Member ID: ${content.member_id}`);
      }
      if (content.group_number) {
        lines.push(`    Group #: ${content.group_number}`);
      }
    }
    lines.push("");
  }

  lines.push("".padEnd(60, "="));
  lines.push("Generated by CuraKnot - www.curaknot.com");
  lines.push("".padEnd(60, "="));

  return lines.join("\n");
}

function groupProviders(
  providers: ProviderData[],
): Record<string, ProviderData[]> {
  const grouped: Record<string, ProviderData[]> = {};

  for (const provider of providers) {
    const category = provider.category || "OTHER";
    if (!grouped[category]) {
      grouped[category] = [];
    }
    grouped[category].push(provider);
  }

  // Sort by category priority
  const order = [
    "MEDICAL",
    "FACILITY",
    "PHARMACY",
    "HOME_CARE",
    "EMERGENCY",
    "INSURANCE",
    "OTHER",
  ];
  const sorted: Record<string, ProviderData[]> = {};

  for (const cat of order) {
    if (grouped[cat]) {
      sorted[cat] = grouped[cat];
    }
  }

  return sorted;
}

function formatRole(role: string): string {
  const roleMap: Record<string, string> = {
    doctor: "Doctor",
    nurse: "Nurse",
    social_worker: "Social Worker",
    family: "Family",
    other: "Other",
  };
  return roleMap[role] || role;
}

function formatFacilityType(type: string): string {
  const typeMap: Record<string, string> = {
    hospital: "Hospital",
    nursing_home: "Nursing Home",
    rehab: "Rehabilitation Center",
    other: "Other",
  };
  return typeMap[type] || type;
}
