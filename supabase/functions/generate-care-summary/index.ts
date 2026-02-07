import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GenerateRequest {
  circle_id: string;
  patient_ids: string[];
  start_date: string;
  end_date: string;
  include_sections?: {
    handoffs?: boolean;
    med_changes?: boolean;
    open_questions?: boolean;
    tasks?: boolean;
    contacts?: boolean;
  };
}

interface GenerateResponse {
  success: boolean;
  export_id?: string;
  download_url?: string;
  expires_at?: string;
  page_count?: number;
  generated_at?: string;
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
      circle_id,
      patient_ids,
      start_date,
      end_date,
      include_sections = {
        handoffs: true,
        med_changes: true,
        open_questions: true,
        tasks: true,
        contacts: true,
      },
    } = body;

    // Verify membership
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_NOT_MEMBER",
            message: "Not a member of this circle",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch circle info
    const { data: circle } = await supabaseService
      .from("circles")
      .select("name")
      .eq("id", circle_id)
      .single();

    // Fetch patients
    const { data: patients } = await supabaseService
      .from("patients")
      .select("id, display_name")
      .in("id", patient_ids);

    // Fetch handoffs in date range
    let handoffs: any[] = [];
    if (include_sections.handoffs) {
      const { data } = await supabaseService
        .from("handoffs")
        .select("id, title, summary, type, published_at, created_by")
        .eq("circle_id", circle_id)
        .in("patient_id", patient_ids)
        .eq("status", "PUBLISHED")
        .gte("published_at", start_date)
        .lte("published_at", end_date)
        .order("published_at", { ascending: false });
      handoffs = data || [];
    }

    // Fetch medication changes from handoff revisions
    let medChanges: any[] = [];
    if (include_sections.med_changes && handoffs.length > 0) {
      const handoffIds = handoffs.map((h) => h.id);
      const { data: revisions } = await supabaseService
        .from("handoff_revisions")
        .select("structured_json")
        .in("handoff_id", handoffIds);

      revisions?.forEach((r) => {
        const json = r.structured_json;
        if (json?.changes?.med_changes) {
          medChanges.push(...json.changes.med_changes);
        }
      });
    }

    // Fetch open questions
    let questions: any[] = [];
    if (include_sections.open_questions && handoffs.length > 0) {
      const handoffIds = handoffs.map((h) => h.id);
      const { data: revisions } = await supabaseService
        .from("handoff_revisions")
        .select("structured_json")
        .in("handoff_id", handoffIds);

      revisions?.forEach((r) => {
        const json = r.structured_json;
        if (json?.questions_for_clinician) {
          questions.push(...json.questions_for_clinician);
        }
      });
    }

    // Fetch tasks
    let tasks: any[] = [];
    if (include_sections.tasks) {
      const { data } = await supabaseService
        .from("tasks")
        .select("id, title, status, due_at, priority")
        .eq("circle_id", circle_id)
        .in("patient_id", patient_ids)
        .eq("status", "OPEN");
      tasks = data || [];
    }

    // Fetch contacts
    let contacts: any[] = [];
    if (include_sections.contacts) {
      const { data } = await supabaseService
        .from("binder_items")
        .select("id, title, content_json")
        .eq("circle_id", circle_id)
        .in("patient_id", patient_ids)
        .eq("type", "CONTACT")
        .eq("is_active", true);
      contacts = data || [];
    }

    // Generate PDF content
    const pdfContent = generatePDFContent({
      circleName: circle?.name || "Care Circle",
      patients: patients || [],
      dateRange: { start: start_date, end: end_date },
      handoffs,
      medChanges,
      questions,
      tasks,
      contacts,
    });

    // In production: Use a PDF library like pdf-lib or jsPDF
    // For now, generate a simple text representation
    const exportId = crypto.randomUUID();
    const storageKey = `${circle_id}/${exportId}.pdf`;

    // Store "PDF" (placeholder - use actual PDF generation in production)
    const pdfBuffer = new TextEncoder().encode(pdfContent);

    await supabaseService.storage
      .from("exports")
      .upload(storageKey, pdfBuffer, {
        contentType: "application/pdf",
        upsert: true,
      });

    // Generate signed URL
    const { data: signedUrl } = await supabaseService.storage
      .from("exports")
      .createSignedUrl(storageKey, 3600);

    // Create audit event
    await supabaseService.from("audit_events").insert({
      circle_id,
      actor_user_id: user.id,
      event_type: "EXPORT_GENERATED",
      object_type: "export",
      object_id: exportId,
      metadata_json: {
        patient_ids,
        start_date,
        end_date,
        sections: include_sections,
      },
    });

    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 1);

    const response: GenerateResponse = {
      success: true,
      export_id: exportId,
      download_url: signedUrl?.signedUrl,
      expires_at: expiresAt.toISOString(),
      page_count: 1, // Placeholder
      generated_at: new Date().toISOString(),
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "EXPORT_PDF_FAILED", message: "Failed to generate PDF" },
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

