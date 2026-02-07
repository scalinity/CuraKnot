import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// LLM request timeout in milliseconds (30 seconds)
const LLM_TIMEOUT_MS = 30000;

// Maximum retry attempts for transient failures
const MAX_RETRIES = 2;

// ============================================================================
// Types
// ============================================================================

interface ChatRequest {
  conversation_id?: string;
  message: string;
  patient_id?: string;
  circle_id: string;
}

interface CoachAction {
  type: "CREATE_TASK" | "ADD_QUESTION" | "UPDATE_BINDER" | "CALL_CONTACT";
  label: string;
  prefill_data: Record<string, unknown>;
}

interface UsageInfo {
  plan: string;
  used: number;
  limit: number | null;
  remaining: number | null;
  unlimited: boolean;
}

interface ChatResponse {
  success: boolean;
  conversation_id?: string;
  message_id?: string;
  content?: string;
  actions?: CoachAction[];
  disclaimer?: string;
  suggested_followups?: string[];
  usage_info?: UsageInfo;
  context_references?: string[];
  error?: {
    code: string;
    message: string;
  };
}

interface PatientContext {
  patient_name?: string;
  recent_handoffs: HandoffSummary[];
  medications: MedicationSummary[];
  conditions: string[];
  recent_tasks: TaskSummary[];
}

interface HandoffSummary {
  id: string;
  title: string;
  summary: string;
  type: string;
  created_at: string;
}

interface MedicationSummary {
  name: string;
  category: string;
}

interface TaskSummary {
  title: string;
  status: string;
  due_at?: string;
}

// ============================================================================
// System Prompt
// ============================================================================

const SYSTEM_PROMPT = `You are CuraKnot Care Coach, a supportive AI assistant for family caregivers.

IMPORTANT GUIDELINES:
1. You are NOT a doctor. Never diagnose conditions or prescribe treatments.
2. Always recommend consulting healthcare providers for medical decisions.
3. If someone describes an emergency, immediately direct them to call 911.
4. Be warm, empathetic, and supportive - caregiving is emotionally challenging.
5. Provide practical, actionable suggestions when possible.
6. Reference the patient's specific context (handoffs, medications) when relevant.
7. Acknowledge the caregiver's efforts and validate their feelings.

CAPABILITIES:
- Help caregivers understand care situations and options
- Suggest questions to ask healthcare providers
- Provide emotional support and validation
- Help with care coordination and communication
- Suggest organizational strategies and tools

LIMITATIONS:
- You are NOT a doctor and cannot diagnose or prescribe
- You cannot provide emergency medical advice
- You should not make clinical recommendations
- You cannot replace professional healthcare providers

RESPONSE FORMAT:
- Start with empathy or acknowledgment when appropriate
- Provide clear, structured information
- Include relevant context from their care record when available
- Suggest concrete next steps
- Keep responses concise but helpful

When referencing context, mention it naturally: "I see from the handoff on [date] that..."

NEVER:
- Recommend specific medications or dosages
- Suggest stopping prescribed treatments
- Make predictions about prognosis
- Provide mental health crisis counseling (direct to 988 for mental health crisis)`;

// ============================================================================
// Emergency Detection
// ============================================================================

const EMERGENCY_PATTERNS = [
  /chest\s*pain/i,
  /can'?t\s*breathe/i,
  /difficulty\s*breathing/i,
  /stroke/i,
  /heart\s*attack/i,
  /unconscious/i,
  /not\s*responsive/i,
  /unresponsive/i,
  /severe\s*bleeding/i,
  /choking/i,
  /seizure/i,
  /overdose/i,
  /suicide/i,
  /kill\s*(myself|themselves|herself|himself)/i,
  /want\s*to\s*die/i,
  /end\s*my\s*life/i,
];

const MENTAL_HEALTH_CRISIS_PATTERNS = [
  /suicide/i,
  /suicidal/i,
  /kill\s*(myself|themselves)/i,
  /want\s*to\s*die/i,
  /end\s*my\s*life/i,
  /self\s*harm/i,
  /hurting\s*myself/i,
];

