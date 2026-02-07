import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface StructureRequest {
  handoff_id: string;
  transcript: string;
  handoff_type: string;
  patient_id: string;
}

interface StructuredBrief {
  title: string;
  summary: string;
  status?: {
    mood_energy?: string;
    pain?: number;
    appetite?: string;
    sleep?: string;
    mobility?: string;
    safety_flags?: string[];
  };
  changes?: {
    med_changes?: {
      name: string;
      change: string;
      details?: string;
      effective?: string;
    }[];
    symptom_changes?: {
      symptom: string;
      details?: string;
    }[];
    care_plan_changes?: {
      area: string;
      details?: string;
    }[];
  };
  questions_for_clinician?: {
    question: string;
    priority?: string;
  }[];
  next_steps?: {
    action: string;
    suggested_owner?: string;
    due?: string;
    priority?: string;
  }[];
  keywords?: string[];
}

interface ConfidenceScores {
  overall: number;
  fields: {
    summary?: number;
    med_changes?: number;
    next_steps?: number;
  };
}

interface StructureResponse {
  success: boolean;
  structured_brief?: StructuredBrief;
  confidence?: ConfidenceScores;
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
          error: { code: "AUTH_INVALID_TOKEN", message: "Invalid token" },
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: StructureRequest = await req.json();
    const { handoff_id, transcript, handoff_type, patient_id } = body;

    if (!handoff_id || !transcript || !handoff_type) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "STRUCT_VALIDATION_FAILED",
            message: "Missing required fields",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get patient context for better extraction
    const { data: patient } = await supabaseService
      .from("patients")
      .select("display_name")
      .eq("id", patient_id)
      .single();

    // Get known medications for context
    const { data: medications } = await supabaseService
      .from("binder_items")
      .select("title, content_json")
      .eq("patient_id", patient_id)
      .eq("type", "MED")
      .eq("is_active", true);

    const knownMeds = medications?.map((m) => m.title) || [];

    // In production: Call LLM provider (OpenAI, Anthropic, etc.)
    const llmProviderUrl = Deno.env.get("LLM_PROVIDER_URL");
    const llmApiKey = Deno.env.get("LLM_API_KEY");

    let structuredBrief: StructuredBrief;
    let confidence: ConfidenceScores;

    if (llmProviderUrl && llmApiKey) {
      // Real LLM integration would go here
      // Example prompt structure:
      /*
      const systemPrompt = `You are a healthcare documentation assistant. 
      Extract structured information from caregiver handoff notes.
      Patient: ${patient?.display_name}
      Known medications: ${knownMeds.join(", ")}
      
      Extract: title (<=80 chars), summary (<=600 chars), status observations,
      medication changes, symptom changes, care plan changes, questions for clinician,
      and actionable next steps with priorities.
      
      Return JSON matching the StructuredBrief schema.`;
      
      const response = await fetch(llmProviderUrl, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${llmApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4",
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: transcript },
          ],
        }),
      });
      
      const result = await response.json();
      structuredBrief = JSON.parse(result.choices[0].message.content);
      */
    }

    // Demo: Generate structured brief from transcript using simple extraction
    structuredBrief = extractStructuredBrief(
      transcript,
      handoff_type,
      patient?.display_name,
    );
    confidence = {
      overall: 0.85,
      fields: {
        summary: 0.9,
        med_changes: 0.75,
        next_steps: 0.85,
      },
    };

    // Store confidence scores on handoff
    await supabaseService
      .from("handoffs")
      .update({
        confidence_json: confidence,
      })
      .eq("id", handoff_id);

