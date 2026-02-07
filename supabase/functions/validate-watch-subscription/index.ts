import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts";

// MARK: - CORS Headers

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// MARK: - Types

interface ValidateWatchSubscriptionResponse {
  success: boolean;
  subscription_plan?: string;
  subscription_token?: string;
  expires_at?: string;
  error?: {
    code: string;
    message: string;
  };
}

// MARK: - HMAC Signing

async function computeHMACSHA256(
  message: string,
  secret: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const messageData = encoder.encode(message);

  const key = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign("HMAC", key, messageData);
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}

function generateSigningSecret(userId: string): string {
  // Device-specific secret derived from user ID and server secret
  const serverSecret = Deno.env.get("WATCH_SIGNING_SECRET");
  if (!serverSecret) {
    throw new Error("WATCH_SIGNING_SECRET environment variable is not set");
  }
  return `${serverSecret}-${userId.substring(0, 8)}`;
}

// MARK: - Main Handler

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
        } as ValidateWatchSubscriptionResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create Supabase clients
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Client with user context for auth check
    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Service client for subscription lookup (bypasses RLS)
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
        } as ValidateWatchSubscriptionResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Look up user's subscription
    const { data: subscription, error: subError } = await supabaseService
      .from("subscriptions")
      .select("plan, status, period_end")
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    // Default to FREE if no active subscription
    let plan = "FREE";
    let periodEnd: string | null = null;

    if (subscription && !subError) {
      plan = subscription.plan;
      periodEnd = subscription.period_end;
    }

    // Check if plan has Watch access
    const watchAccessPlans = ["PLUS", "FAMILY"];
    const hasWatchAccess = watchAccessPlans.includes(plan);

    if (!hasWatchAccess) {
      // Return FREE status without signed token (no Watch access)
      return new Response(
        JSON.stringify({
          success: true,
          subscription_plan: "FREE",
        } as ValidateWatchSubscriptionResponse),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate signed subscription token for Watch
    const timestamp = Math.floor(Date.now() / 1000);
    const dataToSign = `${plan}|${timestamp}`;
    const signingSecret = generateSigningSecret(user.id);
    const signature = await computeHMACSHA256(dataToSign, signingSecret);

    const subscriptionToken = `${plan}|${timestamp}|${signature}`;

    // Token expires in 24 hours
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

    // Log access for audit
    await supabaseService.from("audit_events").insert({
      actor_user_id: user.id,
      event_type: "WATCH_SUBSCRIPTION_VALIDATED",
      object_type: "subscription",
      metadata_json: {
        plan,
        device: "watch",
        timestamp,
      },
    });

    const response: ValidateWatchSubscriptionResponse = {
      success: true,
      subscription_plan: plan,
      subscription_token: subscriptionToken,
      expires_at: expiresAt,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(
      "Error validating Watch subscription:",
      error instanceof Error ? error.name : "Unknown error",
    );
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "SYNC_SERVER_ERROR",
          message: "Internal server error",
        },
      } as ValidateWatchSubscriptionResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
