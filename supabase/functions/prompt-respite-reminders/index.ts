import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SubscriptionRow {
  user_id: string;
}

interface MembershipRow {
  user_id: string;
  circle_id: string;
}

interface RespiteLogRow {
  circle_id: string;
}

// Weekly cron function to remind FAMILY tier caregivers to take respite breaks
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Authenticate: require service role key or Authorization header matching service key
    const authHeader = req.headers.get("Authorization");
    const cronSecret = Deno.env.get("CRON_SECRET");
    const providedToken = authHeader?.replace("Bearer ", "");

    // Accept either service role key or cron secret
    if (
      providedToken !== supabaseServiceKey &&
      (!cronSecret || providedToken !== cronSecret)
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "UNAUTHORIZED", message: "Invalid authorization" },
        }),
        {
          status: 401,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Find FAMILY tier users who haven't had respite in 4+ weeks
    const fourWeeksAgo = new Date();
    fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28);
    const cutoffDate = fourWeeksAgo.toISOString().split("T")[0];
    const todayDate = new Date().toISOString().split("T")[0];

    // Get all FAMILY tier active subscriptions
    const { data: familyUsers, error: subError } = await supabaseService
      .from("subscriptions")
      .select("user_id")
      .eq("plan", "FAMILY")
      .eq("status", "ACTIVE");

    if (subError || !familyUsers || familyUsers.length === 0) {
      return new Response(JSON.stringify({ success: true, remindersSent: 0 }), {
        status: 200,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const familyUserIds = familyUsers.map((u: SubscriptionRow) => u.user_id);

    // Batch fetch: get all active circle memberships for family users
    const { data: allMemberships } = await supabaseService
      .from("circle_members")
      .select("user_id, circle_id")
      .in("user_id", familyUserIds)
      .eq("status", "ACTIVE");

    if (!allMemberships || allMemberships.length === 0) {
      return new Response(JSON.stringify({ success: true, remindersSent: 0 }), {
        status: 200,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // Group circle IDs by user
    const userCirclesMap = new Map<string, string[]>();
    const allCircleIds = new Set<string>();
    for (const m of allMemberships as MembershipRow[]) {
      const circles = userCirclesMap.get(m.user_id) ?? [];
      circles.push(m.circle_id);
      userCirclesMap.set(m.user_id, circles);
      allCircleIds.add(m.circle_id);
    }

    // Batch fetch: get all circles with recent respite activity
    // Use overlapping date range: any respite that overlaps the 4-week window
    // A respite overlaps if: start_date <= today AND end_date >= cutoffDate
    const { data: recentRespiteCircles } = await supabaseService
      .from("respite_log")
      .select("circle_id")
      .in("circle_id", Array.from(allCircleIds))
      .lte("start_date", todayDate)
      .gte("end_date", cutoffDate);

    const circlesWithRecentRespite = new Set(
      (recentRespiteCircles ?? []).map((r: RespiteLogRow) => r.circle_id),
    );

    // Determine which users need reminders
    const notifications: Array<{
      user_id: string;
      circle_id: string;
      notification_type: string;
      title: string;
      body: string;
      data_json: Record<string, string>;
    }> = [];

    for (const [userId, circleIds] of userCirclesMap) {
      // Find circles where no respite has been taken recently
      const circlesNeedingReminder = circleIds.filter(
        (cid) => !circlesWithRecentRespite.has(cid),
      );

      if (circlesNeedingReminder.length > 0) {
        // One reminder per user (reference first circle without recent respite)
        notifications.push({
          user_id: userId,
          circle_id: circlesNeedingReminder[0],
          notification_type: "RESPITE_REMINDER",
          title: "Time for a Break",
          body: "You haven't taken respite in over 4 weeks. Taking regular breaks helps you stay strong for your loved one.",
          data_json: { type: "respite_reminder" },
        });
      }
    }

    // Batch insert all notifications at once
    let actualSent = 0;
    if (notifications.length > 0) {
      const { error: insertError } = await supabaseService
        .from("notification_outbox")
        .insert(notifications);

      if (insertError) {
        console.error(
          "Batch notification insert failed:",
          insertError.code ?? "UNKNOWN",
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "INSERT_FAILED",
              message: "Failed to queue notifications",
            },
          }),
          {
            status: 500,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          },
        );
      }
      actualSent = notifications.length;
    }

    return new Response(
      JSON.stringify({ success: true, remindersSent: actualSent }),
      {
        status: 200,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Unexpected error in prompt-respite-reminders");
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "INTERNAL_ERROR", message: "Failed to send reminders" },
      }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});
