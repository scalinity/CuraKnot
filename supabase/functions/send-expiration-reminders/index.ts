import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Reminder thresholds in days
const REMINDER_THRESHOLDS = [90, 60, 30, 7];

interface ReminderResult {
  success: boolean;
  reminders_sent: number;
  documents_expiring: {
    document_id: string;
    title: string;
    days_until_expiration: number;
  }[];
  error?: { code: string; message: string };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Verify this is called by cron or authorized service (service role only)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_REQUIRED", message: "Authorization required" },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    // Use constant-time comparison to prevent timing attacks on service role key
    const expected = new TextEncoder().encode(supabaseServiceKey);
    const provided = new TextEncoder().encode(token);
    if (
      expected.length !== provided.length ||
      !crypto.subtle.timingSafeEqual(expected, provided)
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_FORBIDDEN",
            message: "This endpoint requires service role authorization",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const now = new Date();
    const remindersSent: ReminderResult["documents_expiring"] = [];
    let totalSent = 0;

    // For each reminder threshold, find matching documents
    for (const days of REMINDER_THRESHOLDS) {
      const targetDate = new Date(now);
      targetDate.setDate(targetDate.getDate() + days);

      // Find documents expiring on exactly the target date (date column, no time component)
      const targetDateStr = targetDate.toISOString().split("T")[0];

      const { data: expiringDocs, error: queryError } = await supabaseService
        .from("legal_documents")
        .select(
          `
          id, title, document_type, expiration_date, circle_id, created_by,
          patient_id
        `,
        )
        .eq("status", "ACTIVE")
        .eq("expiration_date", targetDateStr);

      if (queryError || !expiringDocs || expiringDocs.length === 0) {
        continue;
      }

      for (const doc of expiringDocs) {
        // Check if the circle owner has FAMILY plan (expiration reminders are Family-only)
        const { data: circleOwner } = await supabaseService
          .from("circle_members")
          .select("user_id")
          .eq("circle_id", doc.circle_id)
          .eq("role", "OWNER")
          .eq("status", "ACTIVE")
          .single();

        if (!circleOwner) continue;

        const { data: subscription } = await supabaseService
          .from("subscriptions")
          .select("plan")
          .eq("user_id", circleOwner.user_id)
          .eq("status", "ACTIVE")
          .single();

        if (!subscription || subscription.plan !== "FAMILY") continue;

        // Check if reminder was already sent for this threshold
        const { data: existingAudit } = await supabaseService
          .from("legal_document_audit")
          .select("id")
          .eq("document_id", doc.id)
          .eq("action", "EXPIRATION_REMINDER")
          .filter("details_json->>reminder_days", "eq", String(days))
          .limit(1);

        if (existingAudit && existingAudit.length > 0) {
          continue; // Already sent this reminder
        }

        // Get all users with access to this document
        const { data: accessUsers } = await supabaseService
          .from("legal_document_access")
          .select("user_id")
          .eq("document_id", doc.id)
          .eq("can_view", true);

        const notifyUserIds = new Set<string>();
        notifyUserIds.add(doc.created_by); // Always notify creator
        accessUsers?.forEach((a) => notifyUserIds.add(a.user_id));

        // Get patient name for notification
        const { data: patient } = await supabaseService
          .from("patients")
          .select("display_name")
          .eq("id", doc.patient_id)
          .single();

        // Send push notification to each user
        for (const userId of notifyUserIds) {
          const { data: userProfile } = await supabaseService
            .from("users")
            .select("push_token, display_name")
            .eq("id", userId)
            .single();

          if (userProfile?.push_token) {
            // In production, send via APNs
            // For now, log the notification intent
            console.log(
              `[REMINDER] User ${userId}: "${doc.title}" for ${patient?.display_name ?? "patient"} expires in ${days} days`,
            );
            totalSent++;
          }
        }

        // Log the reminder in audit
        const { error: reminderAuditError } = await supabaseService
          .from("legal_document_audit")
          .insert({
            document_id: doc.id,
            user_id: null,
            action: "EXPIRATION_REMINDER",
            details_json: {
              reminder_days: days,
              notified_users: Array.from(notifyUserIds),
              patient_name: patient?.display_name,
            },
          });
        if (reminderAuditError) {
          console.error(
            `Audit log failed for reminder on doc ${doc.id}:`,
            reminderAuditError.message,
          );
        }

        remindersSent.push({
          document_id: doc.id,
          title: doc.title,
          days_until_expiration: days,
        });
      }
    }

    // Also auto-expire documents past their expiration date
    const { data: expiredDocs } = await supabaseService
      .from("legal_documents")
      .select("id")
      .eq("status", "ACTIVE")
      .lt("expiration_date", now.toISOString().split("T")[0]);

    if (expiredDocs && expiredDocs.length > 0) {
      for (const doc of expiredDocs) {
        await supabaseService
          .from("legal_documents")
          .update({ status: "EXPIRED" })
          .eq("id", doc.id);

        const { error: expireAuditError } = await supabaseService
          .from("legal_document_audit")
          .insert({
            document_id: doc.id,
            user_id: null,
            action: "AUTO_EXPIRED",
            details_json: { reason: "Past expiration date" },
          });
        if (expireAuditError) {
          console.error(
            `Audit log failed for auto-expire on doc ${doc.id}:`,
            expireAuditError.message,
          );
        }
      }
    }

    const result: ReminderResult = {
      success: true,
      reminders_sent: totalSent,
      documents_expiring: remindersSent,
    };

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        reminders_sent: 0,
        documents_expiring: [],
        error: {
          code: "INTERNAL_ERROR",
          message: "An unexpected error occurred",
        },
      } satisfies ReminderResult),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
