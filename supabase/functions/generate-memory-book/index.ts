import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  PDFDocument,
  rgb,
  StandardFonts,
  PageSizes,
} from "https://esm.sh/pdf-lib@1.17.1";

// ============================================================================
// CORS Headers
// ============================================================================

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ============================================================================
// Types
// ============================================================================

interface MemoryBookRequest {
  circleId: string;
  startDate: string; // ISO date (YYYY-MM-DD)
  endDate: string; // ISO date (YYYY-MM-DD)
  includePrivate: boolean;
}

interface MemoryBookResponse {
  url: string;
  expiresAt: string;
  entryCount: number;
  photoCount: number;
}

interface ErrorResponse {
  code: string;
  message: string;
}

interface JournalEntry {
  id: string;
  circle_id: string;
  patient_id: string;
  created_by: string;
  entry_type: "GOOD_MOMENT" | "MILESTONE";
  title: string | null;
  content: string;
  milestone_type: string | null;
  photo_storage_keys: string[];
  visibility: "PRIVATE" | "CIRCLE";
  entry_date: string;
  created_at: string;
}

interface PatientInfo {
  id: string;
  first_name: string;
  last_name: string;
}

interface UserInfo {
  id: string;
  full_name: string;
}

// ============================================================================
// Text Wrapping Helper
// ============================================================================

function wrapText(text: string, maxCharsPerLine: number): string[] {
  const words = text.split(" ");
  const lines: string[] = [];
  let currentLine = "";

  for (const word of words) {
    const testLine = currentLine + (currentLine ? " " : "") + word;
    if (testLine.length > maxCharsPerLine) {
      if (currentLine) {
        lines.push(currentLine);
      }
      currentLine = word;
    } else {
      currentLine = testLine;
    }
  }

  if (currentLine) {
    lines.push(currentLine);
  }

  return lines;
}

// ============================================================================
// Date Formatting
// ============================================================================

