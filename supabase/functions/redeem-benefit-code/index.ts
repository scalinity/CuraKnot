import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface RedeemRequest {
  code: string;
  circle_id?: string;
}

interface RedeemResponse {
  success: boolean;
  plan?: string;
  org_name?: string;
  error?: {
    code: string;
    message: string;
  };
}

serve(async (req) => {
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
            message: "No authorization header",
          },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

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

    const body: RedeemRequest = await req.json();
    const { code, circle_id } = body;

    if (!code) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "VALIDATION_ERROR", message: "Code is required" },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // If circle_id provided, verify membership
    if (circle_id) {
      const { data: membership } = await supabaseService
        .from("circle_members")
        .select("role")
        .eq("circle_id", circle_id)
        .eq("user_id", user.id)
        .eq("status", "ACTIVE")
        .single();

      if (!membership || !["OWNER", "ADMIN"].includes(membership.role)) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "PERMISSION_DENIED",
              message:
                "You must be a circle owner or admin to apply a benefit code",
            },
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Redeem the code
    const { data, error } = await supabaseService.rpc("redeem_benefit_code", {
      p_code: code,
      p_user_id: user.id,
      p_circle_id: circle_id || null,
    });

    if (error) {
      console.error("Redemption error:", error);
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "DATABASE_ERROR", message: error.message },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (data.error) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "REDEMPTION_ERROR", message: data.error },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const response: RedeemResponse = {
      success: true,
      plan: data.plan,
      org_name: data.org_name,
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
        error: { code: "INTERNAL_ERROR", message: "Internal server error" },
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
