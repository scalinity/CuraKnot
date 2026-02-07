import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ValidateInviteRequest {
  token: string;
}

interface ValidateInviteResponse {
  success: boolean;
  circle_id?: string;
  circle_name?: string;
  role?: string;
  error?: {
    code: string;
    message: string;
  };
}

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
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "No authorization header",
          },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create Supabase client with user's token
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Client with user context for auth check
    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Service client for invite operations (bypasses RLS)
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Get current user
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "Invalid or expired token",
          },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body: ValidateInviteRequest = await req.json();
    const { token } = body;

    if (!token) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CIRCLE_INVITE_NOT_FOUND",
            message: "No invite token provided",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Look up invite
    const { data: invite, error: inviteError } = await supabaseService
      .from("circle_invites")
      .select("*, circles(id, name)")
      .eq("token", token)
      .single();

    if (inviteError || !invite) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CIRCLE_INVITE_NOT_FOUND",
            message: "Invalid invite link",
          },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if already used
    if (invite.used_at) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CIRCLE_INVITE_USED",
            message: "This invite has already been used",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if revoked
    if (invite.revoked_at) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CIRCLE_INVITE_REVOKED",
            message: "This invite has been revoked",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check expiration
    if (new Date(invite.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CIRCLE_INVITE_EXPIRED",
            message: "This invite has expired",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if user is already a member
    const { data: existingMember } = await supabaseService
      .from("circle_members")
      .select("id, status")
      .eq("circle_id", invite.circle_id)
      .eq("user_id", user.id)
      .single();

    if (existingMember && existingMember.status === "ACTIVE") {
      return new Response(
        JSON.stringify({
          success: true,
          circle_id: invite.circle_id,
          circle_name: invite.circles?.name,
          role: invite.role,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Add user to circle
    const memberData = {
      circle_id: invite.circle_id,
      user_id: user.id,
      role: invite.role,
      status: "ACTIVE",
      invited_by: invite.created_by,
      invited_at: invite.created_at,
      joined_at: new Date().toISOString(),
    };

    if (existingMember) {
      // Update existing member (was removed, now rejoining)
      await supabaseService
        .from("circle_members")
        .update({ ...memberData, id: existingMember.id })
        .eq("id", existingMember.id);
    } else {
      // Insert new member
      const { error: insertError } = await supabaseService
        .from("circle_members")
        .insert(memberData);

      if (insertError) {
        console.error("Failed to insert member:", insertError);
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "SYNC_SERVER_ERROR",
              message: "Failed to join circle",
            },
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Mark invite as used
    await supabaseService
      .from("circle_invites")
      .update({
        used_at: new Date().toISOString(),
        used_by: user.id,
      })
      .eq("id", invite.id);

    // Create audit event
    await supabaseService.from("audit_events").insert({
      circle_id: invite.circle_id,
      actor_user_id: user.id,
      event_type: "MEMBER_JOINED",
      object_type: "circle_member",
      metadata_json: {
        role: invite.role,
        invite_id: invite.id,
        invited_by: invite.created_by,
      },
    });

    // Notify other members
    const { data: members } = await supabaseService
      .from("circle_members")
      .select("user_id")
      .eq("circle_id", invite.circle_id)
      .eq("status", "ACTIVE")
      .neq("user_id", user.id);

    if (members) {
      const notifications = members.map((m) => ({
        user_id: m.user_id,
        circle_id: invite.circle_id,
        notification_type: "MEMBER_JOINED",
        title: "New Member",
        body: "A new member has joined the care circle",
        data_json: { circle_id: invite.circle_id },
      }));

      await supabaseService.from("notification_outbox").insert(notifications);
    }

    const response: ValidateInviteResponse = {
      success: true,
      circle_id: invite.circle_id,
      circle_name: invite.circles?.name,
      role: invite.role,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "SYNC_SERVER_ERROR", message: "Internal server error" },
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
