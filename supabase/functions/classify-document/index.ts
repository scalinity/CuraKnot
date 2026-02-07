import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// MARK: - CORS Headers

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// MARK: - Types

interface ClassifyRequest {
  scanId: string;
  overrideType?: string;
}

interface ClassifyResponse {
  success: boolean;
  documentType?: string;
  confidence?: number;
  source?: "AI" | "USER_OVERRIDE";
  alternates?: Array<{ type: string; confidence: number }>;
  error?: {
    code: string;
    message: string;
  };
}

const DOCUMENT_TYPES = [
  "PRESCRIPTION",
  "LAB_RESULT",
  "DISCHARGE",
  "BILL",
  "EOB",
  "APPOINTMENT",
  "INSURANCE_CARD",
  "MEDICATION_LIST",
  "OTHER",
] as const;

// MARK: - Classification Prompt

const CLASSIFICATION_PROMPT = `You are a document classification system for a family caregiving app called CuraKnot.

Analyze the provided document image(s) and classify it into ONE of these categories:

1. PRESCRIPTION - A prescription from a doctor, pharmacy label, or medication order
2. LAB_RESULT - Laboratory test results, blood work, urinalysis, or diagnostic reports
3. DISCHARGE - Hospital discharge summary, admission/discharge papers
4. BILL - Medical bill, invoice, or statement requiring payment
5. EOB - Explanation of Benefits from an insurance company
6. APPOINTMENT - Appointment notice, reminder, or scheduling confirmation
7. INSURANCE_CARD - Health insurance card (front or back)
8. MEDICATION_LIST - List of current medications from a provider
9. OTHER - Any document that doesn't fit the above categories

Respond with a JSON object:
{
  "documentType": "CATEGORY_NAME",
  "confidence": 0.0 to 1.0,
  "reasoning": "Brief explanation",
  "alternates": [
    {"type": "CATEGORY_NAME", "confidence": 0.0 to 1.0}
  ]
}

Rules:
- Choose the MOST SPECIFIC category that applies
- If confidence is below 0.5, include alternates
- PRESCRIPTION takes priority over MEDICATION_LIST if it's a single prescription
- BILL takes priority over EOB if it requests payment
- Be conservative with confidence scores

Respond ONLY with the JSON object, no additional text.`;

