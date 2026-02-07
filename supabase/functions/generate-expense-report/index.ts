import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ExpenseRow {
  expense_date: string;
  category: string;
  description: string;
  vendor_name: string | null;
  amount: number;
  covered_by_insurance: number;
  is_recurring: boolean;
  receipt_storage_key: string | null;
}

const ALLOWED_ORIGINS = [
  "http://localhost:54321",
  Deno.env.get("SUPABASE_URL")!,
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin)
    ? origin
    : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    Vary: "Origin",
  };
}

interface ExpenseReportRequest {
  circle_id: string;
  patient_id: string;
  start_date: string;
  end_date: string;
  format: "PDF" | "CSV";
  include_receipts?: boolean;
}

interface ExpenseReportResponse {
  success: boolean;
  report_url?: string;
  total_expenses?: number;
  by_category?: Record<string, number>;
  expense_count?: number;
  expires_at?: string;
  error?: {
    code: string;
    message: string;
  };
}

const FINANCIAL_DISCLAIMER =
  "This is not financial advice. Consult a qualified financial professional for personalized guidance. Data is provided for informational purposes only.";

// Minimum role required: CONTRIBUTOR (VIEWERs cannot export)
const EXPORT_ALLOWED_ROLES = new Set(["CONTRIBUTOR", "ADMIN", "OWNER"]);

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req);

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
        } as ExpenseReportResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseServiceKey || !supabaseAnonKey) {
      console.error("Missing required environment variables");
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CONFIGURATION_ERROR",
            message: "Server configuration error",
          },
        } as ExpenseReportResponse),
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

    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_INVALID_TOKEN", message: "Invalid token" },
        } as ExpenseReportResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate Content-Type
    const contentType = req.headers.get("Content-Type") || "";
    if (!contentType.includes("application/json")) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_CONTENT_TYPE",
            message: "Content-Type must be application/json",
          },
        } as ExpenseReportResponse),
        {
          status: 415,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: ExpenseReportRequest = await req.json();
    const {
      circle_id,
      patient_id,
      start_date,
      end_date,
      format,
      include_receipts,
    } = body;

    // Validate required fields
    if (!circle_id || !patient_id || !start_date || !end_date) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "MISSING_FIELDS",
            message:
              "circle_id, patient_id, start_date, and end_date are required",
          },
        } as ExpenseReportResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate date format
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(start_date) || !dateRegex.test(end_date)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_DATE_RANGE",
            message: "Invalid date format. Use YYYY-MM-DD",
          },
        } as ExpenseReportResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const startParsed = new Date(start_date);
    const endParsed = new Date(end_date);

    if (isNaN(startParsed.getTime()) || isNaN(endParsed.getTime())) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_DATE_RANGE",
            message: "Invalid date values",
          },
        } as ExpenseReportResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (startParsed > endParsed) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_DATE_RANGE",
            message: "start_date must be before or equal to end_date",
          },
        } as ExpenseReportResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate format
    if (format !== "PDF" && format !== "CSV") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_FORMAT",
            message: "Format must be PDF or CSV",
          },
        } as ExpenseReportResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify circle membership and role
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
        } as ExpenseReportResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check role: VIEWER cannot export reports
    if (!EXPORT_ALLOWED_ROLES.has(membership.role)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INSUFFICIENT_ROLE",
            message: "Insufficient permissions to export reports",
          },
        } as ExpenseReportResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check subscription tier - expense report export requires PLUS or FAMILY
    const { data: subscription } = await supabaseService
      .from("subscriptions")
      .select("plan_id, status")
      .eq("user_id", user.id)
      .in("status", ["ACTIVE", "TRIALING"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const userPlan = subscription?.plan_id || "FREE";

    if (userPlan === "FREE") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SUBSCRIPTION_REQUIRED",
            message:
              "Expense report export requires a paid plan. Please upgrade.",
          },
        } as ExpenseReportResponse),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch patient info
    const { data: patient } = await supabaseService
      .from("patients")
      .select("id, display_name")
      .eq("id", patient_id)
      .eq("circle_id", circle_id)
      .single();

    if (!patient) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PATIENT_NOT_FOUND",
            message: "Patient not found in this circle",
          },
        } as ExpenseReportResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch expenses in date range using correct column names
    const { data: expenses, error: expenseError } = await supabaseService
      .from("care_expenses")
      .select(
        "id, expense_date, category, description, vendor_name, amount, covered_by_insurance, is_recurring, receipt_storage_key",
      )
      .eq("circle_id", circle_id)
      .eq("patient_id", patient_id)
      .gte("expense_date", start_date)
      .lte("expense_date", end_date)
      .order("expense_date", { ascending: true });

    if (expenseError) {
      console.error("Error fetching expenses:", expenseError.message);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "QUERY_ERROR",
            message: "Failed to fetch expense data",
          },
        } as ExpenseReportResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const expenseList = expenses || [];

    // Calculate totals using integer arithmetic to avoid floating point issues
    let totalCents = 0;
    let coveredCents = 0;
    const byCategoryCents: Record<string, number> = {};

    for (const expense of expenseList) {
      const amountCents = Math.round((Number(expense.amount) || 0) * 100);
      // Clamp insurance coverage to amount (defense in depth)
      const rawInsuranceCents = Math.round(
        (Number(expense.covered_by_insurance) || 0) * 100,
      );
      const insuranceCents = Math.min(rawInsuranceCents, amountCents);
      totalCents += amountCents;
      coveredCents += insuranceCents;

      const category = expense.category || "Other";
      byCategoryCents[category] =
        (byCategoryCents[category] || 0) + amountCents;
    }

    const totalExpenses = totalCents / 100;
    const totalCovered = coveredCents / 100;
    const totalOOP = (totalCents - coveredCents) / 100;

    const byCategory: Record<string, number> = {};
    for (const [key, cents] of Object.entries(byCategoryCents)) {
      byCategory[key] = cents / 100;
    }

    // Generate report content
    let reportBuffer: Uint8Array;
    let reportContentType: string;
    let fileExtension: string;

    if (format === "CSV") {
      const csvContent = generateCSV(
        expenseList,
        totalExpenses,
        totalCovered,
        totalOOP,
        patient.display_name,
        start_date,
        end_date,
      );
      reportBuffer = new TextEncoder().encode(csvContent);
      reportContentType = "text/csv";
      fileExtension = "csv";
    } else {
      // Generate text-based report (production would use a PDF library)
      const textContent = generateTextReport(
        patient.display_name,
        start_date,
        end_date,
        expenseList,
        totalExpenses,
        totalCovered,
        totalOOP,
        byCategory,
      );
      reportBuffer = new TextEncoder().encode(textContent);
      reportContentType = "text/plain";
      fileExtension = "txt";
    }

    // Upload to care-expense-reports storage bucket
    const exportId = crypto.randomUUID();
    const storageKey = `${circle_id}/${patient_id}/expense-report-${exportId}.${fileExtension}`;

    const { error: uploadError } = await supabaseService.storage
      .from("care-expense-reports")
      .upload(storageKey, reportBuffer, {
        contentType: reportContentType,
        cacheControl: "3600",
      });

    if (uploadError) {
      console.error("Upload error:", uploadError.message);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "UPLOAD_ERROR",
            message: "Failed to upload report",
          },
        } as ExpenseReportResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create signed URL (1 hour expiry)
    const { data: signedUrl } = await supabaseService.storage
      .from("care-expense-reports")
      .createSignedUrl(storageKey, 3600);

    // Log audit event
    await supabaseService.from("audit_events").insert({
      circle_id,
      actor_user_id: user.id,
      event_type: "EXPENSE_REPORT_EXPORTED",
      object_type: "expense_report",
      object_id: exportId,
      metadata_json: {
        patient_id,
        start_date,
        end_date,
        format,
        include_receipts: include_receipts || false,
        expense_count: expenseList.length,
        total_expenses: totalExpenses,
      },
    });

    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 1);

    const response: ExpenseReportResponse = {
      success: true,
      report_url: signedUrl?.signedUrl,
      total_expenses: totalExpenses,
      by_category: byCategory,
      expense_count: expenseList.length,
      expires_at: expiresAt.toISOString(),
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const corsHeaders = getCorsHeaders(req);
    console.error("Error:", (error as Error).message);
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "GENERATION_ERROR",
          message: "Failed to generate expense report",
        },
      } as ExpenseReportResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Sanitize a value for CSV output to prevent formula injection.
 * Prefix any value starting with =, +, -, @, tab, or carriage return
 * with a single quote to neutralize it as a formula.
 */
