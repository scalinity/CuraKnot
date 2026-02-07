import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

/**
 * Get Delegation Candidates
 *
 * PRIVACY: This function returns circle members sorted by recent activity.
 * Suggestions are based on CIRCLE MEMBERSHIP, NOT on comparing wellness scores
 * across users. Only the requesting user's wellness data is ever accessed.
 */

interface DelegationCandidate {
  userId: string;
  fullName: string;
  role: string;
  recentHandoffCount: number;
  circleId: string;
  circleName: string;
}

interface DelegationCandidatesResponse {
  success: boolean;
  candidates: DelegationCandidate[];
  sortedBy: string;
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

    // Get user's active circles
    const { data: circles, error: circlesError } = await supabaseService
      .from("circle_members")
      .select("circle_id, circles(name)")
      .eq("user_id", user.id)
      .eq("status", "ACTIVE");

    if (circlesError) {
      console.error("Error fetching circles:", circlesError);
      return errorResponse("DATABASE_ERROR", "Failed to fetch circles", 500);
    }

    if (!circles || circles.length === 0) {
      return jsonResponse({
        success: true,
        candidates: [],
        sortedBy: "recent_activity",
        message: "No active circles found",
      });
    }

    const circleIds = circles.map((c) => c.circle_id);
    const sevenDaysAgo = new Date(
      Date.now() - 7 * 24 * 60 * 60 * 1000,
    ).toISOString();

    // Get active members (Contributor, Admin, Owner) from user's circles
    // Exclude the requesting user
    const { data: members, error: membersError } = await supabaseService
      .from("circle_members")
      .select("user_id, role, circle_id, users(display_name)")
      .in("circle_id", circleIds)
      .neq("user_id", user.id)
      .in("role", ["CONTRIBUTOR", "ADMIN", "OWNER"])
      .eq("status", "ACTIVE");

    if (membersError) {
      console.error("Error fetching members:", membersError);
      return errorResponse("DATABASE_ERROR", "Failed to fetch members", 500);
    }

    if (!members || members.length === 0) {
      return jsonResponse({
        success: true,
        candidates: [],
        sortedBy: "recent_activity",
        message: "No other active members found",
      });
    }

    // Calculate recent handoff count for each member (last 7 days)
    // This is PUBLIC activity data, NOT wellness scores
    const candidates: DelegationCandidate[] = await Promise.all(
      members.map(async (member) => {
        const { count: recentHandoffCount } = await supabaseService
          .from("handoffs")
          .select("*", { count: "exact", head: true })
          .eq("created_by", member.user_id)
          .gte("created_at", sevenDaysAgo);

        const circle = circles.find((c) => c.circle_id === member.circle_id);

        return {
          userId: member.user_id,
          fullName:
            (member.users as { display_name: string })?.display_name ||
            "Unknown",
          role: member.role,
          recentHandoffCount: recentHandoffCount || 0,
          circleId: member.circle_id,
          circleName:
            (circle?.circles as { name: string })?.name || "Care Circle",
        };
      }),
    );

    // Sort by recent activity (lower = more available to help)
    const sortedCandidates = candidates.sort(
      (a, b) => a.recentHandoffCount - b.recentHandoffCount,
    );

    const response: DelegationCandidatesResponse = {
      success: true,
      candidates: sortedCandidates,
      sortedBy: "recent_activity",
    };

    return jsonResponse(response);
  } catch (error) {
    console.error("Error fetching delegation candidates:", error);
    return errorResponse("INTERNAL_ERROR", "Internal server error", 500);
  }
});
