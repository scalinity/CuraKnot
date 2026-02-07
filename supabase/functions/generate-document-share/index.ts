import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GenerateShareRequest {
  document_id: string;
  expiration_hours: number; // max 168 (7 days)
  require_access_code: boolean;
  max_views?: number; // optional view limit
}

interface GenerateShareResponse {
  success: boolean;
  share_url?: string;
  share_token?: string;
  access_code?: string;
  expires_at?: string;
  error?: { code: string; message: string };
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
          error: { code: "AUTH_MISSING", message: "No authorization header" },
        } satisfies GenerateShareResponse),
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

    // Authenticate
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_INVALID", message: "Invalid token" },
        } satisfies GenerateShareResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: GenerateShareRequest = await req.json();
    const { document_id, expiration_hours, require_access_code, max_views } =
      body;

    // Validate document_id is present
    if (!document_id || typeof document_id !== "string") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_INPUT",
            message: "document_id is required",
          },
        } satisfies GenerateShareResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate expiration (max 7 days = 168 hours)
    if (!expiration_hours || expiration_hours < 1 || expiration_hours > 168) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_EXPIRATION",
            message: "Expiration must be between 1 and 168 hours (7 days)",
          },
        } satisfies GenerateShareResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate max_views if provided (1-1000 range)
    if (
      max_views !== undefined &&
      max_views !== null &&
      (max_views < 1 || max_views > 1000 || !Number.isInteger(max_views))
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_MAX_VIEWS",
            message: "Max views must be an integer between 1 and 1000",
          },
        } satisfies GenerateShareResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify document exists
    const { data: document, error: docError } = await supabaseService
      .from("legal_documents")
      .select("id, circle_id, created_by, status, storage_key, title")
      .eq("id", document_id)
      .single();

    if (docError || !document) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "DOC_NOT_FOUND", message: "Document not found" },
        } satisfies GenerateShareResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify user has share permission (creator always can, or explicit can_share)
    const isCreator = document.created_by === user.id;
    if (!isCreator) {
      const { data: access } = await supabaseService
        .from("legal_document_access")
        .select("can_share")
        .eq("document_id", document_id)
        .eq("user_id", user.id)
        .single();

      if (!access?.can_share) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "SHARE_DENIED",
              message: "You do not have permission to share this document",
            },
          } satisfies GenerateShareResponse),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Generate cryptographically secure share token
    const tokenBytes = new Uint8Array(32);
    crypto.getRandomValues(tokenBytes);
    const shareToken = Array.from(tokenBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // Generate optional access code (6-digit)
    let accessCode: string | null = null;
    if (require_access_code) {
      const codeBytes = new Uint8Array(4);
      crypto.getRandomValues(codeBytes);
      const num =
        ((codeBytes[0] << 24) |
          (codeBytes[1] << 16) |
          (codeBytes[2] << 8) |
          codeBytes[3]) >>>
        0;
      accessCode = String(num % 1000000).padStart(6, "0");
    }

    // Calculate expiration
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + expiration_hours);

    // Insert share record
    const { error: insertError } = await supabaseService
      .from("legal_document_shares")
      .insert({
        document_id,
        shared_by: user.id,
        share_token: shareToken,
        access_code: accessCode,
        expires_at: expiresAt.toISOString(),
        max_views: max_views ?? null,
      });

    if (insertError) {
      console.error("Insert share error:", insertError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SHARE_CREATE_FAILED",
            message: "Failed to create share link",
          },
        } satisfies GenerateShareResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Log audit event
    const ipAddress =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      req.headers.get("x-real-ip") ||
      null;
    const userAgent = req.headers.get("user-agent") || null;

    const { error: auditError } = await supabaseService
      .from("legal_document_audit")
      .insert({
        document_id,
        user_id: user.id,
        action: "SHARED",
        details_json: {
          share_token: shareToken,
          expiration_hours,
          has_access_code: require_access_code,
          max_views: max_views ?? null,
        },
        ip_address: ipAddress,
        user_agent: userAgent,
      });
    if (auditError) {
      console.error("Audit log insert failed:", auditError.message);
    }

    // Build share URL
    const shareUrl = `${supabaseUrl}/functions/v1/resolve-document-share?token=${shareToken}`;

    const response: GenerateShareResponse = {
      success: true,
      share_url: shareUrl,
      share_token: shareToken,
      access_code: accessCode ?? undefined,
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
        error: {
          code: "INTERNAL_ERROR",
          message: "An unexpected error occurred",
        },
      } satisfies GenerateShareResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
