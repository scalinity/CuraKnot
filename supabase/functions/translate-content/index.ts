import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  getCorsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
} from "../_shared/cors.ts";
import { isValidUUID } from "../_shared/validation.ts";
import { createHash } from "https://deno.land/std@0.168.0/hash/mod.ts";

// ============================================================================
// Types
// ============================================================================

interface TranslateRequest {
  text: string;
  sourceLanguage: string;
  targetLanguage: string;
  circleId?: string;
  contentType: "HANDOFF" | "BINDER" | "TASK" | "NOTIFICATION";
}

interface TranslateResponse {
  translatedText: string;
  confidenceScore: number;
  medicalTermsFound: string[];
  disclaimer: boolean;
}

// Supported language codes
const SUPPORTED_LANGUAGES = ["en", "es", "zh-Hans", "vi", "ko", "tl", "fr"];

// Valid content types
const VALID_CONTENT_TYPES = ["HANDOFF", "BINDER", "TASK", "NOTIFICATION"];

// Maximum text length (50KB - prevents abuse while allowing full handoffs)
const MAX_TEXT_LENGTH = 50_000;

// Maximum OpenAI tokens to request
const MAX_OPENAI_TOKENS = 4096;

// Languages available per tier
const TIER_LANGUAGES: Record<string, string[]> = {
  FREE: ["en"],
  PLUS: ["en", "es"],
  FAMILY: SUPPORTED_LANGUAGES,
};

// Medical disclaimers per language
const MEDICAL_DISCLAIMERS: Record<string, string> = {
  en: "Medication names shown in original language for safety.",
  es: "Los nombres de medicamentos se muestran en su idioma original por seguridad.",
  "zh-Hans": "为安全起见，药物名称以原文显示。",
  vi: "Tên thuốc được hiển thị bằng ngôn ngữ gốc để đảm bảo an toàn.",
  ko: "안전을 위해 약물 이름은 원래 언어로 표시됩니다.",
  tl: "Ang mga pangalan ng gamot ay ipinapakita sa orihinal na wika para sa kaligtasan.",
  fr: "Les noms des médicaments sont affichés dans la langue d'origine par mesure de sécurité.",
};

// Language display names
const LANGUAGE_NAMES: Record<string, string> = {
  en: "English",
  es: "Spanish",
  "zh-Hans": "Chinese (Simplified)",
  vi: "Vietnamese",
  ko: "Korean",
  tl: "Tagalog",
  fr: "French",
};

// Common medication name patterns to protect
const MEDICATION_PATTERNS = [
  // Generic drug name patterns (ending in common suffixes) - case insensitive
  /\b\w{3,}(?:pril|sartan|olol|statin|zosin|dipine|mycin|cillin|cycline|prazole|tidine|fenac|profen|oxacin|azole|vir|mab|nib|tinib|zumab|ximab)\b/gi,
  // Specific common medications - case insensitive
  /\b(?:aspirin|ibuprofen|acetaminophen|metformin|lisinopril|amlodipine|metoprolol|atorvastatin|omeprazole|losartan|levothyroxine|gabapentin|prednisone|warfarin|insulin|morphine|oxycodone|hydrocodone|amoxicillin|azithromycin|ciprofloxacin|tramadol|diazepam|alprazolam|lorazepam|sertraline|fluoxetine|citalopram|escitalopram|duloxetine|venlafaxine|bupropion)\b/gi,
  // Dosage patterns (drug name + dose) - matches "Metformin 500 mg", "metformin 500mg", "METFORMIN 500 MG"
  /\b[A-Za-z]{3,}\s+\d+\s*(?:mg|mcg|ml|g|units?|IU)\b/gi,
];

// ============================================================================
// Helpers
// ============================================================================

function hashText(text: string): string {
  const hash = createHash("sha256");
  hash.update(text);
  return hash.toString();
}

