import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface CreateInviteRequest {
  circle_id: string;
  role?: "ADMIN" | "CONTRIBUTOR" | "VIEWER";
  expires_in_days?: number;
}

interface CreateInviteResponse {
  success: boolean;
  invite_id?: string;
  token?: string;
  invite_url?: string;
  expires_at?: string;
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

    // Create Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

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

    // Parse request
    const body: CreateInviteRequest = await req.json();
    const { circle_id, role = "CONTRIBUTOR", expires_in_days = 7 } = body;

    if (!circle_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "CIRCLE_NOT_FOUND", message: "Circle ID required" },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check user's role in circle
    const { data: membership, error: memberError } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (memberError || !membership) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_NOT_MEMBER",
            message: "You are not a member of this circle",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Only OWNER or ADMIN can invite
    if (!["OWNER", "ADMIN"].includes(membership.role)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_ROLE_FORBIDDEN",
            message: "Only admins can invite members",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate secure token
    const tokenBytes = new Uint8Array(32);
    crypto.getRandomValues(tokenBytes);
    const token = Array.from(tokenBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // Calculate expiration
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + expires_in_days);

    // Create invite
    const { data: invite, error: createError } = await supabaseService
      .from("circle_invites")
      .insert({
        circle_id,
        token,
        role,
        created_by: user.id,
        expires_at: expiresAt.toISOString(),
      })
      .select()
      .single();

    if (createError) {
      console.error("Failed to create invite:", createError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SYNC_SERVER_ERROR",
            message: "Failed to create invite",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create audit event
    await supabaseService.from("audit_events").insert({
      circle_id,
      actor_user_id: user.id,
      event_type: "INVITE_CREATED",
      object_type: "circle_invite",
      object_id: invite.id,
      metadata_json: { role, expires_at: expiresAt.toISOString() },
    });

    // Generate invite URL
    const appUrl = Deno.env.get("APP_URL") || "https://curaknot.app";
    const inviteUrl = `${appUrl}/join/${token}`;

    const response: CreateInviteResponse = {
      success: true,
      invite_id: invite.id,
      token,
      invite_url: inviteUrl,
      expires_at: expiresAt.toISOString(),
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
