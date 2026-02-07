import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ScanRequest {
  circle_id: string;
  patient_id: string;
  image_keys: string[]; // Storage keys for uploaded images
}

interface ParsedMed {
  name: string;
  dose?: string;
  schedule?: string;
  purpose?: string;
  prescriber?: string;
  confidence: {
    name: number;
    dose?: number;
    schedule?: number;
  };
}

interface ScanResponse {
  success: boolean;
  session_id?: string;
  proposals_count?: number;
  status?: string;
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

    const body: ScanRequest = await req.json();
    const { circle_id, patient_id, image_keys } = body;

    if (!circle_id || !patient_id || !image_keys?.length) {
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

    // Check membership
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership || membership.role === "VIEWER") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_ROLE_FORBIDDEN",
            message: "Insufficient permissions",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create scan session
    const { data: session, error: sessionError } = await supabaseService
      .from("med_scan_sessions")
      .insert({
        circle_id,
        patient_id,
        created_by: user.id,
        source_object_keys: image_keys,
        status: "PENDING",
      })
      .select()
      .single();

    if (sessionError) {
      console.error("Session creation error:", sessionError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to create scan session",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get signed URLs for images
    const imageUrls: string[] = [];
    for (const key of image_keys) {
      const { data: signedUrl } = await supabaseService.storage
        .from("attachments")
        .createSignedUrl(key, 300); // 5 minutes
      if (signedUrl?.signedUrl) {
        imageUrls.push(signedUrl.signedUrl);
      }
    }

    // Perform OCR (in production, this would call an external OCR service)
    const ocrResult = await performOCR(imageUrls);

    // Parse medications from OCR text
    const parsedMeds = parseMedicationsFromText(ocrResult.text);

    // Process results
    const { data: processResult, error: processError } =
      await supabaseService.rpc("process_med_scan_results", {
        p_session_id: session.id,
        p_ocr_text: ocrResult.text,
        p_parsed_meds: parsedMeds,
      });

    if (processError) {
      console.error("Process error:", processError);
      await supabaseService
        .from("med_scan_sessions")
        .update({ status: "FAILED", error_message: processError.message })
        .eq("id", session.id);

      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PROCESSING_ERROR",
            message: "Failed to process scan results",
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
      event_type: "MED_SCAN_COMPLETED",
      object_type: "med_scan_session",
      object_id: session.id,
      metadata_json: { proposals_created: processResult.proposals_created },
    });

    const response: ScanResponse = {
      success: true,
      session_id: session.id,
      proposals_count: processResult.proposals_created,
      status: processResult.status,
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

async function performOCR(imageUrls: string[]): Promise<{ text: string }> {
  // In production, this would call Google Cloud Vision, AWS Textract, or similar
  // For now, return a mock result

  // Simulated OCR text from medication labels
  const mockOcrText = `
    LISINOPRIL 10MG TABLET
    Take one tablet by mouth once daily
    Dr. Smith, MD
    Qty: 30
    
    METFORMIN HCL 500MG
    Take one tablet twice daily with meals
    Dr. Johnson
    
    ATORVASTATIN 20MG
    Take one tablet at bedtime
    Dr. Smith, MD
  `;

  return { text: mockOcrText };
}

function parseMedicationsFromText(ocrText: string): ParsedMed[] {
  // In production, this would use NLP/ML to extract medications
  // For now, use simple pattern matching

  const medications: ParsedMed[] = [];

  // Common medication name patterns
  const medPatterns = [
    /([A-Z][A-Z\s]+)\s+(\d+(?:\.\d+)?(?:MG|MCG|ML|G))\s*(TABLET|CAPSULE|SOLUTION)?/gi,
  ];

  const lines = ocrText.split("\n").filter((l) => l.trim());

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    for (const pattern of medPatterns) {
      const match = pattern.exec(line);
      if (match) {
        const med: ParsedMed = {
          name: match[1].trim(),
          dose: match[2],
          confidence: {
            name: 0.9,
            dose: 0.85,
          },
        };

        // Look for schedule in next line
        if (i + 1 < lines.length) {
          const nextLine = lines[i + 1].toLowerCase();
          if (nextLine.includes("take") || nextLine.includes("daily")) {
            med.schedule = lines[i + 1].trim();
            med.confidence.schedule = 0.8;
          }
        }

        // Look for prescriber
        for (let j = i; j < Math.min(i + 3, lines.length); j++) {
          const checkLine = lines[j];
          if (checkLine.includes("Dr.") || checkLine.includes("MD")) {
            med.prescriber = checkLine.trim();
            break;
          }
        }

        medications.push(med);
        break;
      }
    }
  }

  return medications;
}
