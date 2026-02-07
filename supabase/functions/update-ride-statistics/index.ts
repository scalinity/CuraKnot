import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "https://curaknot.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Verify cron secret to prevent unauthorized invocation
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (!cronSecret) {
    console.error("CRON_SECRET environment variable is not set");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
  const authHeader = req.headers.get("Authorization");
  if (authHeader !== `Bearer ${cronSecret}`) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      console.error("Missing required environment variables");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const monthStartStr = monthStart.toISOString().split("T")[0];

    // Get all rides for current month with assigned drivers.
    // SCHEDULED rides are included intentionally: they count toward rides_scheduled
    // (planned activity) but NOT rides_given (only COMPLETED increments rides_given).
    const { data: rides, error: ridesError } = await supabase
      .from("scheduled_rides")
      .select("circle_id, driver_user_id, status, confirmation_status")
      .gte("pickup_time", monthStart.toISOString())
      .in("status", ["COMPLETED", "CANCELLED", "MISSED", "SCHEDULED"])
      .not("driver_user_id", "is", null);

    if (ridesError) {
      console.error("Error fetching rides for statistics update");
      return new Response(JSON.stringify({ error: "Failed to fetch rides" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!rides || rides.length === 0) {
      return new Response(
        JSON.stringify({
          circles_processed: 0,
          stats_updated: 0,
          message: "No rides to process",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Aggregate by circle_id + driver_user_id
    const statsMap = new Map<
      string,
      {
        circle_id: string;
        user_id: string;
        rides_given: number;
        rides_scheduled: number;
        rides_cancelled: number;
      }
    >();

    for (const ride of rides) {
      if (!ride.driver_user_id || !ride.circle_id) continue;

      const key = `${ride.circle_id}:${ride.driver_user_id}`;
      let stat = statsMap.get(key);

      if (!stat) {
        stat = {
          circle_id: ride.circle_id,
          user_id: ride.driver_user_id,
          rides_given: 0,
          rides_scheduled: 0,
          rides_cancelled: 0,
        };
        statsMap.set(key, stat);
      }

      // Count by status
      switch (ride.status) {
        case "COMPLETED":
          stat.rides_given++;
          stat.rides_scheduled++;
          break;
        case "SCHEDULED":
          stat.rides_scheduled++;
          break;
        case "CANCELLED":
          stat.rides_cancelled++;
          stat.rides_scheduled++;
          break;
        case "MISSED":
          // Missed rides count as scheduled but not given
          stat.rides_scheduled++;
          break;
        default:
          // Unknown status — skip to avoid corrupting statistics
          console.warn(`Unknown ride status: ${ride.status}`);
          break;
      }
    }

    // Upsert statistics
    let statsUpdated = 0;
    let upsertErrors = 0;
    const circlesProcessed = new Set<string>();

    // Batch upsert all statistics in a single call instead of N+1
    const upsertPayload = [];
    for (const stat of statsMap.values()) {
      circlesProcessed.add(stat.circle_id);
      upsertPayload.push({
        circle_id: stat.circle_id,
        user_id: stat.user_id,
        month: monthStartStr,
        rides_given: stat.rides_given,
        rides_scheduled: stat.rides_scheduled,
        rides_cancelled: stat.rides_cancelled,
      });
    }

    if (upsertPayload.length > 0) {
      const { error: upsertError } = await supabase
        .from("ride_statistics")
        .upsert(upsertPayload, {
          onConflict: "circle_id,user_id,month",
        });

      if (upsertError) {
        console.error("Error batch upserting ride statistics");
        upsertErrors = upsertPayload.length;
      } else {
        statsUpdated = upsertPayload.length;
      }
    }

    // Log to audit_events
    await supabase.from("audit_events").insert({
      event_type: "RIDE_STATISTICS_UPDATED",
      metadata_json: {
        circles_processed: circlesProcessed.size,
        stats_updated: statsUpdated,
        upsert_errors: upsertErrors,
        rides_analyzed: rides.length,
        month: monthStartStr,
        timestamp: now.toISOString(),
      },
    });

    return new Response(
      JSON.stringify({
        circles_processed: circlesProcessed.size,
        stats_updated: statsUpdated,
        rides_analyzed: rides.length,
        month: monthStartStr,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Update ride statistics error");
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
