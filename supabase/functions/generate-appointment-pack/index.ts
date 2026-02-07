import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GeneratePackRequest {
  circle_id: string;
  patient_id: string;
  range_start: string;
  range_end: string;
  template?: string;
  create_share_link?: boolean;
  share_link_ttl_hours?: number;
}

interface GeneratePackResponse {
  success: boolean;
  pack_id?: string;
  pdf_url?: string;
  share_link?: {
    token: string;
    url: string;
    expires_at: string;
  };
  content_summary?: {
    handoffs: number;
    med_changes: number;
    open_tasks: number;
    questions: number;
  };
  error?: {
    code: string;
    message: string;
  };
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "Invalid or expired token",
          },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: GeneratePackRequest = await req.json();
    const {
      circle_id,
      patient_id,
      range_start,
      range_end,
      template = "general",
      create_share_link = false,
      share_link_ttl_hours = 24,
    } = body;

    if (!circle_id || !patient_id || !range_start || !range_end) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Missing required fields",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check membership
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership || membership.role === "VIEWER") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_ROLE_FORBIDDEN",
            message: "Insufficient permissions",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Compose content using database function
    const { data: content, error: contentError } = await supabaseService.rpc(
      "compose_appointment_pack_content",
      {
        p_circle_id: circle_id,
        p_patient_id: patient_id,
        p_range_start: range_start,
        p_range_end: range_end,
      },
    );

    if (contentError) {
      console.error(
        "Content composition error:",
        contentError.code || "unknown",
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to compose content",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate PDF HTML
    const pdfHtml = generatePackPDF(content, template);
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const filename = `visit-pack-${timestamp}.html`;
    const storageKey = `${circle_id}/${patient_id}/${filename}`;

    // Upload to storage
    const { error: uploadError } = await supabaseService.storage
      .from("exports")
      .upload(storageKey, pdfHtml, { contentType: "text/html", upsert: true });

    if (uploadError) {
      console.error("Upload error:", uploadError);
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "STORAGE_ERROR", message: "Failed to upload pack" },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create appointment pack record
    const { data: pack, error: packError } = await supabaseService
      .from("appointment_packs")
      .insert({
        circle_id,
        patient_id,
        created_by: user.id,
        range_start,
        range_end,
        template,
        content_json: content,
        pdf_object_key: storageKey,
      })
      .select()
      .single();

    if (packError) {
      console.error("Pack insert error:", packError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to create pack record",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get signed URL
    const { data: signedUrl } = await supabaseService.storage
      .from("exports")
      .createSignedUrl(storageKey, 3600);

    // Create share link if requested
    let shareLink:
      | { token: string; url: string; expires_at: string }
      | undefined;

    if (create_share_link) {
      const { data: linkData, error: linkError } = await supabaseService.rpc(
        "create_share_link",
        {
          p_circle_id: circle_id,
          p_user_id: user.id,
          p_object_type: "appointment_pack",
          p_object_id: pack.id,
          p_ttl_hours: share_link_ttl_hours,
        },
      );

      if (!linkError && linkData && !linkData.error) {
        const baseUrl =
          Deno.env.get("PUBLIC_SITE_URL") || "https://app.curaknot.com";
        shareLink = {
          token: linkData.token,
          url: `${baseUrl}/share/${linkData.token}`,
          expires_at: linkData.expires_at,
        };
      }
    }

    // Create audit event
    await supabaseService.from("audit_events").insert({
      circle_id,
      actor_user_id: user.id,
      event_type: "APPOINTMENT_PACK_GENERATED",
      object_type: "appointment_pack",
      object_id: pack.id,
      metadata_json: {
        template,
        range_start,
        range_end,
        has_share_link: !!shareLink,
      },
    });

    const response: GeneratePackResponse = {
      success: true,
      pack_id: pack.id,
      pdf_url: signedUrl?.signedUrl,
      share_link: shareLink,
      content_summary: content.counts,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(
      "Appointment pack error:",
      error instanceof Error ? error.name : "unknown",
    );
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

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function generatePackPDF(content: any, template: string): string {
  const patientName = escapeHtml(content.patient?.name || "Patient");
  const rangeStart = new Date(content.range?.start).toLocaleDateString();
  const rangeEnd = new Date(content.range?.end).toLocaleDateString();
  const generatedAt = new Date(content.generated_at).toLocaleString();

  return `
<!DOCTYPE html>
<html>
<head>
  <title>Visit Pack - ${patientName}</title>
  <style>
    * { box-sizing: border-box; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0; padding: 40px; color: #1a1a1a; line-height: 1.5;
    }
    .header { border-bottom: 2px solid #2563eb; padding-bottom: 20px; margin-bottom: 30px; }
    .header h1 { margin: 0 0 8px 0; color: #2563eb; }
    .header .meta { color: #666; font-size: 14px; }
    .section { margin-bottom: 30px; }
    .section h2 { 
      color: #1a1a1a; font-size: 18px; margin: 0 0 16px 0;
      padding-bottom: 8px; border-bottom: 1px solid #e5e5e5;
    }
    .card { background: #f9fafb; padding: 16px; border-radius: 8px; margin-bottom: 12px; }
    .card-title { font-weight: 600; margin-bottom: 4px; }
    .card-meta { font-size: 13px; color: #666; }
    .card-body { margin-top: 8px; }
    .badge { 
      display: inline-block; padding: 2px 8px; border-radius: 12px;
      font-size: 12px; font-weight: 500;
    }
    .badge-high { background: #fee2e2; color: #dc2626; }
    .badge-med { background: #fef3c7; color: #d97706; }
    .badge-low { background: #dbeafe; color: #2563eb; }
    .questions-list { list-style: none; padding: 0; margin: 0; }
    .questions-list li { 
      padding: 12px 16px; background: #fffbeb; border-left: 3px solid #f59e0b;
      margin-bottom: 8px; border-radius: 0 8px 8px 0;
    }
    .empty { color: #9ca3af; font-style: italic; }
    .footer { 
      margin-top: 40px; padding-top: 20px; border-top: 1px solid #e5e5e5;
      font-size: 12px; color: #9ca3af; text-align: center;
    }
    @media print {
      body { padding: 20px; }
      .section { break-inside: avoid; }
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Visit Preparation Pack</h1>
    <div class="meta">
      <strong>${patientName}</strong> | ${rangeStart} — ${rangeEnd}<br>
      Generated: ${generatedAt}
    </div>
  </div>

  <div class="section">
    <h2>Questions to Ask (${content.questions?.length || 0})</h2>
    ${
      content.questions?.length > 0
        ? `
      <ul class="questions-list">
        ${content.questions
          .map(
            (q: any) => `
          <li>
            <span class="badge badge-${q.priority?.toLowerCase() || "med"}">${q.priority || "MEDIUM"}</span>
            ${escapeHtml(q.question || "")}
          </li>
        `,
          )
          .join("")}
      </ul>
    `
        : '<p class="empty">No questions to ask.</p>'
    }
  </div>

  <div class="section">
    <h2>Recent Updates (${content.handoffs?.length || 0})</h2>
    ${
      content.handoffs?.length > 0
        ? content.handoffs
            .slice(0, 5)
            .map(
              (h: any) => `
        <div class="card">
          <div class="card-title">${escapeHtml(h.title || "")}</div>
          <div class="card-meta">${escapeHtml(h.type || "")} • ${new Date(h.created_at).toLocaleDateString()}</div>
          ${h.summary ? `<div class="card-body">${escapeHtml(h.summary)}</div>` : ""}
        </div>
      `,
            )
            .join("")
        : '<p class="empty">No recent updates in this period.</p>'
    }
  </div>

  <div class="section">
    <h2>Medication Changes (${content.med_changes?.length || 0})</h2>
    ${
      content.med_changes?.length > 0
        ? content.med_changes
            .map(
              (m: any) => `
        <div class="card">
          <div class="card-title">${escapeHtml(m.name || "")}</div>
          <div class="card-meta">Updated: ${new Date(m.updated_at).toLocaleDateString()}</div>
        </div>
      `,
            )
            .join("")
        : '<p class="empty">No medication changes in this period.</p>'
    }
  </div>

  <div class="section">
    <h2>Open Action Items (${content.open_tasks?.length || 0})</h2>
    ${
      content.open_tasks?.length > 0
        ? content.open_tasks
            .map(
              (t: any) => `
        <div class="card">
          <div class="card-title">
            <span class="badge badge-${t.priority?.toLowerCase() || "med"}">${t.priority || "MED"}</span>
            ${escapeHtml(t.title || "")}
          </div>
          ${t.due_at ? `<div class="card-meta">Due: ${new Date(t.due_at).toLocaleDateString()}</div>` : ""}
        </div>
      `,
            )
            .join("")
        : '<p class="empty">No open action items.</p>'
    }
  </div>

  <div class="footer">
    <p>This document was generated by CuraKnot for caregiver use only.<br>
    Not a medical record. Verify all information with healthcare providers.</p>
  </div>
</body>
</html>
  `;
}