function detectEmergency(message: string): {
  isEmergency: boolean;
  isMentalHealthCrisis: boolean;
} {
  const isEmergency = EMERGENCY_PATTERNS.some((pattern) =>
    pattern.test(message),
  );
  const isMentalHealthCrisis = MENTAL_HEALTH_CRISIS_PATTERNS.some((pattern) =>
    pattern.test(message),
  );
  return { isEmergency, isMentalHealthCrisis };
}

// ============================================================================
// Input Sanitization (Prompt Injection Prevention)
// ============================================================================

function sanitizeUserInput(input: string): string {
  // Remove common prompt injection patterns
  let sanitized = input
    // Remove attempts to override system prompt
    .replace(/ignore\s+(previous|all|above)\s+(instructions?|prompts?)/gi, "")
    .replace(
      /disregard\s+(previous|all|above)\s+(instructions?|prompts?)/gi,
      "",
    )
    .replace(/forget\s+(previous|all|above)\s+(instructions?|prompts?)/gi, "")
    // Remove role-play injection attempts
    .replace(/you\s+are\s+now\s+/gi, "")
    .replace(/pretend\s+(to\s+be|you're)\s+/gi, "")
    .replace(/act\s+as\s+(if\s+you're\s+)?/gi, "")
    // Remove attempts to extract system prompt
    .replace(/what\s+(is|are)\s+your\s+(instructions?|prompts?|rules?)/gi, "")
    .replace(/show\s+me\s+your\s+(system\s+)?prompt/gi, "")
    .replace(/repeat\s+(your\s+)?(system\s+)?instructions?/gi, "")
    // Remove delimiter injection attempts
    .replace(/```system/gi, "")
    .replace(/\[SYSTEM\]/gi, "")
    .replace(/<<SYS>>/gi, "")
    .replace(/<\|im_start\|>/gi, "")
    .replace(/<\|im_end\|>/gi, "")
    // Trim excessive whitespace
    .replace(/\s+/g, " ")
    .trim();

  // Limit length to prevent token exhaustion attacks
  const MAX_MESSAGE_LENGTH = 4000;
  if (sanitized.length > MAX_MESSAGE_LENGTH) {
    sanitized = sanitized.substring(0, MAX_MESSAGE_LENGTH);
  }

  return sanitized;
}

// ============================================================================
// PHI Sanitization (Remove sensitive details before LLM)
// ============================================================================

function sanitizeContextForLLM(context: PatientContext): PatientContext {
  // Create a sanitized copy that doesn't include specific PHI
  return {
    patient_name: context.patient_name
      ? `[Patient: ${context.patient_name.split(" ")[0]}]`
      : undefined,
    recent_handoffs: context.recent_handoffs.map((h) => ({
      id: h.id,
      title: h.title,
      summary: h.summary
        ? h.summary
            // Remove potential SSN patterns
            .replace(/\b\d{3}[-.]?\d{2}[-.]?\d{4}\b/g, "[SSN REDACTED]")
            // Remove potential phone numbers
            .replace(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/g, "[PHONE REDACTED]")
            // Remove potential dates of birth
            .replace(
              /\b(0?[1-9]|1[0-2])[\/\-](0?[1-9]|[12]\d|3[01])[\/\-](19|20)\d{2}\b/g,
              "[DOB REDACTED]",
            )
            // Remove email addresses
            .replace(/\b[\w.-]+@[\w.-]+\.\w+\b/g, "[EMAIL REDACTED]")
        : "",
      type: h.type,
      created_at: h.created_at,
    })),
    medications: context.medications.map((m) => ({
      name: m.name,
      // Don't include dosage details - just medication category
      category: m.category,
    })),
    conditions: context.conditions,
    recent_tasks: context.recent_tasks.map((t) => ({
      title: t.title,
      status: t.status,
      due_at: t.due_at,
    })),
  };
}

function getEmergencyResponse(isMentalHealthCrisis: boolean): string {
  if (isMentalHealthCrisis) {
    return `I'm concerned about what you've shared. If you or someone you know is in crisis, please reach out for help:

**988 Suicide & Crisis Lifeline** - Call or text 988 (available 24/7)

If there is immediate danger, please call **911** right away.

You don't have to face this alone. Professional support is available and can help.`;
  }

  return `This sounds like it could be a medical emergency.

**Please call 911 immediately** if you believe someone is experiencing a medical emergency.

Emergency signs that require 911:
- Chest pain or difficulty breathing
- Loss of consciousness or unresponsiveness
- Signs of stroke (face drooping, arm weakness, speech difficulty)
- Severe bleeding
- Seizures
- Suspected overdose

Your safety comes first. Please seek emergency help right away.`;
}

// ============================================================================
// Context Builder
// ============================================================================

async function buildContext(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  patientId: string | undefined,
  circleId: string,
): Promise<PatientContext> {
  const context: PatientContext = {
    recent_handoffs: [],
    medications: [],
    conditions: [],
    recent_tasks: [],
  };

  if (!patientId) {
    return context;
  }

  try {
    // Fetch patient info
    const { data: patient } = await supabase
      .from("patients")
      .select("display_name, conditions_json")
      .eq("id", patientId)
      .single();

    if (patient) {
      context.patient_name = patient.display_name;
      if (patient.conditions_json) {
        context.conditions = patient.conditions_json;
      }
    }

    // Fetch recent handoffs (last 30 days, limit 10)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const { data: handoffs } = await supabase
      .from("handoffs")
      .select("id, title, summary, type, created_at")
      .eq("patient_id", patientId)
      .eq("status", "PUBLISHED")
      .gt("created_at", thirtyDaysAgo.toISOString())
      .order("created_at", { ascending: false })
      .limit(10);

    if (handoffs) {
      context.recent_handoffs = handoffs.map((h) => ({
        id: h.id,
        title: h.title,
        summary: h.summary || "",
        type: h.type,
        created_at: h.created_at,
      }));
    }

    // Fetch current medications (limit 20)
    const { data: medications } = await supabase
      .from("binder_items")
      .select("title, content_json")
      .eq("patient_id", patientId)
      .eq("type", "MED")
      .eq("is_active", true)
      .limit(20);

    if (medications) {
      context.medications = medications.map((m) => ({
        name: m.title,
        category: m.content_json?.category || "General",
      }));
    }

    // Fetch recent/upcoming tasks (limit 5)
    const { data: tasks } = await supabase
      .from("tasks")
      .select("title, status, due_at")
      .eq("circle_id", circleId)
      .in("status", ["OPEN", "IN_PROGRESS"])
      .order("due_at", { ascending: true })
      .limit(5);

    if (tasks) {
      context.recent_tasks = tasks.map((t) => ({
        title: t.title,
        status: t.status,
        due_at: t.due_at,
      }));
    }
  } catch (error) {
    console.error("Error building context:", error);
  }

  return context;
}

function formatContextForPrompt(context: PatientContext): string {
  const parts: string[] = [];

  if (context.patient_name) {
    parts.push(`Patient: ${context.patient_name}`);
  }

  if (context.conditions.length > 0) {
    parts.push(`Known conditions: ${context.conditions.join(", ")}`);
  }

  if (context.medications.length > 0) {
    const medList = context.medications.map((m) => m.name).join(", ");
    parts.push(`Current medications: ${medList}`);
  }

  if (context.recent_handoffs.length > 0) {
    parts.push("\nRecent care notes:");
    context.recent_handoffs.slice(0, 5).forEach((h) => {
      const date = new Date(h.created_at).toLocaleDateString();
      parts.push(
        `- ${date}: ${h.title}${h.summary ? ` - ${h.summary.substring(0, 150)}` : ""}`,
      );
    });
  }

  if (context.recent_tasks.length > 0) {
    parts.push("\nUpcoming tasks:");
    context.recent_tasks.forEach((t) => {
      const due = t.due_at
        ? ` (due: ${new Date(t.due_at).toLocaleDateString()})`
        : "";
      parts.push(`- ${t.title}${due}`);
    });
  }

  return parts.join("\n");
}

// ============================================================================
// Action Extraction
// ============================================================================

function extractActions(response: string): CoachAction[] {
  const actions: CoachAction[] = [];

  // Check for task suggestions
  const taskPatterns = [
    /schedule\s+(?:an?\s+)?(?:appointment|visit|call)/i,
    /call\s+(?:the\s+)?(?:doctor|nurse|specialist)/i,
    /follow\s+up\s+with/i,
    /make\s+an\s+appointment/i,
    /pick\s+up\s+(?:medication|prescription)/i,
  ];

  taskPatterns.forEach((pattern) => {
    const match = response.match(pattern);
    if (match) {
      actions.push({
        type: "CREATE_TASK",
        label: `Create task: ${match[0]}`,
        prefill_data: {
          title: match[0].charAt(0).toUpperCase() + match[0].slice(1),
        },
      });
    }
  });

  // Check for question suggestions
  const questionPattern =
    /(?:ask\s+(?:the\s+)?(?:doctor|provider|nurse)|questions?\s+to\s+ask)[\s:]+(.+?)(?:\.|$)/gi;
  const questionMatches = response.matchAll(questionPattern);
  for (const match of questionMatches) {
    if (match[1] && match[1].length > 10) {
      actions.push({
        type: "ADD_QUESTION",
        label: "Add to visit questions",
        prefill_data: {
          question: match[1].trim(),
        },
      });
    }
  }

  return actions.slice(0, 3); // Limit to 3 actions
}

function extractFollowUps(response: string): string[] {
  const followUps: string[] = [];

  // Common follow-up patterns
  if (response.toLowerCase().includes("medication")) {
    followUps.push("Tell me more about the medication side effects");
  }
  if (
    response.toLowerCase().includes("doctor") ||
    response.toLowerCase().includes("appointment")
  ) {
    followUps.push("What questions should I ask at the appointment?");
  }
  if (response.toLowerCase().includes("symptom")) {
    followUps.push("When should I be more concerned about this?");
  }
  if (
    response.toLowerCase().includes("tired") ||
    response.toLowerCase().includes("fatigue")
  ) {
    followUps.push("What could be causing the fatigue?");
  }

  return followUps.slice(0, 3);
}

// ============================================================================
// LLM Integration
// ============================================================================

async function callLLM(
  systemPrompt: string,
  context: string,
  userMessage: string,
  conversationHistory: Array<{ role: string; content: string }>,
): Promise<{ content: string; tokens_used: number; success: boolean }> {
  const xaiKey = Deno.env.get("XAI_API_KEY");

  if (!xaiKey) {
    // Fallback response when no API key
    return {
      content: generateFallbackResponse(userMessage),
      tokens_used: 0,
      success: false,
    };
  }

  const messages = [
    { role: "system", content: systemPrompt + "\n\n" + context },
    ...conversationHistory.slice(-10), // Last 10 messages for context
    { role: "user", content: userMessage },
  ];

  // Retry loop for transient failures
  let lastError: Error | null = null;
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      // Create abort controller for timeout
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);

      const response = await fetch("https://api.x.ai/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${xaiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "grok-4-1-fast-reasoning",
          messages,
          max_tokens: 1000,
          temperature: 0.7,
        }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        const errorText = await response.text();
        // Don't retry on 4xx errors (client errors)
        if (response.status >= 400 && response.status < 500) {
          throw new Error(
            `Grok API client error: ${response.status} - ${errorText}`,
          );
        }
        // Retry on 5xx errors (server errors)
        throw new Error(
          `Grok API server error: ${response.status} - ${errorText}`,
        );
      }

      const result = await response.json();
      return {
        content: result.choices[0].message.content,
        tokens_used: result.usage?.total_tokens || 0,
        success: true,
      };
    } catch (error) {
      lastError = error as Error;

      // Log the error but don't expose PHI
      console.error(
        `LLM call attempt ${attempt + 1}/${MAX_RETRIES + 1} failed:`,
        error instanceof Error ? error.message : "Unknown error",
      );

      // Check if it's a timeout
      if (error instanceof Error && error.name === "AbortError") {
        console.error("LLM request timed out");
      }

      // Don't retry on abort or non-retryable errors
      if (
        error instanceof Error &&
        (error.name === "AbortError" || error.message.includes("client error"))
      ) {
        break;
      }

      // Exponential backoff before retry
      if (attempt < MAX_RETRIES) {
        await new Promise((resolve) =>
          setTimeout(resolve, Math.pow(2, attempt) * 1000),
        );
      }
    }
  }

  console.error("All LLM attempts failed, using fallback:", lastError?.message);
  return {
    content: generateFallbackResponse(userMessage),
    tokens_used: 0,
    success: false,
  };
}