function formatDate(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

function formatDateShort(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

// ============================================================================
// PDF Generation
// ============================================================================

async function generatePDF(
  entries: JournalEntry[],
  patient: PatientInfo | null,
  dateRange: { start: string; end: string },
): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.create();
  const helvetica = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const helveticaBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const helveticaOblique = await pdfDoc.embedFont(
    StandardFonts.HelveticaOblique,
  );

  const pageWidth = PageSizes.Letter[0];
  const pageHeight = PageSizes.Letter[1];
  const margin = 50;
  const lineHeight = 16;
  const paragraphSpacing = 24;

  // Colors
  const textColor = rgb(0.2, 0.2, 0.2);
  const secondaryColor = rgb(0.5, 0.5, 0.5);
  const purpleColor = rgb(0.5, 0.3, 0.7);

  // -------------------------------------------------------------------------
  // Title Page
  // -------------------------------------------------------------------------

  let page = pdfDoc.addPage(PageSizes.Letter);
  let y = pageHeight - 150;

  // Title
  page.drawText("Memory Book", {
    x: margin,
    y,
    size: 36,
    font: helveticaBold,
    color: textColor,
  });
  y -= 40;

  // Subtitle with patient name
  const subtitle = patient
    ? `A collection of moments with ${patient.first_name}`
    : "A collection of moments in your caregiving journey";

  page.drawText(subtitle, {
    x: margin,
    y,
    size: 14,
    font: helveticaOblique,
    color: secondaryColor,
  });
  y -= 60;

  // Date range
  page.drawText(
    `${formatDateShort(dateRange.start)} – ${formatDateShort(dateRange.end)}`,
    {
      x: margin,
      y,
      size: 12,
      font: helvetica,
      color: secondaryColor,
    },
  );
  y -= 30;

  // Entry count
  const goodMoments = entries.filter(
    (e) => e.entry_type === "GOOD_MOMENT",
  ).length;
  const milestones = entries.filter((e) => e.entry_type === "MILESTONE").length;

  page.drawText(`${entries.length} entries`, {
    x: margin,
    y,
    size: 12,
    font: helvetica,
    color: secondaryColor,
  });
  y -= 20;

  page.drawText(`${goodMoments} good moments · ${milestones} milestones`, {
    x: margin,
    y,
    size: 10,
    font: helvetica,
    color: secondaryColor,
  });

  // Footer
  page.drawText("Created with CuraKnot", {
    x: margin,
    y: 50,
    size: 10,
    font: helvetica,
    color: secondaryColor,
  });

  // -------------------------------------------------------------------------
  // Entry Pages
  // -------------------------------------------------------------------------

  // Group entries by month
  const entriesByMonth: { [key: string]: JournalEntry[] } = {};
  for (const entry of entries) {
    const date = new Date(entry.entry_date);
    const monthKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
    if (!entriesByMonth[monthKey]) {
      entriesByMonth[monthKey] = [];
    }
    entriesByMonth[monthKey].push(entry);
  }

  // Sort months in chronological order
  const sortedMonths = Object.keys(entriesByMonth).sort();

  for (const monthKey of sortedMonths) {
    const monthEntries = entriesByMonth[monthKey];
    const monthDate = new Date(monthKey + "-01");
    const monthName = monthDate.toLocaleDateString("en-US", {
      month: "long",
      year: "numeric",
    });

    // Add month header page
    page = pdfDoc.addPage(PageSizes.Letter);
    y = pageHeight - 100;

    page.drawText(monthName, {
      x: margin,
      y,
      size: 28,
      font: helveticaBold,
      color: purpleColor,
    });
    y -= 50;

    // Entries for this month
    for (const entry of monthEntries) {
      // Check if we need a new page
      if (y < 150) {
        page = pdfDoc.addPage(PageSizes.Letter);
        y = pageHeight - margin;
      }

      // Date header
      page.drawText(formatDate(entry.entry_date), {
        x: margin,
        y,
        size: 10,
        font: helvetica,
        color: secondaryColor,
      });
      y -= 20;

      // Entry type badge
      const badgeText =
        entry.entry_type === "MILESTONE" ? "🎉 Milestone" : "✨ Good Moment";
      page.drawText(badgeText, {
        x: margin,
        y,
        size: 10,
        font: helvetica,
        color: purpleColor,
      });
      y -= 24;

      // Title (for milestones)
      if (entry.title) {
        page.drawText(entry.title, {
          x: margin,
          y,
          size: 16,
          font: helveticaBold,
          color: textColor,
        });
        y -= 24;
      }

      // Milestone type
      if (entry.milestone_type) {
        const typeLabel =
          entry.milestone_type.charAt(0) +
          entry.milestone_type.slice(1).toLowerCase();
        page.drawText(`Type: ${typeLabel}`, {
          x: margin,
          y,
          size: 10,
          font: helvetica,
          color: secondaryColor,
        });
        y -= 20;
      }

      // Content
      const contentLines = wrapText(entry.content, 80);
      for (const line of contentLines) {
        if (y < margin) {
          page = pdfDoc.addPage(PageSizes.Letter);
          y = pageHeight - margin;
        }

        page.drawText(line, {
          x: margin,
          y,
          size: 11,
          font: helvetica,
          color: textColor,
        });
        y -= lineHeight;
      }

      // Photo indicator
      if (entry.photo_storage_keys && entry.photo_storage_keys.length > 0) {
        y -= 8;
        page.drawText(
          `📷 ${entry.photo_storage_keys.length} photo${entry.photo_storage_keys.length > 1 ? "s" : ""}`,
          {
            x: margin,
            y,
            size: 10,
            font: helvetica,
            color: secondaryColor,
          },
        );
        y -= lineHeight;
      }

      // Spacing between entries
      y -= paragraphSpacing;
    }
  }

  // Save and return
  return await pdfDoc.save();
}

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get auth token from header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          code: "AUTH_MISSING",
          message: "Missing Authorization header",
        } as ErrorResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create Supabase clients
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Client with user context for auth check
    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Service client for data access (bypasses RLS for admin operations)
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Get current user
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();

    if (userError || !user) {
      return new Response(
        JSON.stringify({
          code: "AUTH_INVALID",
          message: "Invalid or expired token",
        } as ErrorResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check Family tier access
    const { data: hasAccess, error: accessError } = await supabaseService.rpc(
      "has_feature_access",
      {
        p_user_id: user.id,
        p_feature: "memory_book_export",
      },
    );

    if (accessError || !hasAccess) {
      return new Response(
        JSON.stringify({
          code: "FEATURE_NOT_AVAILABLE",
          message: "Memory Book export requires a Family subscription",
        } as ErrorResponse),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request
    const body: MemoryBookRequest = await req.json();
    const { circleId, startDate, endDate, includePrivate } = body;

    // Validate request
    if (!circleId || !startDate || !endDate) {
      return new Response(
        JSON.stringify({
          code: "INVALID_REQUEST",
          message: "Missing required fields: circleId, startDate, endDate",
        } as ErrorResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate UUID format for circleId
    const UUID_REGEX =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!UUID_REGEX.test(circleId)) {
      return new Response(
        JSON.stringify({
          code: "INVALID_REQUEST",
          message: "Invalid circleId format",
        } as ErrorResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate date format (YYYY-MM-DD)
    const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
    if (
      !DATE_REGEX.test(startDate) ||
      !DATE_REGEX.test(endDate) ||
      isNaN(new Date(startDate).getTime()) ||
      isNaN(new Date(endDate).getTime())
    ) {
      return new Response(
        JSON.stringify({
          code: "INVALID_REQUEST",
          message: "Invalid date format. Use YYYY-MM-DD.",
        } as ErrorResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify user is member of circle
    const { data: membership, error: memberError } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", circleId)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (memberError || !membership) {
      return new Response(
        JSON.stringify({
          code: "NOT_MEMBER",
          message: "You are not a member of this circle",
        } as ErrorResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch entries (respecting visibility)
    let query = supabaseService
      .from("journal_entries")
      .select("*")
      .eq("circle_id", circleId)
      .gte("entry_date", startDate)
      .lte("entry_date", endDate)
      .order("entry_date", { ascending: true })
      .limit(500);

    // Apply visibility filter
    if (includePrivate) {
      // Include CIRCLE entries + user's own PRIVATE entries
      query = query.or(
        `visibility.eq.CIRCLE,and(visibility.eq.PRIVATE,created_by.eq.${user.id})`,
      );
    } else {
      // Only CIRCLE entries
      query = query.eq("visibility", "CIRCLE");
    }

    const { data: entries, error: fetchError } = await query;

    if (fetchError) {
      console.error("Fetch error:", fetchError.code || "unknown");
      return new Response(
        JSON.stringify({
          code: "FETCH_ERROR",
          message: "Failed to fetch journal entries",
        } as ErrorResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!entries || entries.length === 0) {
      return new Response(
        JSON.stringify({
          code: "NO_ENTRIES",
          message: "No entries found in the specified date range",
        } as ErrorResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get patient info (for title page)
    const patientIds = [...new Set(entries.map((e) => e.patient_id))];
    let patient: PatientInfo | null = null;

    if (patientIds.length === 1) {
      const { data: patientData } = await supabaseService
        .from("patients")
        .select("id, first_name, last_name")
        .eq("id", patientIds[0])
        .single();

      patient = patientData;
    }

    // Generate PDF
    const pdfBytes = await generatePDF(entries as JournalEntry[], patient, {
      start: startDate,
      end: endDate,
    });

    // Upload to Supabase Storage
    const timestamp = Date.now();
    const filename = `memory-book-${timestamp}.pdf`;
    const storagePath = `exports/${circleId}/${filename}`;

    const { error: uploadError } = await supabaseService.storage
      .from("care-exports")
      .upload(storagePath, pdfBytes, {
        contentType: "application/pdf",
        upsert: false,
      });

    if (uploadError) {
      console.error(
        "Upload error:",
        uploadError.message ? "storage_error" : "unknown",
      );
      return new Response(
        JSON.stringify({
          code: "UPLOAD_ERROR",
          message: "Failed to save generated PDF",
        } as ErrorResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate signed URL (24 hour expiry)
    const { data: signedUrlData, error: signedUrlError } =
      await supabaseService.storage
        .from("care-exports")
        .createSignedUrl(storagePath, 86400); // 24 hours

    if (signedUrlError || !signedUrlData) {
      console.error("Signed URL error: failed to generate");
      return new Response(
        JSON.stringify({
          code: "URL_ERROR",
          message: "Failed to generate download URL",
        } as ErrorResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate photo count
    const photoCount = entries.reduce(
      (sum, e) => sum + (e.photo_storage_keys?.length || 0),
      0,
    );

    // Return success response
    const response: MemoryBookResponse = {
      url: signedUrlData.signedUrl,
      expiresAt: new Date(Date.now() + 86400 * 1000).toISOString(),
      entryCount: entries.length,
      photoCount,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(
      "Unexpected error:",
      error instanceof Error ? error.name : "unknown",
    );
    return new Response(
      JSON.stringify({
        code: "INTERNAL_ERROR",
        message: "An unexpected error occurred",
      } as ErrorResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