interface PDFData {
  circleName: string;
  patients: { id: string; display_name: string }[];
  dateRange: { start: string; end: string };
  handoffs: any[];
  medChanges: any[];
  questions: any[];
  tasks: any[];
  contacts: any[];
}

function generatePDFContent(data: PDFData): string {
  const lines: string[] = [];

  // Header
  lines.push("═".repeat(60));
  lines.push(`CARE SUMMARY - ${data.circleName}`);
  lines.push(`Date Range: ${data.dateRange.start} to ${data.dateRange.end}`);
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push("═".repeat(60));
  lines.push("");

  // Patients
  lines.push("PATIENTS:");
  data.patients.forEach((p) => {
    lines.push(`  • ${p.display_name}`);
  });
  lines.push("");

  // Handoffs
  if (data.handoffs.length > 0) {
    lines.push("─".repeat(40));
    lines.push("RECENT HANDOFFS:");
    lines.push("─".repeat(40));
    data.handoffs.forEach((h) => {
      lines.push(`[${h.type}] ${h.title}`);
      lines.push(`  Published: ${h.published_at}`);
      if (h.summary) {
        lines.push(`  ${h.summary.substring(0, 200)}...`);
      }
      lines.push("");
    });
  }

  // Medication Changes
  if (data.medChanges.length > 0) {
    lines.push("─".repeat(40));
    lines.push("MEDICATION CHANGES:");
    lines.push("─".repeat(40));
    data.medChanges.forEach((m) => {
      lines.push(`  • ${m.name}: ${m.change}`);
      if (m.details) {
        lines.push(`    ${m.details}`);
      }
    });
    lines.push("");
  }

  // Questions for Clinician
  if (data.questions.length > 0) {
    lines.push("─".repeat(40));
    lines.push("QUESTIONS FOR CLINICIAN:");
    lines.push("─".repeat(40));
    data.questions.forEach((q, i) => {
      lines.push(`  ${i + 1}. ${q.question}`);
    });
    lines.push("");
  }

  // Outstanding Tasks
  if (data.tasks.length > 0) {
    lines.push("─".repeat(40));
    lines.push("OUTSTANDING TASKS:");
    lines.push("─".repeat(40));
    data.tasks.forEach((t) => {
      const dueStr = t.due_at ? ` (Due: ${t.due_at})` : "";
      lines.push(`  □ [${t.priority}] ${t.title}${dueStr}`);
    });
    lines.push("");
  }

  // Key Contacts
  if (data.contacts.length > 0) {
    lines.push("─".repeat(40));
    lines.push("KEY CONTACTS:");
    lines.push("─".repeat(40));
    data.contacts.forEach((c) => {
      const content = c.content_json;
      lines.push(`  ${c.title}`);
      if (content?.phone) lines.push(`    Phone: ${content.phone}`);
      if (content?.email) lines.push(`    Email: ${content.email}`);
    });
    lines.push("");
  }

  lines.push("═".repeat(60));
  lines.push("END OF CARE SUMMARY");
  lines.push("═".repeat(60));

  return lines.join("\n");
}