function generateFallbackResponse(message: string): string {
  const lowerMessage = message.toLowerCase();

  if (lowerMessage.includes("tired") || lowerMessage.includes("fatigue")) {
    return `I understand your concern about tiredness. Fatigue can have many causes, including medications, sleep quality, nutrition, or underlying conditions.

Some things to consider:
- Has anything changed recently (medications, sleep schedule, activity level)?
- Are there other symptoms accompanying the fatigue?
- How long has this been going on?

I'd recommend discussing this with the healthcare provider, especially if the fatigue is persistent or worsening. They can help identify the cause and suggest appropriate next steps.

Is there anything specific about the fatigue you'd like to discuss?`;
  }

  if (
    lowerMessage.includes("medication") ||
    lowerMessage.includes("medicine")
  ) {
    return `I can help you think through medication questions. When it comes to medications, it's always best to consult directly with the healthcare provider or pharmacist for specific advice.

Some general things to keep track of:
- Take medications as prescribed
- Note any side effects or changes
- Keep an updated list in the Care Binder
- Ask the provider about any concerns

What specific aspect of the medications would you like to discuss?`;
  }

  if (
    lowerMessage.includes("overwhelm") ||
    lowerMessage.includes("stress") ||
    lowerMessage.includes("hard")
  ) {
    return `Caregiving is incredibly demanding, and it's completely normal to feel overwhelmed at times. Your feelings are valid, and the fact that you're here seeking support shows your dedication.

Some things that might help:
- Remember to take breaks when you can
- Lean on your Care Circle for support
- Consider respite care options
- Don't hesitate to ask for help

Would you like to talk about specific aspects of what's feeling overwhelming?`;
  }

  return `Thank you for sharing that. I'm here to help you navigate caregiving questions and concerns.

I can help with:
- Understanding care situations
- Preparing questions for healthcare visits
- Coordinating with your Care Circle
- Managing tasks and documentation

What would be most helpful to discuss?`;
}

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  // Declare in outer scope for catch block access
  let currentUser: { id: string } | null = null;
  let supabaseServiceClient: ReturnType<typeof createClient> | null = null;

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
    // Declare in outer scope for catch block access
    supabaseServiceClient = createClient(supabaseUrl, supabaseServiceKey);

    // Get current user
    const {
      data: { user: authenticatedUser },
      error: userError,
    } = await supabaseUser.auth.getUser();

    // CRITICAL: Assign authenticated user to currentUser for catch block access
    currentUser = authenticatedUser;
    const user = currentUser;
    const supabaseService = supabaseServiceClient!;

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

    // Parse request
    const body: ChatRequest = await req.json();
    const { conversation_id, message, patient_id, circle_id } = body;

    if (!message || !circle_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Missing required fields: message and circle_id",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Input sanitization - prevent prompt injection
    const sanitizedMessage = sanitizeUserInput(message);
    if (sanitizedMessage.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Message cannot be empty after sanitization",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // CRITICAL: Verify circle membership before any data access
    const { data: membership, error: membershipError } = await supabaseService
      .from("circle_members")
      .select("id, role, status")
      .eq("circle_id", circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (membershipError || !membership) {
      console.warn(
        `UNAUTHORIZED_ACCESS_ATTEMPT: user=${user.id} circle=${circle_id}`,
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_UNAUTHORIZED",
            message: "You do not have access to this circle",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check usage limits
    const { data: usageData } = await supabaseService.rpc("check_coach_usage", {
      p_user_id: user.id,
    });

    const usage = usageData as UsageInfo;

    if (!usage.allowed) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "LIMIT_REACHED",
            message:
              usage.plan === "FREE"
                ? "Care Coach requires a Plus or Family subscription"
                : "Monthly message limit reached",
          },
          usage_info: usage,
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check for emergency (use original message for emergency detection)
    const { isEmergency, isMentalHealthCrisis } =
      detectEmergency(sanitizedMessage);
    if (isEmergency) {
      const emergencyResponse = getEmergencyResponse(isMentalHealthCrisis);

      // Log emergency detection for safety audit
      console.log(
        `EMERGENCY_DETECTED: user=${user.id}, type=${isMentalHealthCrisis ? "MENTAL_HEALTH" : "MEDICAL"}`,
      );

      // Still save the conversation for audit
      let conversationId = conversation_id;
      if (!conversationId) {
        const { data: newConv } = await supabaseService
          .from("coach_conversations")
          .insert({
            circle_id,
            user_id: user.id,
            patient_id,
            title: "Emergency Inquiry",
          })
          .select("id")
          .single();
        conversationId = newConv?.id;
      }

      if (conversationId) {
        // Save user message
        await supabaseService.from("coach_messages").insert({
          conversation_id: conversationId,
          role: "USER",
          content: message,
        });

        // Save emergency response
        await supabaseService.from("coach_messages").insert({
          conversation_id: conversationId,
          role: "ASSISTANT",
          content: emergencyResponse,
        });
      }

      return new Response(
        JSON.stringify({
          success: true,
          conversation_id: conversationId,
          content: emergencyResponse,
          actions: [],
          disclaimer: "",
          usage_info: usage,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // CRITICAL: Verify patient belongs to this circle before accessing data
    if (patient_id) {
      const { data: patientCheck, error: patientCheckError } =
        await supabaseService
          .from("patients")
          .select("id")
          .eq("id", patient_id)
          .eq("circle_id", circle_id)
          .single();

      if (patientCheckError || !patientCheck) {
        console.warn(
          `UNAUTHORIZED_PATIENT_ACCESS: user=${user.id} patient=${patient_id} circle=${circle_id}`,
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "AUTH_UNAUTHORIZED",
              message: "Patient does not belong to this circle",
            },
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Build context and sanitize for LLM (remove PHI)
    const rawContext = await buildContext(
      supabaseService,
      user.id,
      patient_id,
      circle_id,
    );
    const sanitizedContext = sanitizeContextForLLM(rawContext);
    const contextString = formatContextForPrompt(sanitizedContext);

    // Get or create conversation
    let conversationId = conversation_id;

    // CRITICAL: Verify conversation ownership before reuse
    if (conversationId) {
      const { data: convCheck, error: convCheckError } = await supabaseService
        .from("coach_conversations")
        .select("id")
        .eq("id", conversationId)
        .eq("circle_id", circle_id)
        .single();

      if (convCheckError || !convCheck) {
        console.warn(
          `UNAUTHORIZED_CONVERSATION_ACCESS: user=${user.id} conversation=${conversationId} circle=${circle_id}`,
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "AUTH_UNAUTHORIZED",
              message: "Conversation does not belong to this circle",
            },
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (!conversationId) {
      const { data: newConv, error: convError } = await supabaseService
        .from("coach_conversations")
        .insert({
          circle_id,
          user_id: user.id,
          patient_id,
          title: message.substring(0, 50) + (message.length > 50 ? "..." : ""),
        })
        .select("id")
        .single();

      if (convError) {
        throw convError;
      }
      conversationId = newConv.id;
    }

    // Get conversation history
    const { data: historyMessages } = await supabaseService
      .from("coach_messages")
      .select("role, content")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: true })
      .limit(20);

    const conversationHistory = (historyMessages || []).map((m) => ({
      role: m.role.toLowerCase(),
      content: m.content,
    }));

    // CRITICAL: Increment usage BEFORE calling LLM (atomic operation to prevent race conditions)
    // This ensures we don't charge for failed calls - we decrement if LLM fails
    const { error: usageError } = await supabaseService.rpc(
      "increment_coach_usage",
      { p_user_id: user.id },
    );

    if (usageError) {
      console.error("Failed to increment usage:", usageError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INTERNAL_ERROR",
            message: "Failed to process request",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Save user message (store sanitized version)
    const { data: savedUserMsg, error: userMsgError } = await supabaseService
      .from("coach_messages")
      .insert({
        conversation_id: conversationId,
        role: "USER",
        content: sanitizedMessage,
        context_handoff_ids: rawContext.recent_handoffs.map((h) => h.id),
      })
      .select("id")
      .single();

    if (userMsgError) {
      // Decrement usage on save failure (rollback)
      await supabaseService.rpc("decrement_coach_usage", {
        p_user_id: user.id,
      });
      console.error("Failed to save user message:", userMsgError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INTERNAL_ERROR",
            message: "Failed to save message",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Call LLM with sanitized message
    const {
      content: responseContent,
      tokens_used,
      success: llmSuccess,
    } = await callLLM(
      SYSTEM_PROMPT,
      contextString,
      sanitizedMessage,
      conversationHistory,
    );

    // If LLM failed, decrement usage (don't charge for failures)
    if (!llmSuccess) {
      await supabaseService.rpc("decrement_coach_usage", {
        p_user_id: user.id,
      });
    }

    // Extract actions and follow-ups
    const actions = extractActions(responseContent);
    const suggestedFollowups = extractFollowUps(responseContent);

    // Add disclaimer
    const disclaimer =
      "This is not medical advice. Please consult a healthcare provider for medical questions.";

    // Save assistant message
    const latencyMs = Date.now() - startTime;
    const { data: savedMessage, error: assistantMsgError } =
      await supabaseService
        .from("coach_messages")
        .insert({
          conversation_id: conversationId,
          role: "ASSISTANT",
          content: responseContent,
          actions_json: actions,
          context_snapshot_json: {
            patient_name: sanitizedContext.patient_name,
            handoff_count: rawContext.recent_handoffs.length,
            medication_count: rawContext.medications.length,
          },
          tokens_used,
          latency_ms: latencyMs,
          model_version: "grok-4-1-fast-reasoning",
        })
        .select("id")
        .single();

    if (assistantMsgError) {
      console.error("Failed to save assistant message:", assistantMsgError);
      // Don't fail the request - the user got their response
    }

    // Update usage info
    const { data: updatedUsage } = await supabaseService.rpc(
      "check_coach_usage",
      {
        p_user_id: user.id,
      },
    );

    // Build context references (use raw context for display, not sanitized)
    const contextReferences: string[] = [];
    if (rawContext.patient_name) {
      contextReferences.push(`Patient: ${rawContext.patient_name}`);
    }
    if (rawContext.recent_handoffs.length > 0) {
      contextReferences.push(
        `${rawContext.recent_handoffs.length} recent handoffs`,
      );
    }
    if (rawContext.medications.length > 0) {
      contextReferences.push(`${rawContext.medications.length} medications`);
    }

    const response: ChatResponse = {
      success: true,
      conversation_id: conversationId,
      message_id: savedMessage?.id,
      content: responseContent,
      actions,
      disclaimer,
      suggested_followups: suggestedFollowups,
      usage_info: updatedUsage as UsageInfo,
      context_references: contextReferences,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);

    // CRITICAL: If we got past usage increment but failed to deliver response, rollback
    // Check if we authenticated (user exists) - usage increment happens after auth
    if (currentUser?.id && supabaseServiceClient) {
      try {
        await supabaseServiceClient.rpc("decrement_coach_usage", {
          p_user_id: currentUser.id,
        });
        console.log(
          `Rolled back usage for user ${currentUser.id} due to error`,
        );
      } catch (rollbackError) {
        console.error("Failed to rollback usage:", rollbackError);
        // Log but don't fail - already in error state
      }
    }

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