function extractMedicationNames(text: string): string[] {
  const medications = new Set<string>();
  for (const pattern of MEDICATION_PATTERNS) {
    const matches = text.matchAll(new RegExp(pattern.source, pattern.flags));
    for (const match of matches) {
      medications.add(match[0]);
    }
  }
  return Array.from(medications);
}

function protectMedications(
  text: string,
  medications: string[],
): { protectedText: string; placeholders: Map<string, string> } {
  const placeholders = new Map<string, string>();
  let protectedText = text;

  medications.forEach((med, index) => {
    const placeholder = `[[MED_${index}]]`;
    placeholders.set(placeholder, med);
    // Use word boundary replacement to avoid partial matches
    const escaped = med.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    protectedText = protectedText.replace(
      new RegExp(escaped, "gi"),
      placeholder,
    );
  });

  return { protectedText, placeholders };
}

function restoreMedications(
  text: string,
  placeholders: Map<string, string>,
): string {
  let restored = text;
  for (const [placeholder, original] of placeholders) {
    restored = restored.replace(
      new RegExp(placeholder.replace(/[[\]]/g, "\\$&"), "g"),
      original,
    );
  }
  return restored;
}

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // 1. Authenticate
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse("AUTH_MISSING", "Missing Authorization header", 401);
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
      return errorResponse("AUTH_INVALID", "Invalid authorization token", 401);
    }

    // 2. Parse and validate request
    const body: TranslateRequest = await req.json();
    const { text, sourceLanguage, targetLanguage, circleId, contentType } =
      body;

    if (!text || !sourceLanguage || !targetLanguage || !contentType) {
      return errorResponse(
        "INVALID_INPUT",
        "Missing required fields: text, sourceLanguage, targetLanguage, contentType",
        400,
      );
    }

    // Validate text length
    if (typeof text !== "string" || text.length > MAX_TEXT_LENGTH) {
      return errorResponse(
        "INVALID_INPUT",
        `Text exceeds maximum length of ${MAX_TEXT_LENGTH} characters`,
        400,
      );
    }

    if (text.trim().length === 0) {
      return errorResponse("INVALID_INPUT", "Text cannot be empty", 400);
    }

    // Validate content type
    if (!VALID_CONTENT_TYPES.includes(contentType)) {
      return errorResponse("INVALID_INPUT", "Invalid contentType", 400);
    }

    if (!SUPPORTED_LANGUAGES.includes(sourceLanguage)) {
      return errorResponse(
        "UNSUPPORTED_LANGUAGE",
        `Source language '${sourceLanguage}' is not supported`,
        400,
      );
    }

    if (!SUPPORTED_LANGUAGES.includes(targetLanguage)) {
      return errorResponse(
        "UNSUPPORTED_LANGUAGE",
        `Target language '${targetLanguage}' is not supported`,
        400,
      );
    }

    if (sourceLanguage === targetLanguage) {
      return jsonResponse({
        translatedText: text,
        confidenceScore: 1.0,
        medicalTermsFound: [],
        disclaimer: false,
      });
    }

    if (circleId && !isValidUUID(circleId)) {
      return errorResponse("INVALID_INPUT", "Invalid circleId format", 400);
    }

    // 2b. Verify circle membership if circleId provided (IDOR prevention)
    if (circleId) {
      const { data: membership, error: memberError } = await supabaseService
        .from("circle_members")
        .select("id")
        .eq("circle_id", circleId)
        .eq("user_id", user.id)
        .eq("status", "ACTIVE")
        .maybeSingle();

      if (memberError || !membership) {
        return errorResponse(
          "ACCESS_DENIED",
          "You do not have access to this circle",
          403,
        );
      }
    }

    // 3. Check subscription tier
    const { data: subscription } = await supabaseService
      .from("subscriptions")
      .select("plan")
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const userPlan = subscription?.plan || "FREE";
    const allowedLanguages = TIER_LANGUAGES[userPlan] || TIER_LANGUAGES.FREE;

    if (!allowedLanguages.includes(targetLanguage)) {
      return errorResponse(
        "FEATURE_LOCKED",
        `Translation to ${LANGUAGE_NAMES[targetLanguage] || targetLanguage} requires ${targetLanguage === "es" ? "Plus" : "Family"} plan`,
        402,
      );
    }

    // 4. Check translation cache (use delimiter to prevent hash collision)
    const cacheInput = [sourceLanguage, targetLanguage, text].join("\x00");
    const textHash = hashText(cacheInput);

    const { data: cached } = await supabaseService
      .from("translation_cache")
      .select("translated_text, confidence_score, contains_medical_terms")
      .eq("source_text_hash", textHash)
      .eq("source_language", sourceLanguage)
      .eq("target_language", targetLanguage)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();

    if (cached) {
      return jsonResponse({
        translatedText: cached.translated_text,
        confidenceScore: cached.confidence_score || 0.9,
        medicalTermsFound: [],
        disclaimer: cached.contains_medical_terms || false,
      });
    }

    // 5. Extract and protect medication names
    const medications = extractMedicationNames(text);
    const { protectedText, placeholders } = protectMedications(
      text,
      medications,
    );

    // 6. Look up circle glossary terms (circle membership already verified above)
    let glossaryTerms: { source_term: string; translated_term: string }[] = [];
    if (circleId) {
      const { data: glossary } = await supabaseService
        .from("translation_glossary")
        .select("source_term, translated_term")
        .or(`circle_id.eq.${circleId},circle_id.is.null`)
        .eq("source_language", sourceLanguage)
        .eq("target_language", targetLanguage);

      glossaryTerms = glossary || [];
    } else {
      // Get system glossary only
      const { data: glossary } = await supabaseService
        .from("translation_glossary")
        .select("source_term, translated_term")
        .is("circle_id", null)
        .eq("source_language", sourceLanguage)
        .eq("target_language", targetLanguage);

      glossaryTerms = glossary || [];
    }

    // 7. Translate via OpenAI
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      return errorResponse(
        "CONFIG_ERROR",
        "Translation service not configured",
        500,
      );
    }

    const sourceLangName = LANGUAGE_NAMES[sourceLanguage] || sourceLanguage;
    const targetLangName = LANGUAGE_NAMES[targetLanguage] || targetLanguage;

    // Sanitize glossary terms to prevent prompt injection
    // Strip control chars, newlines, quotes, and limit length
    const sanitizeTerm = (term: string): string =>
      term
        .replace(/[\x00-\x1f\x7f]/g, "") // Control characters
        .replace(/[\n\r]/g, " ") // Newlines (prevent multi-line injection)
        .replace(/["'`\\]/g, "") // Quotes and backslash
        .trim()
        .slice(0, 200);

    const glossaryContext =
      glossaryTerms.length > 0
        ? `\n\nUse these specific term translations (glossary overrides):\n${glossaryTerms.map((g) => `- "${sanitizeTerm(g.source_term)}" → "${sanitizeTerm(g.translated_term)}"`).join("\n")}`
        : "";

    const systemPrompt = `You are a medical-context translation assistant. Translate the following text from ${sourceLangName} to ${targetLangName}.

Rules:
1. Preserve all [[MED_N]] placeholders exactly as they appear - do NOT translate them
2. Maintain the original meaning accurately, especially for medical/health context
3. Use natural, fluent ${targetLangName} appropriate for family caregivers
4. Preserve any formatting (line breaks, bullet points, etc.)
5. If unsure about a medical term, keep the original term in parentheses${glossaryContext}

Return ONLY the translated text, nothing else.`;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);

    let translatedText: string;
    let confidenceScore = 0.9;
    const containsMedicalTerms = medications.length > 0;

    // Cap max_tokens to prevent abuse
    const maxTokens = Math.min(
      Math.max(protectedText.length * 3, 1000),
      MAX_OPENAI_TOKENS,
    );

    try {
      const response = await fetch(
        "https://api.openai.com/v1/chat/completions",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${openaiApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "gpt-4o-mini",
            messages: [
              { role: "system", content: systemPrompt },
              { role: "user", content: protectedText },
            ],
            temperature: 0.2,
            max_tokens: maxTokens,
          }),
          signal: controller.signal,
        },
      );

      if (!response.ok) {
        const errStatus = response.status;
        // Log status code only, not response body (may contain sensitive data)
        console.error(`OpenAI API error: status ${errStatus}`);
        return errorResponse(
          "TRANSLATION_FAILED",
          "Translation service error",
          502,
        );
      }

      const result = await response.json();

      // Validate response structure before accessing
      if (!result.choices?.[0]?.message?.content) {
        console.error("OpenAI API returned malformed response structure");
        return errorResponse(
          "TRANSLATION_FAILED",
          "Translation service returned invalid response",
          502,
        );
      }

      translatedText = result.choices[0].message.content.trim();

      // Extract confidence from finish_reason
      if (result.choices[0].finish_reason === "stop") {
        confidenceScore = 0.95;
      }
    } finally {
      clearTimeout(timeout);
    }

    // 8. Restore medication names (untranslated)
    translatedText = restoreMedications(translatedText, placeholders);

    // 9. Apply glossary overrides post-translation
    for (const entry of glossaryTerms) {
      const sourceEscaped = entry.source_term.replace(
        /[.*+?^${}()|[\]\\]/g,
        "\\$&",
      );
      const termPattern = new RegExp(sourceEscaped, "gi");
      if (termPattern.test(text)) {
        // The source term appeared in the original text.
        // Replace any occurrence of the source term that the LLM may have
        // left untranslated or translated differently in the output.
        const targetEscaped = entry.translated_term.replace(
          /[.*+?^${}()|[\]\\]/g,
          "\\$&",
        );
        // Also look for the source term in the translation (LLM may have left it)
        translatedText = translatedText.replace(
          new RegExp(sourceEscaped, "gi"),
          entry.translated_term,
        );
      }
    }

    // 10. Cache the translation (non-fatal, log errors)
    try {
      const { error: cacheError } = await supabaseService
        .from("translation_cache")
        .upsert(
          {
            source_text_hash: textHash,
            source_language: sourceLanguage,
            target_language: targetLanguage,
            translated_text: translatedText,
            confidence_score: confidenceScore,
            contains_medical_terms: containsMedicalTerms,
            created_at: new Date().toISOString(),
            expires_at: new Date(
              Date.now() + 30 * 24 * 60 * 60 * 1000,
            ).toISOString(),
          },
          {
            onConflict: "source_text_hash,source_language,target_language",
          },
        );
      if (cacheError) {
        console.warn("Failed to cache translation:", cacheError.message);
      }
    } catch (cacheErr) {
      console.warn(
        "Cache write exception:",
        cacheErr instanceof Error ? cacheErr.message : "Unknown",
      );
    }

    // 11. Increment usage metrics
    if (circleId) {
      try {
        await supabaseService.rpc("increment_usage", {
          p_user_id: user.id,
          p_circle_id: circleId,
          p_metric_type: "HANDOFF_TRANSLATION",
        });
      } catch {
        // Non-fatal: log but don't fail the request
        console.warn("Failed to increment usage metrics");
      }
    } else {
      console.warn(
        `Translation without circleId for user ${user.id} — usage not tracked`,
      );
    }

    // 12. Return response
    const response: TranslateResponse = {
      translatedText,
      confidenceScore,
      medicalTermsFound: [], // Don't transmit actual medication names (PHI)
      disclaimer: containsMedicalTerms || confidenceScore < 0.95,
    };

    return jsonResponse(response);
  } catch (error) {
    console.error(
      "translate-content error:",
      error instanceof Error ? error.message : "Unknown error",
    );
    return errorResponse("INTERNAL_ERROR", "An internal error occurred", 500);
  }
});
