import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SubmitRequest {
  token: string;
  payload: {
    title?: string;
    summary: string;
    update_type?: string;
    notes?: string;
  };
  submitter_name?: string;
  submitter_role?: string;
}

interface ValidateResponse {
  valid: boolean;
  patient_label?: string;
  helper_name?: string;
  error?: string;
}

interface SubmitResponse {
  success: boolean;
  submission_id?: string;
  error?: {
    code: string;
    message: string;
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

  try {
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "submit";

    if (action === "validate") {
      // Validate link (GET request with token param)
      const token = url.searchParams.get("token");

      if (!token) {
        return new Response(
          JSON.stringify({ valid: false, error: "Token is required" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const { data, error } = await supabaseService.rpc(
        "validate_helper_link",
        {
          p_token: token,
        },
      );

      if (error) {
        console.error("Validation error:", error.code || "unknown");
        return new Response(
          JSON.stringify({ valid: false, error: "Validation failed" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const response: ValidateResponse = {
        valid: data.valid,
        patient_label: data.patient_label,
        helper_name: data.helper_name,
        error: data.error,
      };

      return new Response(JSON.stringify(response), {
        status: data.valid ? 200 : 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Submit update (POST request)
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "METHOD_NOT_ALLOWED", message: "POST required" },
        }),
        {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: SubmitRequest = await req.json();
    const { token, payload, submitter_name, submitter_role } = body;

    if (!token || !payload?.summary) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Token and summary are required",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting check (simple: by token)
    const { data: recentSubmissions } = await supabaseService
      .from("helper_submissions")
      .select("id")
      .eq(
        "helper_link_id",
        (
          await supabaseService
            .from("helper_links")
            .select("id")
            .eq("token", token)
            .single()
        ).data?.id,
      )
      .gte("submitted_at", new Date(Date.now() - 60000).toISOString()); // Last minute

    if (recentSubmissions && recentSubmissions.length >= 5) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "RATE_LIMITED",
            message: "Too many submissions. Please wait a moment.",
          },
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Submit
    const { data, error } = await supabaseService.rpc("submit_helper_update", {
      p_token: token,
      p_payload: payload,
      p_submitter_name: submitter_name || null,
      p_submitter_role: submitter_role || null,
    });

    if (error) {
      console.error("Submit error:", error.code || "unknown");
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "DATABASE_ERROR", message: "Submission failed" },
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
          error: { code: "SUBMIT_ERROR", message: data.error },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const response: SubmitResponse = {
      success: true,
      submission_id: data.submission_id,
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
