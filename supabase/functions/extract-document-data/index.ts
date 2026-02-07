import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// MARK: - CORS Headers

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// MARK: - Types

interface ExtractRequest {
  scanId: string;
}

interface ExtractResponse {
  success: boolean;
  fields?: Record<string, unknown>;
  confidence?: number;
  error?: {
    code: string;
    message: string;
  };
}

// MARK: - Extraction Prompts by Document Type

const EXTRACTION_PROMPTS: Record<string, string> = {
  PRESCRIPTION: `Extract the following fields from this prescription document:
- medication: The name of the medication (generic and/or brand name)
- dosage: The dose (e.g., "10mg", "500mg")
- frequency: How often to take (e.g., "once daily", "twice daily with meals")
- prescriber: The doctor/prescriber name
- prescriberPhone: Prescriber's phone number if visible
- pharmacy: The pharmacy name
- rxNumber: The prescription/Rx number
- fillDate: Date the prescription was filled (ISO format YYYY-MM-DD)
- refills: Number of refills remaining (as integer)

Return a JSON object with these fields. Use null for any field not found.`,

  LAB_RESULT: `Extract the following fields from this lab result document:
- testName: The name of the test performed
- result: The test result value with units
- normalRange: The reference/normal range
- performedDate: Date the test was performed (ISO format YYYY-MM-DD)
- orderedBy: The ordering physician's name
- lab: The laboratory name
- abnormal: Whether the result is abnormal (true/false)
- notes: Any additional notes or comments

Return a JSON object with these fields. Use null for any field not found.`,

  DISCHARGE: `Extract the following fields from this discharge summary:
- facility: The hospital/facility name
- dischargeDate: Date of discharge (ISO format YYYY-MM-DD)
- admissionDate: Date of admission if available (ISO format YYYY-MM-DD)
- diagnosis: Primary diagnosis or diagnoses (as string or array)
- followUpInstructions: Follow-up care instructions
- medications: List of medications prescribed at discharge (as array of strings)
- restrictions: Activity or diet restrictions
- followUpAppointments: Any scheduled follow-up appointments

Return a JSON object with these fields. Use null for any field not found.`,

  BILL: `Extract the following fields from this medical bill:
- provider: The healthcare provider/facility name
- serviceDate: Date of service (ISO format YYYY-MM-DD)
- totalAmount: Total amount billed (as decimal number)
- amountDue: Amount currently due (as decimal number)
- dueDate: Payment due date (ISO format YYYY-MM-DD)
- accountNumber: Account or statement number
- patientName: Patient name on the bill
- services: List of services/items billed (as array)

Return a JSON object with these fields. Use null for any field not found.`,

  EOB: `Extract the following fields from this Explanation of Benefits:
- provider: The healthcare provider name
- serviceDate: Date of service (ISO format YYYY-MM-DD)
- claimNumber: The claim number
- amountBilled: Total amount billed by provider (as decimal)
- amountAllowed: Insurance allowed amount (as decimal)
- insurancePaid: Amount paid by insurance (as decimal)
- patientResponsibility: Amount patient owes (as decimal)
- deductible: Deductible amount applied (as decimal)
- copay: Copay amount if applicable (as decimal)

Return a JSON object with these fields. Use null for any field not found.`,

  APPOINTMENT: `Extract the following fields from this appointment notice:
- provider: The doctor/provider name
- specialty: Medical specialty if mentioned
- appointmentDate: Date of appointment (ISO format YYYY-MM-DD)
- appointmentTime: Time of appointment (24-hour format HH:MM)
- location: Office address or location name
- phone: Contact phone number
- instructions: Any preparation or arrival instructions
- confirmationNumber: Appointment confirmation number if visible

Return a JSON object with these fields. Use null for any field not found.`,

  INSURANCE_CARD: `Extract the following fields from this insurance card:
- insuranceName: The insurance company name
- planName: The specific plan name
- memberId: Member ID number
- groupNumber: Group number
- subscriberName: Name of subscriber/policy holder
- effectiveDate: Coverage effective date (ISO format YYYY-MM-DD)
- rxBin: Pharmacy BIN number
- rxPcn: Pharmacy PCN
- rxGroup: Pharmacy group number
- customerServicePhone: Customer service phone number
- claimsAddress: Address for claims if visible

Return a JSON object with these fields. Use null for any field not found.`,

  MEDICATION_LIST: `Extract the following fields from this medication list:
- medications: Array of medication objects, each containing:
  - name: Medication name
  - dosage: Dose (e.g., "10mg")
  - frequency: How often taken
  - prescriber: Prescribing doctor if listed
  - startDate: When started if listed
  - purpose: What it's for if listed
- preparedBy: Who prepared/printed the list
- preparedDate: Date the list was prepared (ISO format YYYY-MM-DD)
- patientName: Patient name on the list

Return a JSON object with these fields. Use null for any field not found.`,

  OTHER: `Extract any relevant information from this document:
- title: Document title or heading
- date: Any date found (ISO format YYYY-MM-DD)
- provider: Healthcare provider if mentioned
- summary: Brief summary of the document content
- keyPoints: Important information as an array of strings

Return a JSON object with these fields. Use null for any field not found.`,
};

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
        } as ExtractResponse),
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
        } as ExtractResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body: ExtractRequest = await req.json();
    const { scanId } = body;

    if (!scanId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Missing scanId",
          },
        } as ExtractResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check subscription tier - FAMILY only
    const { data: subscription } = await supabaseService
      .from("subscriptions")
      .select("plan, status")
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    const userPlan = subscription?.plan || "FREE";

    if (userPlan !== "FAMILY") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "TIER_GATE",
            message: "Field extraction requires Family plan",
          },
        } as ExtractResponse),
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
        } as ExtractResponse),
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
        } as ExtractResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // SECURITY: Viewers cannot extract document data
    if (membership.role === "VIEWER") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PERMISSION_DENIED",
            message: "Contributors and above can extract document data",
          },
        } as ExtractResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify scan has been classified
    if (!scan.document_type || scan.status !== "READY") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_STATE",
            message: "Scan must be classified before extraction",
          },
        } as ExtractResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get extraction prompt for document type
    const extractionPrompt =
      EXTRACTION_PROMPTS[scan.document_type] || EXTRACTION_PROMPTS["OTHER"];

    // Get signed URLs for all pages
    const storageKeys = scan.storage_keys || [];
    const imageUrls: string[] = [];

    for (const key of storageKeys) {
      const { data: signedUrl } = await supabaseService.storage
        .from("scanned-documents")
        .createSignedUrl(key, 900); // 15 minutes for longer API calls

      if (signedUrl?.signedUrl) {
        imageUrls.push(signedUrl.signedUrl);
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
        } as ExtractResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build content array with images
    const contentArray: Array<Record<string, unknown>> = [
      { type: "text", text: extractionPrompt },
    ];

    if (imageUrls.length > 0) {
      for (const url of imageUrls.slice(0, 5)) {
        // Limit to 5 pages
        contentArray.push({
          type: "image_url",
          image_url: { url, detail: "high" },
        });
      }
    } else if (scan.ocr_text) {
      contentArray.push({
        type: "text",
        text: `\n\nOCR Text:\n${scan.ocr_text}`,
      });
    }

    const openaiResponse = await fetch(
      "https://api.openai.com/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o",
          messages: [
            {
              role: "system",
              content:
                "You are a document data extraction system. Extract structured data from medical and healthcare documents. Return ONLY a valid JSON object with the requested fields.",
            },
            {
              role: "user",
              content: contentArray,
            },
          ],
          max_tokens: 2000,
          temperature: 0.1,
          response_format: { type: "json_object" },
        }),
      },
    );

    if (!openaiResponse.ok) {
      // Log only safe metadata, not error content (may contain PHI)
      console.error("OpenAI API extraction failed:", {
        status: openaiResponse.status,
        scanId,
      });

      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PROCESSING_ERROR",
            message: "Extraction service unavailable",
          },
        } as ExtractResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const openaiData = await openaiResponse.json();
    const assistantMessage = openaiData.choices?.[0]?.message?.content || "{}";

    // Parse extracted fields
    let extractedFields: Record<string, unknown>;
    try {
      extractedFields = JSON.parse(assistantMessage);
    } catch (_parseError) {
      // SECURITY: Do not log assistantMessage - contains PHI
      console.error("Failed to parse extraction response:", {
        scanId,
        errorType: "JSON_PARSE_ERROR",
      });
      extractedFields = {};
    }

    // Calculate confidence based on how many fields were extracted
    const totalExpectedFields = Object.keys(
      JSON.parse(
        `{${
          extractionPrompt
            .match(/- \w+:/g)
            ?.map((f) => `"${f.slice(2, -1)}": null`)
            .join(",") || ""
        }}`,
      ),
    ).length;
    const extractedFieldCount = Object.values(extractedFields).filter(
      (v) => v !== null && v !== undefined && v !== "",
    ).length;
    const confidence =
      totalExpectedFields > 0 ? extractedFieldCount / totalExpectedFields : 0.5;

    // Update scan with extracted fields
    const { error: updateError } = await supabaseService
      .from("document_scans")
      .update({
        extracted_fields_json: extractedFields,
        extraction_confidence: confidence,
        updated_at: new Date().toISOString(),
      })
      .eq("id", scanId);

    if (updateError) {
      console.error("Failed to save extraction:", { scanId });
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to save extracted fields",
          },
        } as ExtractResponse),
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
        event_type: "DOCUMENT_EXTRACTED",
        object_type: "document_scan",
        object_id: scanId,
        metadata_json: {
          document_type: scan.document_type,
          fields_extracted: extractedFieldCount,
          confidence,
        },
      });

    if (auditError) {
      console.error("Failed to create audit event:", { scanId });
    }

    const response: ExtractResponse = {
      success: true,
      fields: extractedFields,
      confidence,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error extracting document data:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "INTERNAL_ERROR",
          message: "Internal server error",
        },
      } as ExtractResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
