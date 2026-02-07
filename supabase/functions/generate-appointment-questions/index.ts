import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Constants for input validation
const RANGE_DAYS_MAX = 90;
const MAX_QUESTIONS_MAX = 20;
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ============================================================================
// Types
// ============================================================================

interface GenerateQuestionsRequest {
  patient_id: string;
  circle_id: string;
  appointment_pack_id?: string;
  appointment_date?: string;
  range_days?: number;
  max_questions?: number;
}

interface GeneratedQuestion {
  id: string;
  question_text: string;
  reasoning: string;
  category: QuestionCategory;
  source: "AI_GENERATED" | "TEMPLATE";
  source_handoff_ids: string[];
  source_medication_ids: string[];
  priority: "HIGH" | "MEDIUM" | "LOW";
  priority_score: number;
}

type QuestionCategory =
  | "SYMPTOM"
  | "MEDICATION"
  | "TEST"
  | "CARE_PLAN"
  | "PROGNOSIS"
  | "SIDE_EFFECT"
  | "GENERAL";

interface PatternAnalysis {
  repeated_symptoms: Array<{
    symptom: string;
    count: number;
    last_mentioned: string;
  }>;
  medication_changes: Array<{
    medication_id: string;
    medication_name: string;
    change_type: "NEW" | "DOSE_CHANGED" | "STOPPED";
    changed_at: string;
  }>;
  potential_side_effects: Array<{
    medication_id: string;
    medication_name: string;
    symptom: string;
    correlation_score: number;
  }>;
}

interface GenerateQuestionsResponse {
  success: true;
  questions: GeneratedQuestion[];
  analysis_context: {
    handoffs_analyzed: number;
    date_range: { start: string; end: string };
    patterns_detected: PatternAnalysis;
    template_questions_added: number;
  };
  subscription_status: {
    plan: "FREE" | "PLUS" | "FAMILY";
    has_access: boolean;
    preview_only: boolean;
  };
}

interface ErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
  };
}

