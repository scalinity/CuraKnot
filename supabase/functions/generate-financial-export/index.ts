import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ExportRequest {
  circle_id: string;
  patient_id?: string;
  start_date?: string;
  end_date?: string;
  format: "PDF" | "CSV";
  include_attachments?: boolean;
}

interface FinancialItem {
  id: string;
  kind: string;
  vendor: string | null;
  amount_cents: number | null;
  currency: string;
  due_at: string | null;
  status: string;
  reference_id: string | null;
  notes: string | null;
  created_at: string;
  patient?: { display_name: string } | null;
}

interface ExportResponse {
  success: boolean;
  export_url?: string;
  filename?: string;
  item_count?: number;
  summary?: {
    total_amount: number;
    by_status: Record<string, number>;
    by_kind: Record<string, number>;
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

    // Get current user
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

    // Parse request
    const body: ExportRequest = await req.json();
    const { circle_id, patient_id, start_date, end_date, format } = body;

    if (!circle_id || !format) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Missing required fields: circle_id and format",
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
            message: "Contributors+ required to export financial data",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build query
    let query = supabaseService
      .from("financial_items")
      .select("*, patient:patients(display_name)")
      .eq("circle_id", circle_id)
      .order("created_at", { ascending: false });

    if (patient_id) {
      query = query.eq("patient_id", patient_id);
    }

    if (start_date) {
      query = query.gte("created_at", start_date);
    }

    if (end_date) {
      query = query.lte("created_at", end_date + "T23:59:59Z");
    }

    const { data: items, error: itemsError } = await query;

    if (itemsError) {
      console.error("Query error:", itemsError.code || "unknown");
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to fetch financial items",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate summary
    const summary = {
      total_amount: 0,
      by_status: {} as Record<string, number>,
      by_kind: {} as Record<string, number>,
    };

    for (const item of items as FinancialItem[]) {
      summary.total_amount += item.amount_cents || 0;
      summary.by_status[item.status] =
        (summary.by_status[item.status] || 0) + 1;
      summary.by_kind[item.kind] = (summary.by_kind[item.kind] || 0) + 1;
    }

    // Generate export based on format
    let content: string;
    let mimeType: string;
    let extension: string;

    if (format === "CSV") {
      content = generateCSV(items as FinancialItem[]);
      mimeType = "text/csv";
      extension = "csv";
    } else {
      // For PDF, generate HTML content that can be converted
      content = generatePDFContent(items as FinancialItem[], summary);
      mimeType = "text/html";
      extension = "html"; // Would be converted to PDF in production
    }

    // Generate filename
    const timestamp = new Date().toISOString().split("T")[0];
    const filename = `financial-export-${timestamp}.${extension}`;

    // Store in exports bucket
    const { data: uploadData, error: uploadError } =
      await supabaseService.storage
        .from("exports")
        .upload(`${circle_id}/${filename}`, content, {
          contentType: mimeType,
          upsert: true,
        });

    if (uploadError) {
      console.error("Upload error: storage_error");
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "STORAGE_ERROR",
            message: "Failed to generate export file",
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
      .createSignedUrl(`${circle_id}/${filename}`, 3600); // 1 hour

    // Create audit event
    await supabaseService.from("audit_events").insert({
      circle_id,
      actor_user_id: user.id,
      event_type: "FINANCIAL_EXPORT_GENERATED",
      object_type: "financial_export",
      metadata_json: {
        format,
        item_count: items.length,
        date_range: { start_date, end_date },
      },
    });

    const response: ExportResponse = {
      success: true,
      export_url: signedUrl?.signedUrl,
      filename,
      item_count: items.length,
      summary: {
        total_amount: summary.total_amount / 100, // Convert to dollars
        by_status: summary.by_status,
        by_kind: summary.by_kind,
      },
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(
      "Financial export error:",
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

function generateCSV(items: FinancialItem[]): string {
  const headers = [
    "Date",
    "Type",
    "Vendor",
    "Amount",
    "Currency",
    "Status",
    "Due Date",
    "Reference",
    "Patient",
    "Notes",
  ];

  const rows = items.map((item) => [
    new Date(item.created_at).toLocaleDateString(),
    item.kind,
    item.vendor || "",
    item.amount_cents ? (item.amount_cents / 100).toFixed(2) : "",
    item.currency,
    item.status,
    item.due_at ? new Date(item.due_at).toLocaleDateString() : "",
    item.reference_id || "",
    item.patient?.display_name || "",
    (item.notes || "").replace(/"/g, '""'),
  ]);

  const csvContent = [
    headers.join(","),
    ...rows.map((row) => row.map((cell) => `"${cell}"`).join(",")),
  ].join("\n");

  return csvContent;
}

function generatePDFContent(
  items: FinancialItem[],
  summary: {
    total_amount: number;
    by_status: Record<string, number>;
    by_kind: Record<string, number>;
  },
): string {
  const totalDollars = (summary.total_amount / 100).toFixed(2);

  return `
<!DOCTYPE html>
<html>
<head>
  <title>Financial Export</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; margin: 40px; }
    h1 { color: #1a1a1a; }
    .summary { background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0; }
    .summary-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
    .summary-item { text-align: center; }
    .summary-value { font-size: 24px; font-weight: bold; }
    .summary-label { color: #666; font-size: 14px; }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
    th { background: #f9f9f9; font-weight: 600; }
    .status-open { color: #2563eb; }
    .status-paid { color: #16a34a; }
    .status-denied { color: #dc2626; }
    .footer { margin-top: 40px; font-size: 12px; color: #666; }
  </style>
</head>
<body>
  <h1>Financial Summary</h1>
  <p>Generated: ${new Date().toLocaleString()}</p>
  
  <div class="summary">
    <div class="summary-grid">
      <div class="summary-item">
        <div class="summary-value">$${totalDollars}</div>
        <div class="summary-label">Total Amount</div>
      </div>
      <div class="summary-item">
        <div class="summary-value">${items.length}</div>
        <div class="summary-label">Total Items</div>
      </div>
      <div class="summary-item">
        <div class="summary-value">${summary.by_status["OPEN"] || 0}</div>
        <div class="summary-label">Open Items</div>
      </div>
    </div>
  </div>

  <table>
    <thead>
      <tr>
        <th>Date</th>
        <th>Type</th>
        <th>Vendor</th>
        <th>Amount</th>
        <th>Status</th>
        <th>Due Date</th>
      </tr>
    </thead>
    <tbody>
      ${items
        .map(
          (item) => `
        <tr>
          <td>${new Date(item.created_at).toLocaleDateString()}</td>
          <td>${item.kind}</td>
          <td>${item.vendor || "-"}</td>
          <td>${item.amount_cents ? "$" + (item.amount_cents / 100).toFixed(2) : "-"}</td>
          <td class="status-${item.status.toLowerCase()}">${item.status}</td>
          <td>${item.due_at ? new Date(item.due_at).toLocaleDateString() : "-"}</td>
        </tr>
      `,
        )
        .join("")}
    </tbody>
  </table>

  <div class="footer">
    <p>This document was generated by CuraKnot. For questions, contact your care circle administrator.</p>
  </div>
</body>
</html>
  `;
}
