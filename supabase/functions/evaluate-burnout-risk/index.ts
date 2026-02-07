import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  WellnessSignals,
  assessBurnoutRisk,
  generateAlertMessage,
  analyzeSentiment,
} from "../_shared/wellness-scoring.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

interface EvaluateBurnoutResponse {
  success: boolean;
  usersEvaluated: number;
  alertsCreated: number;
  timestamp: string;
}

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceKey) {
    console.error("Missing Supabase environment variables");
    return errorResponse("CONFIG_ERROR", "Server configuration error", 500);
  }

  try {
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    const sevenDaysAgo = new Date(
      Date.now() - 7 * 24 * 60 * 60 * 1000,
    ).toISOString();
    const fourteenDaysAgo = new Date(
      Date.now() - 14 * 24 * 60 * 60 * 1000,
    ).toISOString();

    // Fetch all users with recent check-ins (last 7 days)
    // who have wellness_checkins feature access
    const { data: recentCheckIns, error: checkInsError } = await supabaseService
      .from("wellness_checkins")
      .select(
        "user_id, stress_level, sleep_quality, capacity_level, week_start",
      )
      .gte("created_at", sevenDaysAgo)
      .order("created_at", { ascending: false });

    if (checkInsError) {
      console.error(
        "Error fetching check-ins:",
        checkInsError.code || "unknown",
      );
      return errorResponse("DATABASE_ERROR", "Failed to fetch check-ins", 500);
    }

    // Group by user (take most recent check-in per user)
    const userCheckIns = new Map<
      string,
      { stress_level: number; sleep_quality: number; capacity_level: number }
    >();
    for (const checkIn of recentCheckIns || []) {
      if (!userCheckIns.has(checkIn.user_id)) {
        userCheckIns.set(checkIn.user_id, {
          stress_level: checkIn.stress_level,
          sleep_quality: checkIn.sleep_quality,
          capacity_level: checkIn.capacity_level,
        });
      }
    }

    let usersEvaluated = 0;
    let alertsCreated = 0;

    // Evaluate each user
    for (const [userId, checkIn] of userCheckIns) {
      try {
        // Check if user has wellness_checkins feature
        const { data: hasFeature } = await supabaseService.rpc(
          "has_feature_access",
          {
            p_user_id: userId,
            p_feature: "wellness_checkins",
          },
        );

        if (!hasFeature) {
          continue; // Skip users without feature access
        }

        const now = new Date();
        const last7Days = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        const prior7Days = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000);

        // Gather behavioral signals
        const { count: handoffCountLast7 } = await supabaseService
          .from("handoffs")
          .select("*", { count: "exact", head: true })
          .eq("created_by", userId)
          .gte("created_at", last7Days.toISOString());

        const { count: handoffCountPrior7 } = await supabaseService
          .from("handoffs")
          .select("*", { count: "exact", head: true })
          .eq("created_by", userId)
          .gte("created_at", prior7Days.toISOString())
          .lt("created_at", last7Days.toISOString());

        const { data: recentHandoffs } = await supabaseService
          .from("handoffs")
          .select("created_at, raw_transcript")
          .eq("created_by", userId)
          .gte("created_at", last7Days.toISOString());

        const lateNightEntries =
          recentHandoffs?.filter((h) => {
            const hour = new Date(h.created_at).getUTCHours();
            return hour >= 22 || hour <= 5;
          }).length || 0;

        // Sentiment analysis
        let totalSentiment = 0;
        let sentimentCount = 0;
        if (recentHandoffs) {
          for (const handoff of recentHandoffs) {
            if (handoff.raw_transcript) {
              totalSentiment += analyzeSentiment(handoff.raw_transcript);
              sentimentCount++;
            }
          }
        }
        const averageSentiment =
          sentimentCount > 0 ? totalSentiment / sentimentCount : 0;

        // Task completion rate
        const { count: totalTasks } = await supabaseService
          .from("tasks")
          .select("*", { count: "exact", head: true })
          .eq("assigned_to", userId)
          .gte("created_at", last7Days.toISOString());

        const { count: completedTasks } = await supabaseService
          .from("tasks")
          .select("*", { count: "exact", head: true })
          .eq("assigned_to", userId)
          .eq("status", "COMPLETED")
          .gte("created_at", last7Days.toISOString());

        const taskCompletionRate =
          totalTasks && totalTasks > 0 ? (completedTasks || 0) / totalTasks : 1;

        // Days without break
        const { data: last30DaysHandoffs } = await supabaseService
          .from("handoffs")
          .select("created_at")
          .eq("created_by", userId)
          .gte(
            "created_at",
            new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString(),
          );

        let daysWithoutBreak = 0;
        if (last30DaysHandoffs && last30DaysHandoffs.length > 0) {
          const handoffDates = new Set(
            last30DaysHandoffs.map(
              (h) => new Date(h.created_at).toISOString().split("T")[0],
            ),
          );

          for (let i = 0; i < 30; i++) {
            const date = new Date(now.getTime() - i * 24 * 60 * 60 * 1000)
              .toISOString()
              .split("T")[0];
            if (handoffDates.has(date)) {
              daysWithoutBreak++;
            } else {
              break;
            }
          }
        }

        // Build signals
        const signals: WellnessSignals = {
          stressLevel: checkIn.stress_level,
          sleepQuality: checkIn.sleep_quality,
          capacityLevel: checkIn.capacity_level,
          handoffCountLast7Days: handoffCountLast7 || 0,
          handoffCountPrior7Days: handoffCountPrior7 || 0,
          lateNightEntries,
          averageSentiment,
          taskCompletionRate,
          daysWithoutBreak,
        };

        const riskLevel = assessBurnoutRisk(signals);
        usersEvaluated++;

        // Create alert if MODERATE or HIGH risk
        if (riskLevel === "MODERATE" || riskLevel === "HIGH") {
          // Check for existing active alert in last 7 days (avoid duplicates)
          const { data: existingAlerts } = await supabaseService
            .from("wellness_alerts")
            .select("id")
            .eq("user_id", userId)
            .eq("alert_type", "BURNOUT_RISK")
            .eq("status", "ACTIVE")
            .gte("created_at", sevenDaysAgo)
            .limit(1);

          if (!existingAlerts || existingAlerts.length === 0) {
            // Fetch delegation candidates from CIRCLE MEMBERSHIP (NOT wellness data)
            // PRIVACY: We query circle_members, not wellness scores
            const { data: circles } = await supabaseService
              .from("circle_members")
              .select("circle_id, circles(name)")
              .eq("user_id", userId)
              .eq("status", "ACTIVE");

            const circleIds = circles?.map((c) => c.circle_id) || [];

            let delegationSuggestions: Array<{
              userId: string;
              fullName: string;
              circleName: string;
            }> = [];

            if (circleIds.length > 0) {
              // Get active members (Contributor, Admin, Owner) from user's circles
              // Sort by recent handoff count (lower = more available)
              const { data: candidates } = await supabaseService
                .from("circle_members")
                .select("user_id, users(display_name), circle_id")
                .in("circle_id", circleIds)
                .neq("user_id", userId)
                .in("role", ["CONTRIBUTOR", "ADMIN", "OWNER"])
                .eq("status", "ACTIVE")
                .limit(10);

              if (candidates && candidates.length > 0) {
                // Get recent handoff counts for each candidate
                const candidatesWithActivity = await Promise.all(
                  candidates.map(async (c) => {
                    const { count } = await supabaseService
                      .from("handoffs")
                      .select("*", { count: "exact", head: true })
                      .eq("created_by", c.user_id)
                      .gte("created_at", sevenDaysAgo);

                    const circle = circles?.find(
                      (circ) => circ.circle_id === c.circle_id,
                    );

                    return {
                      userId: c.user_id,
                      fullName:
                        (c.users as { display_name: string })?.display_name ||
                        "Unknown",
                      circleName:
                        (circle?.circles as { name: string })?.name ||
                        "Care Circle",
                      recentHandoffs: count || 0,
                    };
                  }),
                );

                // Sort by recent activity (lower = more available)
                candidatesWithActivity.sort(
                  (a, b) => a.recentHandoffs - b.recentHandoffs,
                );

                // Take top 3 most available
                delegationSuggestions = candidatesWithActivity
                  .slice(0, 3)
                  .map(({ userId, fullName, circleName }) => ({
                    userId,
                    fullName,
                    circleName,
                  }));
              }
            }

            // Generate alert message
            const { title, message } = generateAlertMessage(riskLevel, signals);

            // Create alert
            const { error: alertError } = await supabaseService
              .from("wellness_alerts")
              .insert({
                user_id: userId,
                risk_level: riskLevel,
                alert_type: "BURNOUT_RISK",
                title,
                message,
                delegation_suggestions: delegationSuggestions,
                status: "ACTIVE",
              });

            if (alertError) {
              console.error(
                "Error creating burnout alert:",
                alertError.code || "unknown",
              );
            } else {
              alertsCreated++;
            }
          }
        }
      } catch (userError) {
        console.error(
          "Error processing user for burnout risk:",
          userError instanceof Error ? userError.name : "unknown",
        );
        // Continue with next user
      }
    }

    const response: EvaluateBurnoutResponse = {
      success: true,
      usersEvaluated,
      alertsCreated,
      timestamp: new Date().toISOString(),
    };

    return jsonResponse(response);
  } catch (error) {
    console.error(
      "Error evaluating burnout risk:",
      error instanceof Error ? error.name : "unknown",
    );
    return errorResponse("INTERNAL_ERROR", "Internal server error", 500);
  }
});