interface QuestionTemplate {
  id: string;
  category: QuestionCategory;
  trigger_type: string;
  template_text: string;
  template_variables: string[];
  priority_default: "HIGH" | "MEDIUM" | "LOW";
  min_confidence_score: number;
}

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Auth check
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse(
        401,
        "AUTH_INVALID_TOKEN",
        "No authorization header",
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
      return errorResponse(401, "AUTH_INVALID_TOKEN", "Invalid token");
    }

    // Parse JSON with error handling
    let body: GenerateQuestionsRequest;
    try {
      body = await req.json();
    } catch (parseError) {
      return errorResponse(
        400,
        "INVALID_JSON",
        "Request body must be valid JSON",
      );
    }

    const {
      patient_id,
      circle_id,
      appointment_pack_id,
      range_days: rawRangeDays = 30,
      max_questions: rawMaxQuestions = 10,
    } = body;

    // Validate required fields
    if (!patient_id || !circle_id) {
      return errorResponse(
        400,
        "VALIDATION_ERROR",
        "Missing patient_id or circle_id",
      );
    }

    // Validate UUID formats
    if (!isValidUUID(patient_id)) {
      return errorResponse(
        400,
        "VALIDATION_ERROR",
        "Invalid patient_id format",
      );
    }
    if (!isValidUUID(circle_id)) {
      return errorResponse(400, "VALIDATION_ERROR", "Invalid circle_id format");
    }
    if (appointment_pack_id && !isValidUUID(appointment_pack_id)) {
      return errorResponse(
        400,
        "VALIDATION_ERROR",
        "Invalid appointment_pack_id format",
      );
    }

    // Clamp and validate range_days and max_questions
    const range_days = Math.max(1, Math.min(rawRangeDays, RANGE_DAYS_MAX));
    const max_questions = Math.max(
      1,
      Math.min(rawMaxQuestions, MAX_QUESTIONS_MAX),
    );

    // CRITICAL: Verify patient belongs to circle
    const { data: patient, error: patientError } = await supabaseService
      .from("patients")
      .select("id, circle_id")
      .eq("id", patient_id)
      .single();

    if (patientError || !patient) {
      return errorResponse(404, "PATIENT_NOT_FOUND", "Patient not found");
    }

    if (patient.circle_id !== circle_id) {
      return errorResponse(
        403,
        "AUTH_INVALID_PATIENT",
        "Patient does not belong to this circle",
      );
    }

    // Check circle membership
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership) {
      return errorResponse(
        403,
        "AUTH_ROLE_FORBIDDEN",
        "Not a member of this circle",
      );
    }

    // Check subscription
    const { data: subscriptionData } = await supabaseService.rpc(
      "has_feature_access",
      { p_user_id: user.id, p_feature: "appointment_questions" },
    );

    const { data: planData } = await supabaseService.rpc("get_user_plan", {
      p_user_id: user.id,
    });

    const plan = (planData as string) || "FREE";
    const hasAccess = subscriptionData === true;

    // FREE tier: return preview with 2 sample questions
    if (!hasAccess) {
      const previewQuestions = await generatePreviewQuestions(
        supabaseService,
        patient_id,
      );
      return successResponse({
        success: true,
        questions: previewQuestions,
        analysis_context: {
          handoffs_analyzed: 0,
          date_range: { start: "", end: "" },
          patterns_detected: {
            repeated_symptoms: [],
            medication_changes: [],
            potential_side_effects: [],
          },
          template_questions_added: 2,
        },
        subscription_status: {
          plan: plan as "FREE" | "PLUS" | "FAMILY",
          has_access: false,
          preview_only: true,
        },
      });
    }

    // Calculate date range
    const rangeEnd = new Date();
    const rangeStart = new Date(
      rangeEnd.getTime() - range_days * 24 * 60 * 60 * 1000,
    );

    // Fetch handoffs WITH circle_id filter for defense in depth
    const { data: handoffs, error: handoffsError } = await supabaseService
      .from("handoffs")
      .select("id, title, summary, created_at") // Removed content_json to reduce payload
      .eq("patient_id", patient_id)
      .eq("circle_id", circle_id) // Added circle_id filter
      .eq("status", "PUBLISHED")
      .gte("created_at", rangeStart.toISOString())
      .lte("created_at", rangeEnd.toISOString())
      .order("created_at", { ascending: false })
      .limit(50); // Reduced from 100

    if (handoffsError) {
      console.error("Handoffs query failed", { code: handoffsError.code });
      return errorResponse(500, "DATABASE_ERROR", "Failed to fetch handoffs");
    }

    // Fetch medications with circle_id filter
    const { data: medications, error: medsError } = await supabaseService
      .from("binder_items")
      .select("id, title, content_json, created_at, updated_at")
      .eq("patient_id", patient_id)
      .eq("circle_id", circle_id) // Added circle_id filter
      .eq("type", "MED")
      .eq("is_active", true);

    if (medsError) {
      console.error("Medications query failed", { code: medsError.code });
    }

    // Check for insufficient data
    if (
      (!handoffs || handoffs.length < 3) &&
      (!medications || medications.length === 0)
    ) {
      // Return template questions only
      const templates = await fetchActiveTemplates(supabaseService);
      const baselineQuestions = templates
        .filter((t) => t.trigger_type === "BASELINE")
        .slice(0, max_questions)
        .map((t, idx) => templateToQuestion(t, idx, []));

      return successResponse({
        success: true,
        questions: baselineQuestions,
        analysis_context: {
          handoffs_analyzed: handoffs?.length || 0,
          date_range: {
            start: rangeStart.toISOString(),
            end: rangeEnd.toISOString(),
          },
          patterns_detected: {
            repeated_symptoms: [],
            medication_changes: [],
            potential_side_effects: [],
          },
          template_questions_added: baselineQuestions.length,
        },
        subscription_status: {
          plan: plan as "FREE" | "PLUS" | "FAMILY",
          has_access: true,
          preview_only: false,
        },
      });
    }

    // Pattern analysis
    const patterns = analyzePatterns(
      handoffs || [],
      medications || [],
      rangeStart,
    );

    // Fetch templates
    const templates = await fetchActiveTemplates(supabaseService);

    // Generate questions from patterns and templates
    const questions = generateQuestionsFromPatterns(
      patterns,
      templates,
      handoffs || [],
      medications || [],
      max_questions,
    );

    // Try LLM enhancement if configured
    const llmApiKey =
      Deno.env.get("OPENAI_API_KEY") || Deno.env.get("LLM_API_KEY");
    if (llmApiKey && handoffs && handoffs.length >= 3) {
      try {
        const enhancedQuestions = await enhanceWithLLM(
          llmApiKey,
          handoffs,
          medications || [],
          patterns,
          questions,
          max_questions,
        );
        if (enhancedQuestions.length > 0) {
          // Merge AI questions with template questions
          const aiQuestionIds = new Set(enhancedQuestions.map((q) => q.id));
          const nonDuplicateTemplates = questions.filter(
            (q) => !aiQuestionIds.has(q.id),
          );
          questions.length = 0;
          questions.push(...enhancedQuestions, ...nonDuplicateTemplates);
        }
      } catch (llmError) {
        console.error(
          "LLM enhancement failed, using template questions:",
          llmError,
        );
        // Continue with template questions
      }
    }

    // Sort by priority score and limit
    questions.sort((a, b) => b.priority_score - a.priority_score);
    const finalQuestions = questions.slice(0, max_questions);

    // Save questions to database
    if (finalQuestions.length > 0) {
      const questionsToInsert = finalQuestions.map((q, idx) => ({
        id: q.id,
        circle_id,
        patient_id,
        appointment_pack_id: appointment_pack_id || null,
        question_text: q.question_text,
        reasoning: q.reasoning,
        category: q.category,
        source: q.source,
        source_handoff_ids: q.source_handoff_ids,
        source_medication_ids: q.source_medication_ids,
        created_by: user.id,
        priority: q.priority,
        priority_score: q.priority_score,
        status: "PENDING",
        sort_order: idx,
      }));

      const { error: insertError } = await supabaseService
        .from("appointment_questions")
        .insert(questionsToInsert);

      if (insertError) {
        console.error("Failed to save questions:", insertError);
        // Continue anyway, questions are returned to client
      }
    }

    // Add audit logging after successful generation
    if (finalQuestions.length > 0) {
      await supabaseService
        .from("audit_events")
        .insert({
          event_type: "APPOINTMENT_QUESTIONS_GENERATED",
          user_id: user.id,
          circle_id: circle_id,
          patient_id: patient_id,
          action: "GENERATE",
          metadata: {
            question_count: finalQuestions.length,
            handoff_count: handoffs?.length || 0,
            ai_enhanced: llmApiKey ? true : false,
          },
          created_at: new Date().toISOString(),
        })
        .catch((err) => {
          console.error("Audit logging failed", { code: err?.code });
        });
    }

    return successResponse({
      success: true,
      questions: finalQuestions,
      analysis_context: {
        handoffs_analyzed: handoffs?.length || 0,
        date_range: {
          start: rangeStart.toISOString(),
          end: rangeEnd.toISOString(),
        },
        patterns_detected: patterns,
        template_questions_added: questions.filter(
          (q) => q.source === "TEMPLATE",
        ).length,
      },
      subscription_status: {
        plan: plan as "FREE" | "PLUS" | "FAMILY",
        has_access: true,
        preview_only: false,
      },
    });
  } catch (error) {
    console.error("Error:", error);
    return errorResponse(500, "INTERNAL_ERROR", "Internal server error");
  }
});

