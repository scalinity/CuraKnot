import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "https://curaknot.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Time window constants (in hours)
const REMINDER_WINDOW_HOURS = 25;
const REMINDER_24H_MIN = 23;
const REMINDER_24H_MAX = 25;
const REMINDER_1H_MIN = 0.5;
const REMINDER_1H_MAX = 1.5;
const IDEMPOTENCY_LOOKBACK_HOURS = 26;

interface ScheduledRide {
  id: string;
  circle_id: string;
  patient_id: string;
  created_by: string;
  pickup_time: string;
  driver_user_id: string | null;
  confirmation_status: string;
  status: string;
  needs_return: boolean;
  return_time: string | null;
}

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
    let remindersSent = 0;
    let alertsSent = 0;

    // 1. Find rides needing reminders (next REMINDER_WINDOW_HOURS to catch 24h and 1h windows)
    const windowEnd = new Date(
      now.getTime() + REMINDER_WINDOW_HOURS * 60 * 60 * 1000,
    );

    const { data: upcomingRides, error: ridesError } = await supabase
      .from("scheduled_rides")
      .select(
        "id, circle_id, patient_id, created_by, pickup_time, driver_user_id, confirmation_status, status, needs_return, return_time",
      )
      .eq("status", "SCHEDULED")
      .gte("pickup_time", now.toISOString())
      .lte("pickup_time", windowEnd.toISOString())
      .order("pickup_time", { ascending: true });

    if (ridesError) {
      console.error("Error fetching rides for reminders");
      return new Response(JSON.stringify({ error: "Failed to fetch rides" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!upcomingRides || upcomingRides.length === 0) {
      return new Response(
        JSON.stringify({
          reminders_sent: 0,
          alerts_sent: 0,
          message: "No upcoming rides",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Check which rides already had reminders sent (idempotency)
    const rideIds = upcomingRides.map((r: ScheduledRide) => r.id);
    const { data: existingReminders } = await supabase
      .from("audit_events")
      .select("metadata_json")
      .eq("event_type", "RIDE_REMINDER_SENT")
      .gte(
        "created_at",
        new Date(
          now.getTime() - IDEMPOTENCY_LOOKBACK_HOURS * 60 * 60 * 1000,
        ).toISOString(),
      );

    const alreadySentSet = new Set<string>();
    if (existingReminders) {
      for (const event of existingReminders) {
        const key = event.metadata_json?.reminder_key;
        if (key) alreadySentSet.add(key);
      }
    }

    // Pre-fetch circle members for all relevant circles (batch instead of N+1)
    const circleIds = [
      ...new Set(upcomingRides.map((r: ScheduledRide) => r.circle_id)),
    ];
    const circleMembersMap = new Map<string, string[]>();

    if (circleIds.length > 0) {
      const { data: allMembers } = await supabase
        .from("circle_members")
        .select("circle_id, user_id")
        .in("circle_id", circleIds)
        .eq("status", "ACTIVE")
        .in("role", ["CONTRIBUTOR", "ADMIN", "OWNER"]);

      if (allMembers) {
        for (const m of allMembers) {
          const existing = circleMembersMap.get(m.circle_id) || [];
          existing.push(m.user_id);
          circleMembersMap.set(m.circle_id, existing);
        }
      }
    }

    // Pre-fetch push tokens for all users who may receive notifications
    const allUserIds = new Set<string>();
    for (const ride of upcomingRides as ScheduledRide[]) {
      if (ride.driver_user_id) allUserIds.add(ride.driver_user_id);
      allUserIds.add(ride.created_by);
      const memberIds = circleMembersMap.get(ride.circle_id) || [];
      for (const mid of memberIds) allUserIds.add(mid);
    }

    const pushTokenMap = new Map<string, string>();
    if (allUserIds.size > 0) {
      const { data: tokenRows } = await supabase
        .from("users")
        .select("id, push_token")
        .in("id", [...allUserIds])
        .not("push_token", "is", null);

      if (tokenRows) {
        for (const row of tokenRows) {
          if (row.push_token) pushTokenMap.set(row.id, row.push_token);
        }
      }
    }

    for (const ride of upcomingRides as ScheduledRide[]) {
      try {
        const pickupTime = new Date(ride.pickup_time);
        const hoursUntilPickup =
          (pickupTime.getTime() - now.getTime()) / (1000 * 60 * 60);

        // 24-hour window
        if (
          hoursUntilPickup >= REMINDER_24H_MIN &&
          hoursUntilPickup <= REMINDER_24H_MAX
        ) {
          if (ride.confirmation_status === "CONFIRMED" && ride.driver_user_id) {
            const reminderKey = `driver_24h_${ride.id}`;
            if (!alreadySentSet.has(reminderKey)) {
              // Send driver 24h reminder
              await sendNotification(
                supabase,
                ride.driver_user_id,
                {
                  title: "Ride Tomorrow",
                  body: `Pickup at ${formatTime(pickupTime)}`,
                  type: "RIDE_REMINDER_DRIVER",
                  ride_id: ride.id,
                },
                pushTokenMap,
              );
              await logReminderSent(supabase, reminderKey);
              remindersSent++;
            }
          }

          // Send patient/creator 24h reminder
          const patientKey = `patient_24h_${ride.id}`;
          if (!alreadySentSet.has(patientKey)) {
            await sendNotification(
              supabase,
              ride.created_by,
              {
                title: "Ride Tomorrow",
                body: `Pickup at ${formatTime(pickupTime)}`,
                type: "RIDE_REMINDER_PATIENT",
                ride_id: ride.id,
              },
              pushTokenMap,
            );
            await logReminderSent(supabase, patientKey);
            remindersSent++;
          }

          // Unconfirmed ride alert
          if (ride.confirmation_status === "UNCONFIRMED") {
            const alertKey = `unconfirmed_24h_${ride.id}`;
            if (!alreadySentSet.has(alertKey)) {
              const memberIds = circleMembersMap.get(ride.circle_id) || [];
              for (const memberId of memberIds) {
                await sendNotification(
                  supabase,
                  memberId,
                  {
                    title: "Driver Needed",
                    body: `A ride tomorrow at ${formatTime(pickupTime)} needs a driver`,
                    type: "RIDE_UNCONFIRMED_ALERT",
                    ride_id: ride.id,
                  },
                  pushTokenMap,
                );
                alertsSent++;
              }
              await logReminderSent(supabase, alertKey);
            }
          }
        }

        // 1-hour window
        if (
          hoursUntilPickup >= REMINDER_1H_MIN &&
          hoursUntilPickup <= REMINDER_1H_MAX
        ) {
          if (ride.confirmation_status === "CONFIRMED" && ride.driver_user_id) {
            const reminderKey = `driver_1h_${ride.id}`;
            if (!alreadySentSet.has(reminderKey)) {
              // Send driver 1h reminder
              await sendNotification(
                supabase,
                ride.driver_user_id,
                {
                  title: "Leaving Soon",
                  body: `Pickup at ${formatTime(pickupTime)}`,
                  type: "RIDE_REMINDER_DRIVER_SOON",
                  ride_id: ride.id,
                },
                pushTokenMap,
              );
              await logReminderSent(supabase, reminderKey);
              remindersSent++;
            }
          }
        }
      } catch (rideError) {
        // Per-ride error handling: log and continue processing remaining rides
        console.error("Error processing reminders for individual ride");
        await supabase.from("audit_events").insert({
          event_type: "RIDE_REMINDER_ERROR",
          metadata_json: {
            ride_id: ride.id,
            timestamp: now.toISOString(),
          },
        });
      }
    }

    // Log batch summary to audit_events
    await supabase.from("audit_events").insert({
      event_type: "RIDE_REMINDERS_BATCH",
      metadata_json: {
        reminders_sent: remindersSent,
        alerts_sent: alertsSent,
        rides_processed: upcomingRides.length,
        timestamp: now.toISOString(),
      },
    });

    return new Response(
      JSON.stringify({
        reminders_sent: remindersSent,
        alerts_sent: alertsSent,
        rides_processed: upcomingRides.length,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Ride reminders error");
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Helper: Log a reminder key to prevent duplicate sends
async function logReminderSent(
  supabase: ReturnType<typeof createClient>,
  reminderKey: string,
) {
  await supabase.from("audit_events").insert({
    event_type: "RIDE_REMINDER_SENT",
    metadata_json: { reminder_key: reminderKey },
  });
}

// Helper: Send push notification via existing notification infrastructure
async function sendNotification(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  payload: {
    title: string;
    body: string;
    type: string;
    ride_id: string;
  },
  pushTokenMap: Map<string, string>,
) {
  let delivered = false;
  try {
    const pushToken = pushTokenMap.get(userId);
    if (!pushToken) {
      // No push token — log and skip
      await supabase.from("audit_events").insert({
        event_type: "RIDE_NOTIFICATION_SKIPPED",
        metadata_json: {
          user_id: userId,
          ride_id: payload.ride_id,
          notification_type: payload.type,
          reason: "no_push_token",
        },
      });
      return;
    }

    // TODO: Integrate with actual APNS sending when NotificationManager edge function exists
    // For now, log the intent but do not claim delivery
    console.log(`Notification queued for user (type: ${payload.type})`);
  } catch (error) {
    // Notification delivery failure — non-fatal, continue processing
    console.warn(
      `Non-fatal: notification delivery failed for type ${payload.type}`,
    );
  }

  // Log queued notification for audit trail (not yet delivered)
  await supabase.from("audit_events").insert({
    event_type: "RIDE_NOTIFICATION_QUEUED",
    metadata_json: {
      user_id: userId,
      ride_id: payload.ride_id,
      notification_type: payload.type,
      delivered,
    },
  });
}

// Helper: Format time for display
function formatTime(date: Date): string {
  return date.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}