function sanitizeCSVValue(value: string | number | null | undefined): string {
  if (value === null || value === undefined) return '""';
  const str = String(value);
  // Remove C0 control characters, DEL, and C1 control characters
  let cleaned = str.replace(/[\x00-\x1F\x7F-\x9F]/g, "");
  // Escape double quotes
  let escaped = cleaned.replace(/"/g, '""');
  // Prevent formula injection: prefix dangerous characters (including tab/CR)
  if (/^[=+\-@\t\r]/.test(escaped)) {
    escaped = "'" + escaped;
  }
  return `"${escaped}"`;
}

function generateCSV(
  expenses: ExpenseRow[],
  total: number,
  covered: number,
  oop: number,
  patientName: string,
  startDate: string,
  endDate: string,
): string {
  const lines: string[] = [];

  // Column headers
  lines.push(
    "Date,Category,Description,Vendor,Amount,Insurance Covered,Out of Pocket,Recurring,Has Receipt",
  );

  for (const expense of expenses) {
    const amountVal = Number(expense.amount) || 0;
    const insuranceVal = Number(expense.covered_by_insurance) || 0;
    const oopVal = amountVal - insuranceVal;

    const row = [
      sanitizeCSVValue(expense.expense_date),
      sanitizeCSVValue(expense.category),
      sanitizeCSVValue(expense.description),
      sanitizeCSVValue(expense.vendor_name),
      sanitizeCSVValue(amountVal.toFixed(2)),
      sanitizeCSVValue(insuranceVal.toFixed(2)),
      sanitizeCSVValue(oopVal.toFixed(2)),
      sanitizeCSVValue(expense.is_recurring ? "Yes" : "No"),
      sanitizeCSVValue(expense.receipt_storage_key ? "Yes" : "No"),
    ];
    lines.push(row.join(","));
  }

  // Summary
  lines.push("");
  lines.push(
    `${sanitizeCSVValue(`Report for ${patientName}`)},${sanitizeCSVValue(`${startDate} to ${endDate}`)}`,
  );
  lines.push(`Total,,,,${sanitizeCSVValue(total.toFixed(2))}`);
  lines.push(`Insurance Covered,,,,,${sanitizeCSVValue(covered.toFixed(2))}`);
  lines.push(`Out of Pocket,,,,,,${sanitizeCSVValue(oop.toFixed(2))}`);
  lines.push("");
  lines.push(sanitizeCSVValue(FINANCIAL_DISCLAIMER));

  return lines.join("\n");
}

function generateTextReport(
  patientName: string,
  startDate: string,
  endDate: string,
  expenses: ExpenseRow[],
  totalExpenses: number,
  totalCovered: number,
  totalOOP: number,
  byCategory: Record<string, number>,
): string {
  const lines: string[] = [];
  const separator = "=".repeat(60);
  const thinSep = "-".repeat(60);

  lines.push(separator);
  lines.push("CARE EXPENSE REPORT");
  lines.push(separator);
  lines.push("");
  lines.push(`Patient: ${patientName}`);
  lines.push(`Period: ${startDate} to ${endDate}`);
  lines.push(`Generated: ${new Date().toISOString().split("T")[0]}`);
  lines.push("");
  lines.push(thinSep);
  lines.push("SUMMARY");
  lines.push(thinSep);
  lines.push(`Total Expenses:     $${totalExpenses.toFixed(2)}`);
  lines.push(`Insurance Covered:  $${totalCovered.toFixed(2)}`);
  lines.push(`Out of Pocket:      $${totalOOP.toFixed(2)}`);
  lines.push(`Number of Expenses: ${expenses.length}`);
  lines.push("");

  // Category breakdown
  lines.push(thinSep);
  lines.push("BY CATEGORY");
  lines.push(thinSep);
  const sortedCategories = Object.entries(byCategory).sort(
    ([, a], [, b]) => b - a,
  );
  for (const [category, amount] of sortedCategories) {
    const pct =
      totalExpenses > 0 ? ((amount / totalExpenses) * 100).toFixed(1) : "0.0";
    lines.push(
      `  ${category.padEnd(20)} $${amount.toFixed(2).padStart(10)} (${pct}%)`,
    );
  }
  lines.push("");

  // Expense details
  if (expenses.length > 0) {
    lines.push(thinSep);
    lines.push("EXPENSE DETAILS");
    lines.push(thinSep);
    lines.push("");

    for (const expense of expenses) {
      const amountVal = Number(expense.amount) || 0;
      const insuranceVal = Number(expense.covered_by_insurance) || 0;
      const oopVal = amountVal - insuranceVal;

      lines.push(`Date: ${expense.expense_date}`);
      lines.push(`Category: ${expense.category}`);
      lines.push(`Description: ${expense.description}`);
      if (expense.vendor_name) {
        lines.push(`Vendor: ${expense.vendor_name}`);
      }
      lines.push(`Amount: $${amountVal.toFixed(2)}`);
      if (insuranceVal > 0) {
        lines.push(`Insurance: $${insuranceVal.toFixed(2)}`);
        lines.push(`Out of Pocket: $${oopVal.toFixed(2)}`);
      }
      if (expense.is_recurring) {
        lines.push("Recurring: Yes");
      }
      lines.push("");
    }
  } else {
    lines.push("");
    lines.push("No expenses found for the selected date range.");
    lines.push("");
  }

  // Footer with disclaimer
  lines.push(separator);
  lines.push("DISCLAIMER");
  lines.push(separator);
  lines.push(FINANCIAL_DISCLAIMER);
  lines.push(separator);

  return lines.join("\n");
}
