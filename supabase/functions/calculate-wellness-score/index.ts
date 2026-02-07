import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  WellnessSignals,
  calculateWellnessScore,
  calculateBehavioralScore,
  calculateTotalScore,
  assessBurnoutRisk,
  analyzeSentiment,
} from "../_shared/wellness-scoring.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

interface CalculateScoreRequest {
  checkInId: string;
}

interface CalculateScoreResponse {
  success: boolean;
  wellnessScore: number;
  behavioralScore: number;
  totalScore: number;
  riskLevel: string;
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
    // Auth check
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse("UNAUTHORIZED", "Missing authorization header", 401);
    }

    const supabaseUser = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authHeader } },
      },
    );
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Get authenticated user
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();

    if (userError || !user) {
      return errorResponse("UNAUTHORIZED", "Invalid token", 401);
    }

    // Check subscription tier (wellness_checkins feature required)
    const { data: hasFeature } = await supabaseService.rpc(
      "has_feature_access",
      {
        p_user_id: user.id,
        p_feature: "wellness_checkins",
      },
    );

    if (!hasFeature) {
      return errorResponse(
        "SUBSCRIPTION_REQUIRED",
        "Wellness tracking requires a Plus or Family subscription",
        402,
      );
    }

    // Parse request
    const { checkInId }: CalculateScoreRequest = await req.json();

    if (!checkInId) {
      return errorResponse("INVALID_INPUT", "checkInId is required", 400);
    }

    // Fetch check-in data (RLS ensures user owns it)
    const { data: checkIn, error: checkInError } = await supabaseService
      .from("wellness_checkins")
      .select(
        "id, user_id, stress_level, sleep_quality, capacity_level, week_start",
      )
      .eq("id", checkInId)
      .eq("user_id", user.id)
      .single();

    if (checkInError || !checkIn) {
      return errorResponse("NOT_FOUND", "Check-in not found", 404);
    }

    // Gather behavioral signals from handoff patterns
    const now = new Date();
    const last7Days = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const prior7Days = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000);

    // Handoff counts for last 7 days
    const { count: handoffCountLast7 } = await supabaseService
      .from("handoffs")
      .select("*", { count: "exact", head: true })
      .eq("created_by", user.id)
      .gte("created_at", last7Days.toISOString());

    // Handoff counts for prior 7 days (days 8-14)
    const { count: handoffCountPrior7 } = await supabaseService
      .from("handoffs")
      .select("*", { count: "exact", head: true })
      .eq("created_by", user.id)
      .gte("created_at", prior7Days.toISOString())
      .lt("created_at", last7Days.toISOString());

    // Late night entries (after 10pm UTC - simplified for MVP)
    const { data: recentHandoffs } = await supabaseService
      .from("handoffs")
      .select("created_at, raw_transcript")
      .eq("created_by", user.id)
      .gte("created_at", last7Days.toISOString());

    const lateNightEntries =
      recentHandoffs?.filter((h) => {
        const hour = new Date(h.created_at).getUTCHours();
        return hour >= 22 || hour <= 5; // 10pm-5am UTC
      }).length || 0;

    // Sentiment analysis from handoff transcripts
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
      .eq("assigned_to", user.id)
      .gte("created_at", last7Days.toISOString());

    const { count: completedTasks } = await supabaseService
      .from("tasks")
      .select("*", { count: "exact", head: true })
      .eq("assigned_to", user.id)
      .eq("status", "COMPLETED")
      .gte("created_at", last7Days.toISOString());

    const taskCompletionRate =
      totalTasks && totalTasks > 0 ? (completedTasks || 0) / totalTasks : 1; // Default to 1 if no tasks

    // Days without break (consecutive days with handoffs)
    const { data: last30DaysHandoffs } = await supabaseService
      .from("handoffs")
      .select("created_at")
      .eq("created_by", user.id)
      .gte(
        "created_at",
        new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString(),
      )
      .order("created_at", { ascending: false });

    let daysWithoutBreak = 0;
    if (last30DaysHandoffs && last30DaysHandoffs.length > 0) {
      const handoffDates = new Set(
        last30DaysHandoffs.map(
          (h) => new Date(h.created_at).toISOString().split("T")[0],
        ),
      );

      // Count consecutive days from today with handoffs
      for (let i = 0; i < 30; i++) {
        const date = new Date(now.getTime() - i * 24 * 60 * 60 * 1000)
          .toISOString()
          .split("T")[0];
        if (handoffDates.has(date)) {
          daysWithoutBreak++;
        } else {
          break; // Break on first day without handoffs
        }
      }
    }

    // Build signals object
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

    // Calculate scores
    const wellnessScore = calculateWellnessScore(signals);
    const behavioralScore = calculateBehavioralScore(signals);
    const totalScore = calculateTotalScore(wellnessScore, behavioralScore);
    const riskLevel = assessBurnoutRisk(signals);

    // Update check-in with calculated scores
    const { error: updateError } = await supabaseService
      .from("wellness_checkins")
      .update({
        wellness_score: wellnessScore,
        behavioral_score: behavioralScore,
        total_score: totalScore,
        updated_at: new Date().toISOString(),
      })
      .eq("id", checkInId);

    if (updateError) {
      console.error("Error updating check-in:", updateError);
      // Continue anyway - scores are still returned
    }

    const response: CalculateScoreResponse = {
      success: true,
      wellnessScore,
      behavioralScore,
      totalScore,
      riskLevel,
    };

    return jsonResponse(response);
  } catch (error) {
    console.error("Error calculating wellness score:", error);
    return errorResponse("INTERNAL_ERROR", "Internal server error", 500);
  }
});
