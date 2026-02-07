import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GenerateCardRequest {
  circle_id: string;
  patient_id: string;
  config?: {
    include_name?: boolean;
    include_dob?: boolean;
    include_blood_type?: boolean;
    include_allergies?: boolean;
    include_conditions?: boolean;
    include_medications?: boolean;
    include_emergency_contacts?: boolean;
    include_physician?: boolean;
    include_insurance?: boolean;
    include_notes?: boolean;
  };
  create_share_link?: boolean;
  share_link_ttl_hours?: number;
}

interface GenerateCardResponse {
  success: boolean;
  card_id?: string;
  snapshot?: any;
  share_link?: {
    token: string;
    url: string;
    expires_at: string;
  };
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

    const body: GenerateCardRequest = await req.json();
    const {
      circle_id,
      patient_id,
      config,
      create_share_link = false,
      share_link_ttl_hours = 24,
    } = body;

    if (!circle_id || !patient_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Missing required fields",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create or update the card
    const { data: cardResult, error: cardError } = await supabaseService.rpc(
      "create_or_update_emergency_card",
      {
        p_circle_id: circle_id,
        p_patient_id: patient_id,
        p_user_id: user.id,
        p_config: config || null,
      },
    );

    if (cardError) {
      console.error("Card creation error:", cardError);
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "DATABASE_ERROR", message: "Failed to generate card" },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (cardResult.error) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "CARD_ERROR", message: cardResult.error },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create share link if requested
    let shareLink:
      | { token: string; url: string; expires_at: string }
      | undefined;

    if (create_share_link) {
      const { data: linkData, error: linkError } = await supabaseService.rpc(
        "create_share_link",
        {
          p_circle_id: circle_id,
          p_user_id: user.id,
          p_object_type: "emergency_card",
          p_object_id: cardResult.card_id,
          p_ttl_hours: share_link_ttl_hours,
        },
      );

      if (!linkError && linkData && !linkData.error) {
        const baseUrl =
          Deno.env.get("PUBLIC_SITE_URL") || "https://app.curaknot.com";
        shareLink = {
          token: linkData.token,
          url: `${baseUrl}/emergency/${linkData.token}`,
          expires_at: linkData.expires_at,
        };
      }
    }

    const response: GenerateCardResponse = {
      success: true,
      card_id: cardResult.card_id,
      snapshot: cardResult.snapshot,
      share_link: shareLink,
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