// MARK: - Main Handler

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get auth header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "No authorization header",
          },
        } as ClassifyResponse),
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
        } as ClassifyResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body: ClassifyRequest = await req.json();
    const { scanId, overrideType } = body;

    if (!scanId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Missing scanId",
          },
        } as ClassifyResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check subscription tier for AI classification
    const { data: subscription } = await supabaseService
      .from("subscriptions")
      .select("plan, status")
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    const userPlan = subscription?.plan || "FREE";

    // FREE tier: only manual override allowed
    if (userPlan === "FREE" && !overrideType) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "TIER_GATE",
            message: "AI classification requires Plus or Family plan",
          },
        } as ClassifyResponse),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch the document scan
    const { data: scan, error: scanError } = await supabaseService
      .from("document_scans")
      .select("*")
      .eq("id", scanId)
      .single();

    if (scanError || !scan) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_SCAN",
            message: "Scan not found",
          },
        } as ClassifyResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // SECURITY: Verify user is a member of the scan's circle
    const { data: membership, error: membershipError } = await supabaseService
      .from("circle_members")
      .select("role, status")
      .eq("circle_id", scan.circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (membershipError || !membership) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "ACCESS_DENIED",
            message: "You do not have access to this document",
          },
        } as ClassifyResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // SECURITY: Viewers cannot classify documents
    if (membership.role === "VIEWER") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PERMISSION_DENIED",
            message: "Contributors and above can classify documents",
          },
        } as ClassifyResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // If override type provided, use it directly
    if (
      overrideType &&
      DOCUMENT_TYPES.includes(overrideType as (typeof DOCUMENT_TYPES)[number])
    ) {
      // Update scan with user-selected classification
      const { error: updateError } = await supabaseService
        .from("document_scans")
        .update({
          document_type: overrideType,
          classification_confidence: 1.0,
          classification_source: "USER_OVERRIDE",
          status: "READY",
          updated_at: new Date().toISOString(),
        })
        .eq("id", scanId);

      if (updateError) {
        console.error("Failed to update scan with override:", { scanId });
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "DATABASE_ERROR",
              message: "Failed to save classification",
            },
          } as ClassifyResponse),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          documentType: overrideType,
          confidence: 1.0,
          source: "USER_OVERRIDE",
        } as ClassifyResponse),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update status to processing
    const { error: processingError } = await supabaseService
      .from("document_scans")
      .update({
        status: "PROCESSING",
        updated_at: new Date().toISOString(),
      })
      .eq("id", scanId);

    if (processingError) {
      console.error("Failed to update scan to processing:", { scanId });
    }

    // Get signed URLs for first 3 pages (OpenAI limit)
    const storageKeys = (scan.storage_keys || []).slice(0, 3);
    const imageUrls: string[] = [];

    for (const key of storageKeys) {
      const { data: signedUrl } = await supabaseService.storage
        .from("scanned-documents")
        .createSignedUrl(key, 900); // 15 minutes for longer API calls

      if (signedUrl?.signedUrl) {
        imageUrls.push(signedUrl.signedUrl);
      }
    }

    if (imageUrls.length === 0) {
      // Fallback: try to use OCR text if available
      if (!scan.ocr_text) {
        await supabaseService
          .from("document_scans")
          .update({
            status: "FAILED",
            error_message: "No images or OCR text available",
            updated_at: new Date().toISOString(),
          })
          .eq("id", scanId);

        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "INVALID_SCAN",
              message: "No images available for classification",
            },
          } as ClassifyResponse),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Call OpenAI Vision API
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CONFIGURATION_ERROR",
            message: "OpenAI API key not configured",
          },
        } as ClassifyResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build OpenAI request with images
    const messages: Array<Record<string, unknown>> = [
      {
        role: "system",
        content: CLASSIFICATION_PROMPT,
      },
      {
        role: "user",
        content:
          imageUrls.length > 0
            ? [
                { type: "text", text: "Classify this document:" },
                ...imageUrls.map((url) => ({
                  type: "image_url",
                  image_url: { url, detail: "low" },
                })),
              ]
            : `Classify this document based on the OCR text:\n\n${scan.ocr_text}`,
      },
    ];

    const openaiResponse = await fetch(
      "https://api.openai.com/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages,
          max_tokens: 500,
          temperature: 0.2,
        }),
      },
    );

    if (!openaiResponse.ok) {
      // SECURITY: Log only safe metadata, not error content (may contain PHI)
      console.error("OpenAI API classification failed:", {
        status: openaiResponse.status,
        scanId,
      });

      await supabaseService
        .from("document_scans")
        .update({
          status: "FAILED",
          error_message: "Classification service error",
          updated_at: new Date().toISOString(),
        })
        .eq("id", scanId);

      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PROCESSING_ERROR",
            message: "Classification service unavailable",
          },
        } as ClassifyResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const openaiData = await openaiResponse.json();
    const assistantMessage = openaiData.choices?.[0]?.message?.content || "";

    // Parse classification result
    let classificationResult: {
      documentType: string;
      confidence: number;
      reasoning?: string;
      alternates?: Array<{ type: string; confidence: number }>;
    };

    try {
      // Extract JSON from response (handle markdown code blocks)
      const jsonMatch = assistantMessage.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new Error("No JSON found in response");
      }
      classificationResult = JSON.parse(jsonMatch[0]);
    } catch (_parseError) {
      // SECURITY: Do not log assistantMessage - may contain PHI from OCR
      console.error("Failed to parse classification response:", {
        scanId,
        errorType: "JSON_PARSE_ERROR",
      });

      // Fallback to OTHER with low confidence
      classificationResult = {
        documentType: "OTHER",
        confidence: 0.3,
        reasoning: "Unable to determine document type",
      };
    }

    // Validate document type
    if (
      !DOCUMENT_TYPES.includes(
        classificationResult.documentType as (typeof DOCUMENT_TYPES)[number],
      )
    ) {
      classificationResult.documentType = "OTHER";
      classificationResult.confidence = Math.min(
        classificationResult.confidence,
        0.5,
      );
    }

    // Update scan with classification
    const { error: classifyError } = await supabaseService
      .from("document_scans")
      .update({
        document_type: classificationResult.documentType,
        classification_confidence: classificationResult.confidence,
        classification_source: "AI",
        status: "READY",
        updated_at: new Date().toISOString(),
      })
      .eq("id", scanId);

    if (classifyError) {
      console.error("Failed to save classification:", { scanId });
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to save classification result",
          },
        } as ClassifyResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create audit event (non-blocking - log error but don't fail)
    const { error: auditError } = await supabaseService
      .from("audit_events")
      .insert({
        circle_id: scan.circle_id,
        actor_user_id: user.id,
        event_type: "DOCUMENT_CLASSIFIED",
        object_type: "document_scan",
        object_id: scanId,
        metadata_json: {
          document_type: classificationResult.documentType,
          confidence: classificationResult.confidence,
          source: "AI",
          reasoning: classificationResult.reasoning,
        },
      });

    if (auditError) {
      console.error("Failed to create audit event:", { scanId });
    }

    const response: ClassifyResponse = {
      success: true,
      documentType: classificationResult.documentType,
      confidence: classificationResult.confidence,
      source: "AI",
      alternates: classificationResult.alternates,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error classifying document:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "INTERNAL_ERROR",
          message: "Internal server error",
        },
      } as ClassifyResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