// ============================================================================
// Helper Functions
// ============================================================================

function errorResponse(
  status: number,
  code: string,
  message: string,
): Response {
  const body: ErrorResponse = {
    success: false,
    error: { code, message },
  };
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function successResponse(data: GenerateQuestionsResponse): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function fetchActiveTemplates(
  supabase: ReturnType<typeof createClient>,
): Promise<QuestionTemplate[]> {
  const { data, error } = await supabase
    .from("question_templates")
    .select("*")
    .eq("is_active", true);

  if (error) {
    console.error("Failed to fetch templates:", error);
    return [];
  }

  return data || [];
}

async function generatePreviewQuestions(
  supabase: ReturnType<typeof createClient>,
  _patientId: string,
): Promise<GeneratedQuestion[]> {
  const templates = await fetchActiveTemplates(supabase);
  const baselineTemplates = templates.filter(
    (t) => t.trigger_type === "BASELINE",
  );

  return baselineTemplates.slice(0, 2).map((t, idx) => ({
    id: crypto.randomUUID(),
    question_text: t.template_text,
    reasoning: "Sample question - Upgrade to Plus for personalized questions",
    category: t.category as QuestionCategory,
    source: "TEMPLATE" as const,
    source_handoff_ids: [],
    source_medication_ids: [],
    priority: t.priority_default,
    priority_score: 3,
  }));
}

function analyzePatterns(
  handoffs: Array<{
    id: string;
    title: string;
    summary: string;
    content_json: unknown;
    created_at: string;
  }>,
  medications: Array<{
    id: string;
    title: string;
    content_json: unknown;
    created_at: string;
    updated_at: string;
  }>,
  rangeStart: Date,
): PatternAnalysis {
  const symptomMentions = new Map<
    string,
    { count: number; dates: string[]; handoffIds: string[] }
  >();
  const medicationChanges: PatternAnalysis["medication_changes"] = [];
  const potentialSideEffects: PatternAnalysis["potential_side_effects"] = [];

  // Common symptoms to detect
  const symptomPatterns = [
    "dizzy",
    "dizziness",
    "dizzy spells",
    "tired",
    "fatigue",
    "exhausted",
    "exhaustion",
    "pain",
    "ache",
    "aching",
    "sore",
    "soreness",
    "nausea",
    "nauseous",
    "sick",
    "headache",
    "head ache",
    "confusion",
    "confused",
    "disoriented",
    "anxiety",
    "anxious",
    "worried",
    "shortness of breath",
    "breathing difficulty",
    "breathless",
    "cough",
    "coughing",
    "swelling",
    "swollen",
    "edema",
    "rash",
    "itching",
    "itchy",
    "constipation",
    "constipated",
    "insomnia",
    "sleep problems",
    "can't sleep",
    "trouble sleeping",
    "appetite",
    "not eating",
    "loss of appetite",
    "weakness",
    "weak",
    "feeling weak",
    "fall",
    "fell",
    "falling",
  ];

  // Analyze handoffs for symptom patterns
  for (const handoff of handoffs) {
    const text = `${handoff.title} ${handoff.summary}`.toLowerCase();

    for (const symptom of symptomPatterns) {
      if (text.includes(symptom)) {
        const normalizedSymptom = normalizeSymptom(symptom);
        const existing = symptomMentions.get(normalizedSymptom);
        if (existing) {
          existing.count++;
          existing.dates.push(handoff.created_at);
          if (!existing.handoffIds.includes(handoff.id)) {
            existing.handoffIds.push(handoff.id);
          }
        } else {
          symptomMentions.set(normalizedSymptom, {
            count: 1,
            dates: [handoff.created_at],
            handoffIds: [handoff.id],
          });
        }
      }
    }
  }

  // Detect medication changes (new meds in the last 30 days)
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  for (const med of medications) {
    const createdAt = new Date(med.created_at);
    const updatedAt = new Date(med.updated_at);

    if (createdAt >= rangeStart) {
      medicationChanges.push({
        medication_id: med.id,
        medication_name: med.title,
        change_type: "NEW",
        changed_at: med.created_at,
      });
    } else if (updatedAt >= rangeStart && updatedAt > createdAt) {
      medicationChanges.push({
        medication_id: med.id,
        medication_name: med.title,
        change_type: "DOSE_CHANGED",
        changed_at: med.updated_at,
      });
    }
  }

  // Detect potential side effects (symptom appears after med start)
  for (const medChange of medicationChanges.filter(
    (m) => m.change_type === "NEW",
  )) {
    const medStartDate = new Date(medChange.changed_at);

    for (const [symptom, data] of symptomMentions.entries()) {
      const symptomsAfterMed = data.dates.filter(
        (d) => new Date(d) > medStartDate,
      );
      if (symptomsAfterMed.length >= 2) {
        const correlationScore = Math.min(
          symptomsAfterMed.length / data.dates.length,
          1,
        );
        if (correlationScore >= 0.5) {
          potentialSideEffects.push({
            medication_id: medChange.medication_id,
            medication_name: medChange.medication_name,
            symptom,
            correlation_score: correlationScore,
          });
        }
      }
    }
  }

  // Convert symptom map to array, filter for repeated symptoms (3+)
  const repeatedSymptoms = Array.from(symptomMentions.entries())
    .filter(([_, data]) => data.count >= 3)
    .map(([symptom, data]) => ({
      symptom,
      count: data.count,
      last_mentioned: data.dates[data.dates.length - 1],
    }))
    .sort((a, b) => b.count - a.count);

  return {
    repeated_symptoms: repeatedSymptoms,
    medication_changes: medicationChanges,
    potential_side_effects: potentialSideEffects,
  };
}

function normalizeSymptom(symptom: string): string {
  const normalizations: Record<string, string> = {
    dizzy: "dizziness",
    "dizzy spells": "dizziness",
    tired: "fatigue",
    exhausted: "fatigue",
    exhaustion: "fatigue",
    ache: "pain",
    aching: "pain",
    sore: "pain",
    soreness: "pain",
    nauseous: "nausea",
    sick: "nausea",
    "head ache": "headache",
    confused: "confusion",
    disoriented: "confusion",
    anxious: "anxiety",
    worried: "anxiety",
    "breathing difficulty": "shortness of breath",
    breathless: "shortness of breath",
    coughing: "cough",
    swollen: "swelling",
    edema: "swelling",
    itchy: "rash",
    itching: "rash",
    constipated: "constipation",
    "sleep problems": "insomnia",
    "can't sleep": "insomnia",
    "trouble sleeping": "insomnia",
    "not eating": "loss of appetite",
    weak: "weakness",
    "feeling weak": "weakness",
    fell: "falls",
    fall: "falls",
    falling: "falls",
  };

  return normalizations[symptom] || symptom;
}

function generateQuestionsFromPatterns(
  patterns: PatternAnalysis,
  templates: QuestionTemplate[],
  handoffs: Array<{ id: string }>,
  medications: Array<{ id: string; title: string }>,
  maxQuestions: number,
): GeneratedQuestion[] {
  const questions: GeneratedQuestion[] = [];

  // Generate questions for repeated symptoms
  for (const symptom of patterns.repeated_symptoms.slice(0, 3)) {
    const template = templates.find(
      (t) => t.trigger_type === "SYMPTOM_REPEATED",
    );
    if (template) {
      const questionText = template.template_text
        .replace("{symptom}", symptom.symptom)
        .replace("{count}", symptom.count.toString())
        .replace("{days}", "30");

      const priorityScore = calculatePriorityScore({
        mentionCount: symptom.count,
        lastMentionDays: daysSince(symptom.last_mentioned),
        category: "SYMPTOM",
        correlationScore: null,
      });

      questions.push({
        id: crypto.randomUUID(),
        question_text: questionText,
        reasoning: `${symptom.symptom} was mentioned ${symptom.count} times in recent handoffs`,
        category: "SYMPTOM",
        source: "TEMPLATE",
        source_handoff_ids: handoffs.slice(0, 5).map((h) => h.id),
        source_medication_ids: [],
        priority: categorizePriority(priorityScore),
        priority_score: priorityScore,
      });
    }
  }

  // Generate questions for new medications
  for (const medChange of patterns.medication_changes
    .filter((m) => m.change_type === "NEW")
    .slice(0, 2)) {
    const template = templates.find((t) => t.trigger_type === "MED_NEW");
    if (template) {
      const duration = formatDuration(new Date(medChange.changed_at));
      const questionText = template.template_text
        .replace("{medication}", medChange.medication_name)
        .replace("{duration}", duration);

      const priorityScore = calculatePriorityScore({
        mentionCount: 1,
        lastMentionDays: daysSince(medChange.changed_at),
        category: "MEDICATION",
        correlationScore: null,
      });

      questions.push({
        id: crypto.randomUUID(),
        question_text: questionText,
        reasoning: `${medChange.medication_name} was started ${duration}`,
        category: "MEDICATION",
        source: "TEMPLATE",
        source_handoff_ids: [],
        source_medication_ids: [medChange.medication_id],
        priority: categorizePriority(priorityScore),
        priority_score: priorityScore,
      });
    }
  }

  // Generate questions for potential side effects
  for (const sideEffect of patterns.potential_side_effects.slice(0, 2)) {
    const template = templates.find(
      (t) => t.trigger_type === "MED_SIDE_EFFECT",
    );
    if (template) {
      const questionText = template.template_text
        .replace("{symptom}", sideEffect.symptom)
        .replace("{medication}", sideEffect.medication_name);

      const priorityScore = calculatePriorityScore({
        mentionCount: 2,
        lastMentionDays: 7,
        category: "SIDE_EFFECT",
        correlationScore: sideEffect.correlation_score,
      });

      questions.push({
        id: crypto.randomUUID(),
        question_text: questionText,
        reasoning: `${sideEffect.symptom} appeared after starting ${sideEffect.medication_name} (${Math.round(sideEffect.correlation_score * 100)}% correlation)`,
        category: "SIDE_EFFECT",
        source: "TEMPLATE",
        source_handoff_ids: [],
        source_medication_ids: [sideEffect.medication_id],
        priority: categorizePriority(priorityScore),
        priority_score: priorityScore,
      });
    }
  }

  // Add baseline questions if we have room
  const baselineTemplates = templates.filter(
    (t) => t.trigger_type === "BASELINE",
  );
  const remainingSlots = maxQuestions - questions.length;
  for (const template of baselineTemplates.slice(
    0,
    Math.min(remainingSlots, 3),
  )) {
    questions.push(templateToQuestion(template, questions.length, []));
  }

  return questions;
}

function templateToQuestion(
  template: QuestionTemplate,
  _index: number,
  sourceHandoffIds: string[],
): GeneratedQuestion {
  // Priority scores aligned with iOS QuestionPriority.defaultScore: HIGH=8, MEDIUM=4, LOW=1
  const priorityScore =
    template.priority_default === "HIGH"
      ? 8
      : template.priority_default === "MEDIUM"
        ? 4
        : 1;
  return {
    id: crypto.randomUUID(),
    question_text: template.template_text,
    reasoning: "Standard question for medical appointments",
    category: template.category as QuestionCategory,
    source: "TEMPLATE",
    source_handoff_ids: sourceHandoffIds,
    source_medication_ids: [],
    priority: template.priority_default,
    priority_score: priorityScore,
  };
}

function calculatePriorityScore(context: {
  mentionCount: number;
  lastMentionDays: number;
  category: string;
  correlationScore: number | null;
}): number {
  let score = 0;

  // Recency boost
  if (context.lastMentionDays <= 7) score += 3;
  else if (context.lastMentionDays <= 14) score += 2;
  else if (context.lastMentionDays <= 21) score += 1;

  // Frequency boost (+2 per mention, max +6)
  score += Math.min(context.mentionCount, 3) * 2;

  // Medication safety boost
  if (context.category === "MEDICATION" || context.category === "SIDE_EFFECT") {
    score += 2;
  }

  // Correlation boost
  if (context.correlationScore && context.correlationScore >= 0.7) {
    score += 2;
  }

  return Math.min(score, 10);
}

function categorizePriority(score: number): "HIGH" | "MEDIUM" | "LOW" {
  if (score >= 6) return "HIGH";
  if (score >= 3) return "MEDIUM";
  return "LOW";
}

function daysSince(dateStr: string): number {
  const date = new Date(dateStr);
  const now = new Date();
  return Math.floor((now.getTime() - date.getTime()) / (24 * 60 * 60 * 1000));
}

function formatDuration(startDate: Date): string {
  const days = daysSince(startDate.toISOString());
  if (days < 7) return `${days} day${days === 1 ? "" : "s"} ago`;
  if (days < 30)
    return `${Math.floor(days / 7)} week${Math.floor(days / 7) === 1 ? "" : "s"} ago`;
  return `${Math.floor(days / 30)} month${Math.floor(days / 30) === 1 ? "" : "s"} ago`;
}

// Sanitization helper for LLM prompts
function sanitizeForPrompt(text: string): string {
  return text
    .replace(/SYSTEM:/gi, "[filtered]")
    .replace(/IGNORE\s+PREVIOUS/gi, "[filtered]")
    .replace(/DISREGARD/gi, "[filtered]")
    .replace(/INSTRUCTIONS?:/gi, "[filtered]")
    .substring(0, 200);
}

// UUID validation helper
function isValidUUID(uuid: string): boolean {
  return UUID_REGEX.test(uuid);
}

async function enhanceWithLLM(
  apiKey: string,
  handoffs: Array<{
    id: string;
    title: string;
    summary: string;
    created_at: string;
  }>,
  medications: Array<{ id: string; title: string }>,
  patterns: PatternAnalysis,
  baseQuestions: GeneratedQuestion[],
  maxQuestions: number,
): Promise<GeneratedQuestion[]> {
  // Sanitize handoff data before sending to LLM
  const handoffSummaries = handoffs
    .slice(0, 10)
    .map(
      (h) => `- ${sanitizeForPrompt(h.title)}: ${sanitizeForPrompt(h.summary)}`,
    )
    .join("\n");

  const medList = medications
    .slice(0, 10)
    .map((m) => sanitizeForPrompt(m.title))
    .join(", ");

  const symptomList = patterns.repeated_symptoms
    .slice(0, 5)
    .map((s) => `${sanitizeForPrompt(s.symptom)} (${s.count}x)`)
    .join(", ");

  const systemPrompt = `You are a healthcare assistant helping caregivers prepare questions for medical appointments.
Based on recent care notes and patterns, generate personalized questions to ask the doctor.

IMPORTANT:
- Questions should be specific to the patient's situation
- Focus on actionable topics (symptoms, medications, care plan)
- Prioritize safety concerns (falls, confusion, medication side effects)
- Avoid generic questions if patient-specific ones are available
- Do NOT provide medical advice or diagnoses

Return a JSON array of questions with this structure:
[{
  "question_text": "The question to ask",
  "reasoning": "Why this question is relevant",
  "category": "SYMPTOM|MEDICATION|TEST|CARE_PLAN|PROGNOSIS|SIDE_EFFECT|GENERAL",
  "priority": "HIGH|MEDIUM|LOW"
}]

Maximum ${maxQuestions} questions.`;

  const userPrompt = `Recent care notes (last 30 days):
${handoffSummaries}

Current medications: ${medList || "None listed"}

Patterns detected:
- Repeated symptoms: ${symptomList || "None"}
- New medications: ${
    patterns.medication_changes
      .filter((m) => m.change_type === "NEW")
      .map((m) => m.medication_name)
      .join(", ") || "None"
  }
- Potential side effects: ${patterns.potential_side_effects.map((s) => `${s.symptom} from ${s.medication_name}`).join(", ") || "None"}

Generate personalized questions for the upcoming appointment.`;

  // Add timeout to OpenAI call
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30000);

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.7,
        max_tokens: 800,
      }),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.status}`);
    }

    const result = await response.json();
    const content = result.choices?.[0]?.message?.content;

    if (!content) {
      throw new Error("No content in LLM response");
    }

    // Parse LLM response with robust error handling
    let jsonStr = content.trim();
    const jsonMatch = content.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (jsonMatch) {
      jsonStr = jsonMatch[1].trim();
    }

    let llmQuestions: any[];
    try {
      const parsed = JSON.parse(jsonStr);
      llmQuestions = Array.isArray(parsed) ? parsed : [];
    } catch (parseError) {
      console.error("LLM JSON parsing failed, falling back to templates");
      return [];
    }

    // Validate and filter questions
    return llmQuestions
      .filter(
        (q) =>
          q &&
          typeof q.question_text === "string" &&
          q.question_text.length >= 10 &&
          q.question_text.length <= 500,
      )
      .map((q) => ({
        id: crypto.randomUUID(),
        question_text: String(q.question_text).slice(0, 500),
        reasoning: String(q.reasoning || "AI-generated question").slice(0, 300),
        category: [
          "SYMPTOM",
          "MEDICATION",
          "TEST",
          "CARE_PLAN",
          "PROGNOSIS",
          "SIDE_EFFECT",
          "GENERAL",
        ].includes(q.category)
          ? q.category
          : "GENERAL",
        source: "AI_GENERATED" as const,
        source_handoff_ids: handoffs.slice(0, 5).map((h) => h.id),
        source_medication_ids: medications.slice(0, 3).map((m) => m.id),
        priority: ["HIGH", "MEDIUM", "LOW"].includes(q.priority)
          ? q.priority
          : "MEDIUM",
        priority_score:
          q.priority === "HIGH" ? 8 : q.priority === "MEDIUM" ? 4 : 1,
      }))
      .slice(0, maxQuestions);
  } catch (error) {
    clearTimeout(timeoutId);
    if (error.name === "AbortError") {
      console.error("LLM request timeout");
    } else {
      console.error("LLM enhancement failed", { type: (error as any).name });
    }
    return [];
  }
}