    const response: StructureResponse = {
      success: true,
      structured_brief: structuredBrief,
      confidence,
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

// Simple extraction function (replace with LLM in production)
function extractStructuredBrief(
  transcript: string,
  handoffType: string,
  patientName?: string,
): StructuredBrief {
  const lowerTranscript = transcript.toLowerCase();

  // Extract title
  let title = "";
  const typeMap: Record<string, string> = {
    VISIT: "Visit",
    CALL: "Phone Call",
    APPOINTMENT: "Appointment",
    FACILITY_UPDATE: "Facility Update",
    OTHER: "Update",
  };
  title = `${typeMap[handoffType] || "Update"}`;

  // Try to extract doctor/facility name
  const drMatch = transcript.match(/(?:dr\.?|doctor)\s+(\w+)/i);
  if (drMatch) {
    title += ` with Dr. ${drMatch[1]}`;
  }

  // Extract summary (first 600 chars, trying to end at sentence)
  let summary = transcript.substring(0, 600);
  const lastPeriod = summary.lastIndexOf(".");
  if (lastPeriod > 200) {
    summary = summary.substring(0, lastPeriod + 1);
  }

  // Extract status indicators
  const status: StructuredBrief["status"] = {};

  if (
    lowerTranscript.includes("good spirits") ||
    lowerTranscript.includes("good mood")
  ) {
    status.mood_energy = "Good spirits";
  } else if (
    lowerTranscript.includes("tired") ||
    lowerTranscript.includes("fatigue")
  ) {
    status.mood_energy = "Fatigued";
  }

  // Pain level extraction
  const painMatch = lowerTranscript.match(
    /pain\s*(?:level|score)?\s*(?:is|of|at)?\s*(\d+)/,
  );
  if (painMatch) {
    status.pain = parseInt(painMatch[1]);
  }

  // Mobility
  if (
    lowerTranscript.includes("walker") ||
    lowerTranscript.includes("walking")
  ) {
    status.mobility = lowerTranscript.includes("walker")
      ? "Using walker"
      : "Walking independently";
  }

  // Safety flags
  const safetyFlags: string[] = [];
  if (lowerTranscript.includes("fall") || lowerTranscript.includes("fell")) {
    safetyFlags.push("Fall concern");
  }
  if (
    lowerTranscript.includes("confused") ||
    lowerTranscript.includes("confusion")
  ) {
    safetyFlags.push("Confusion noted");
  }
  if (safetyFlags.length > 0) {
    status.safety_flags = safetyFlags;
  }

  // Extract medication changes
  const medChanges: StructuredBrief["changes"] = { med_changes: [] };

  // Look for dose changes
  const doseMatch = transcript.match(
    /(\w+)\s+(?:increased|decreased|changed)\s+(?:from|to)\s+(\d+\s*mg)/gi,
  );
  if (doseMatch) {
    doseMatch.forEach((match) => {
      const parts = match.match(/(\w+)\s+(increased|decreased|changed)/i);
      if (parts) {
        medChanges.med_changes?.push({
          name: parts[1],
          change: "DOSE",
          details: match,
        });
      }
    });
  }

  // Extract next steps
  const nextSteps: StructuredBrief["next_steps"] = [];

  const actionPatterns = [
    /(?:need to|should|must|have to)\s+(.+?)(?:\.|$)/gi,
    /(?:follow up|schedule|call|pick up)\s+(.+?)(?:\.|$)/gi,
  ];

  actionPatterns.forEach((pattern) => {
    const matches = transcript.matchAll(pattern);
    for (const match of matches) {
      if (match[1] && match[1].length > 5 && match[1].length < 100) {
        nextSteps.push({
          action: match[1].trim(),
          priority: "MED",
        });
      }
    }
  });

  // Extract keywords
  const keywords: string[] = [];
  const keywordPatterns = [
    /(?:medication|prescription|medicine)/gi,
    /(?:appointment|checkup|visit)/gi,
    /(?:blood pressure|bp)/gi,
    /(?:diabetes|blood sugar)/gi,
  ];

  keywordPatterns.forEach((pattern) => {
    if (pattern.test(transcript)) {
      const match = transcript.match(pattern);
      if (match) {
        keywords.push(match[0].toLowerCase());
      }
    }
  });

  return {
    title: title.substring(0, 80),
    summary,
    status: Object.keys(status).length > 0 ? status : undefined,
    changes: medChanges.med_changes?.length ? medChanges : undefined,
    next_steps: nextSteps.length > 0 ? nextSteps : undefined,
    keywords: [...new Set(keywords)],
  };
}
