import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function getCorsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  const allowedOrigins = ["https://curaknot.app", "http://localhost:3000"];
  const allowOrigin = allowedOrigins.includes(origin)
    ? origin
    : allowedOrigins[0];
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

interface SendInvitesRequest {
  meetingId: string;
}

interface AttendeeWithMembership {
  user_id: string;
  circle_members: { status: string }[] | { status: string };
}

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
            message: "Missing authorization",
          },
        }),
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
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CONFIGURATION_ERROR",
            message: "Server configuration error",
          },
        }),
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
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: SendInvitesRequest = await req.json().catch(() => null);
    if (!body) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Invalid or malformed JSON body",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const { meetingId } = body;

    if (!meetingId || !UUID_REGEX.test(meetingId)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Valid meetingId is required",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch meeting
    const { data: meeting, error: meetingError } = await supabaseService
      .from("family_meetings")
      .select("*")
      .eq("id", meetingId)
      .single();

    if (meetingError || !meeting) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "NOT_FOUND", message: "Meeting not found" },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate meeting status - can only send invites for scheduled meetings
    if (meeting.status !== "SCHEDULED") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_STATUS",
            message: "Invites can only be sent for scheduled meetings",
          },
        }),
        {
          status: 422,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify subscription feature access
    const { data: hasFeature } = await supabaseService.rpc(
      "has_feature_access",
      {
        p_user_id: user.id,
        p_feature: "family_meetings",
      },
    );

    if (!hasFeature) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "FEATURE_NOT_AVAILABLE",
            message: "Family Meetings requires a Plus or Family subscription",
          },
        }),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify user is an active circle member FIRST (prevents ex-member creator bypass)
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", meeting.circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_NOT_MEMBER",
            message: "Not a circle member",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Then check if user has permission (creator OR admin)
    const isCreator = meeting.created_by === user.id;
    const isAdmin = membership.role === "OWNER" || membership.role === "ADMIN";

    if (!isCreator && !isAdmin) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_ROLE_FORBIDDEN",
            message: "Only meeting creator or admin can send invites",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch attendees who are still active circle members
    const { data: attendees } = await supabaseService
      .from("meeting_attendees")
      .select("user_id, circle_members!inner(status)")
      .eq("meeting_id", meetingId)
      .eq("circle_members.circle_id", meeting.circle_id)
      .eq("circle_members.status", "ACTIVE");

    if (!attendees || attendees.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          invitesSent: 0,
          calendarEventCreated: false,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Send notifications (no PHI in notification body)
    const notifications = (attendees as AttendeeWithMembership[])
      .filter((a) => a.user_id !== user.id)
      .map((a) => ({
        user_id: a.user_id,
        circle_id: meeting.circle_id,
        notification_type: "MEETING_INVITE",
        title: "Family Meeting Invitation",
        body: "You have been invited to a family meeting. Open the app for details.",
        data_json: {
          meeting_id: meetingId,
          scheduled_at: meeting.scheduled_at,
          format: meeting.format,
        },
      }));

    let invitesSent = 0;
    if (notifications.length > 0) {
      const { error: notifError } = await supabaseService
        .from("notification_outbox")
        .insert(notifications);

      if (!notifError) {
        invitesSent = notifications.length;
      }
    }

    // Create audit event
    await supabaseService.from("audit_events").insert({
      circle_id: meeting.circle_id,
      actor_user_id: user.id,
      event_type: "MEETING_INVITES_SENT",
      object_type: "family_meeting",
      object_id: meetingId,
      metadata_json: {
        invites_sent: invitesSent,
      },
    });

    return new Response(
      JSON.stringify({
        success: true,
        invitesSent,
        calendarEventCreated: false,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (_error) {
    const corsHeaders = getCorsHeaders(req);
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "INTERNAL_ERROR",
          message: "Failed to send meeting invites",
        },
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
