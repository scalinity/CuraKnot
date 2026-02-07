import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ResolveShareResponse {
  success: boolean;
  document_type?: string;
  title?: string;
  document_url?: string;
  patient_name?: string;
  execution_date?: string;
  expiration_date?: string;
  agent_name?: string;
  error?: { code: string; message: string };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Extract token from query params or body
    let token: string | null = null;
    let accessCode: string | null = null;

    const url = new URL(req.url);
    token = url.searchParams.get("token");

    if (req.method === "POST") {
      const body = await req.json();
      token = body.token || token;
      accessCode = body.access_code || null;
    }

    if (!token) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "MISSING_TOKEN", message: "Share token is required" },
        } satisfies ResolveShareResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Look up share record
    const { data: share, error: shareError } = await supabaseService
      .from("legal_document_shares")
      .select("*")
      .eq("share_token", token)
      .single();

    if (shareError || !share) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SHARE_NOT_FOUND",
            message: "Share link not found or invalid",
          },
        } satisfies ResolveShareResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check expiration
    if (new Date(share.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SHARE_EXPIRED",
            message: "This share link has expired",
          },
        } satisfies ResolveShareResponse),
        {
          status: 410,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check max views
    if (share.max_views !== null && share.view_count >= share.max_views) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SHARE_VIEW_LIMIT",
            message: "This share link has reached its view limit",
          },
        } satisfies ResolveShareResponse),
        {
          status: 410,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate access code if required
    if (share.access_code) {
      if (!accessCode) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "ACCESS_CODE_REQUIRED",
              message: "An access code is required to view this document",
            },
          } satisfies ResolveShareResponse),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Constant-time comparison to prevent timing attacks
      const expected = new TextEncoder().encode(share.access_code);
      const provided = new TextEncoder().encode(accessCode);
      if (
        expected.length !== provided.length ||
        !crypto.subtle.timingSafeEqual(expected, provided)
      ) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "ACCESS_CODE_INVALID",
              message: "Invalid access code",
            },
          } satisfies ResolveShareResponse),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Fetch document details
    const { data: document, error: docError } = await supabaseService
      .from("legal_documents")
      .select(
        "id, document_type, title, storage_key, execution_date, expiration_date, agent_name, patient_id, status",
      )
      .eq("id", share.document_id)
      .single();

    if (docError || !document) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DOC_NOT_FOUND",
            message: "The shared document no longer exists",
          },
        } satisfies ResolveShareResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Reject share links for non-active documents (revoked, superseded, expired)
    if (document.status !== "ACTIVE") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DOC_NOT_ACTIVE",
            message: "This document is no longer available",
          },
        } satisfies ResolveShareResponse),
        {
          status: 410,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get patient name
    const { data: patient } = await supabaseService
      .from("patients")
      .select("display_name")
      .eq("id", document.patient_id)
      .single();

    // Generate short-lived signed URL (15 minutes)
    const { data: signedUrl, error: signError } = await supabaseService.storage
      .from("legal-documents")
      .createSignedUrl(document.storage_key, 900);

    if (signError || !signedUrl?.signedUrl) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "URL_GENERATION_FAILED",
            message: "Failed to generate document access URL",
          },
        } satisfies ResolveShareResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Increment view count atomically via RPC
    const { error: rpcError } = await supabaseService.rpc(
      "increment_share_view_count",
      { p_share_id: share.id },
    );
    if (rpcError) {
      console.error(
        "Failed to increment share view count for share",
        share.id,
        ":",
        rpcError.message,
      );
      // Continue serving the document — the view count being slightly off
      // is preferable to blocking document access entirely.
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
        document_id: share.document_id,
        user_id: null, // External access
        action: "VIEWED",
        details_json: {
          access_method: "share_link",
          share_token: token,
          // Approximate — the authoritative count is in legal_document_shares.view_count
          view_number_approx: share.view_count + 1,
        },
        ip_address: ipAddress,
        user_agent: userAgent,
      });
    if (auditError) {
      console.error("Audit log insert failed:", auditError.message);
    }

    const response: ResolveShareResponse = {
      success: true,
      document_type: document.document_type,
      title: document.title,
      document_url: signedUrl.signedUrl,
      patient_name: patient?.display_name,
      execution_date: document.execution_date,
      expiration_date: document.expiration_date,
      agent_name: document.agent_name,
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
      } satisfies ResolveShareResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
