import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

// ============================================================================
// Types
// ============================================================================

interface DetectLanguageRequest {
  text: string;
}

interface DetectLanguageResponse {
  detectedLanguage: string;
  confidence: number;
  alternatives: {
    language: string;
    confidence: number;
  }[];
}

// Supported language codes
const SUPPORTED_LANGUAGES = ["en", "es", "zh-Hans", "vi", "ko", "tl", "fr"];

// Maximum text length for detection (5KB is plenty)
const MAX_TEXT_LENGTH = 5_000;

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
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return errorResponse("AUTH_INVALID", "Invalid authorization token", 401);
    }

    // 2. Parse request
    const body: DetectLanguageRequest = await req.json();
    const { text } = body;

    if (!text || typeof text !== "string" || text.trim().length === 0) {
      return errorResponse(
        "INVALID_INPUT",
        "Missing required field: text",
        400,
      );
    }

    // Enforce text length limit
    if (text.length > MAX_TEXT_LENGTH) {
      return errorResponse(
        "INVALID_INPUT",
        `Text exceeds maximum length of ${MAX_TEXT_LENGTH} characters`,
        400,
      );
    }

    // For very short text, use heuristic detection first (no API call needed)
    if (text.trim().length < 10) {
      const heuristicResult = heuristicDetect(text);
      if (heuristicResult) {
        return jsonResponse(heuristicResult);
      }
    }

    // 3. Check subscription tier to prevent unlimited API abuse
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    const { data: subscription } = await supabaseService
      .from("subscriptions")
      .select("plan")
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const userPlan = subscription?.plan || "FREE";
    if (userPlan === "FREE") {
      return errorResponse(
        "FEATURE_LOCKED",
        "Language detection requires Plus or Family plan",
        402,
      );
    }

    // 4. Detect language via OpenAI
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      return errorResponse(
        "CONFIG_ERROR",
        "Language detection service not configured",
        500,
      );
    }

    const systemPrompt = `You are a language detection system. Analyze the given text and determine the language.

Respond with ONLY a JSON object in this exact format (no other text):
{
  "primary": {"code": "ISO_CODE", "confidence": 0.95},
  "alternatives": [{"code": "ISO_CODE", "confidence": 0.05}]
}

Supported language codes: en (English), es (Spanish), zh-Hans (Chinese Simplified), vi (Vietnamese), ko (Korean), tl (Tagalog), fr (French).

If the text contains mixed languages, report the dominant language as primary with lower confidence, and include other detected languages as alternatives.
If the text is too short or ambiguous, use your best judgment and lower the confidence score accordingly.`;

    // Create timeout AFTER heuristic check to prevent leak on early return
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);

    try {
      // Limit input to 1000 chars for detection (more than enough)
      const truncatedText = text.substring(0, 1000);

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
              { role: "user", content: truncatedText },
            ],
            temperature: 0.1,
            max_tokens: 200,
          }),
          signal: controller.signal,
        },
      );

      if (!response.ok) {
        const errStatus = response.status;
        console.error(`OpenAI API error: status ${errStatus}`);
        // Fallback to heuristic
        const fallback = heuristicDetect(text);
        if (fallback) return jsonResponse(fallback);
        return errorResponse(
          "DETECTION_FAILED",
          "Language detection service error",
          502,
        );
      }

      const result = await response.json();
      const content = result.choices[0].message.content.trim();

      // Parse the JSON response
      let parsed;
      try {
        parsed = JSON.parse(content);
      } catch {
        console.error("Failed to parse LLM response for language detection");
        const fallback = heuristicDetect(text);
        if (fallback) return jsonResponse(fallback);
        return errorResponse(
          "DETECTION_FAILED",
          "Language detection failed",
          500,
        );
      }

      // Map to supported languages
      const primaryCode = mapToSupportedLanguage(parsed.primary.code);
      const alternatives = (parsed.alternatives || [])
        .map((alt: { code: string; confidence: number }) => ({
          language: mapToSupportedLanguage(alt.code),
          confidence: alt.confidence,
        }))
        .filter(
          (alt: { language: string; confidence: number }) =>
            alt.language !== primaryCode &&
            SUPPORTED_LANGUAGES.includes(alt.language),
        );

      const responseData: DetectLanguageResponse = {
        detectedLanguage: primaryCode,
        confidence: parsed.primary.confidence,
        alternatives,
      };

      return jsonResponse(responseData);
    } finally {
      clearTimeout(timeout);
    }
  } catch (error) {
    console.error(
      "detect-language error:",
      error instanceof Error ? error.message : "Unknown error",
    );
    return errorResponse("INTERNAL_ERROR", "An internal error occurred", 500);
  }
});

// ============================================================================
// Helpers
// ============================================================================

/**
 * Map various ISO codes to our supported set
 */
function mapToSupportedLanguage(code: string): string {
  const normalized = code.toLowerCase().trim();

  // Direct matches
  if (SUPPORTED_LANGUAGES.includes(normalized)) return normalized;

  // Chinese variants
  if (
    normalized === "zh" ||
    normalized === "zh-cn" ||
    normalized === "zh-hans" ||
    normalized === "cmn"
  ) {
    return "zh-Hans";
  }

  // Tagalog/Filipino
  if (normalized === "fil" || normalized === "tl") return "tl";

  // Default to English if unknown
  return "en";
}

/**
 * Heuristic-based language detection for short or simple text
 */
function heuristicDetect(text: string): DetectLanguageResponse | null {
  const trimmed = text.trim();

  // Check for CJK characters (Chinese)
  if (/[\u4e00-\u9fff\u3400-\u4dbf]/.test(trimmed)) {
    return {
      detectedLanguage: "zh-Hans",
      confidence: 0.85,
      alternatives: [],
    };
  }

  // Check for Korean characters
  if (/[\uac00-\ud7af\u1100-\u11ff]/.test(trimmed)) {
    return {
      detectedLanguage: "ko",
      confidence: 0.9,
      alternatives: [],
    };
  }

  // Check for Vietnamese diacritics
  if (
    /[ăâđêôơưàảãáạằẳẵắặầẩẫấậèẻẽéẹềểễếệìỉĩíịòỏõóọồổỗốộờởỡớợùủũúụừửữứựỳỷỹýỵ]/i.test(
      trimmed,
    )
  ) {
    return {
      detectedLanguage: "vi",
      confidence: 0.85,
      alternatives: [],
    };
  }

  // Check for Spanish-specific characters and common words
  if (
    /[ñ¿¡]/i.test(trimmed) ||
    /\b(?:el|la|los|las|es|está|tiene|por|para|con|que|del|una|uno)\b/i.test(
      trimmed,
    )
  ) {
    return {
      detectedLanguage: "es",
      confidence: 0.75,
      alternatives: [{ language: "fr", confidence: 0.1 }],
    };
  }

  // Check for French-specific patterns
  if (
    /[àâæçéèêëîïôœùûüÿ]/i.test(trimmed) &&
    /\b(?:le|la|les|des|est|avec|pour|dans|une|que|je|tu|il|nous|vous)\b/i.test(
      trimmed,
    )
  ) {
    return {
      detectedLanguage: "fr",
      confidence: 0.75,
      alternatives: [{ language: "es", confidence: 0.1 }],
    };
  }

  // Check for Tagalog common words
  if (
    /\b(?:ang|ng|mga|sa|na|at|ay|si|ni|ko|mo|niya|ito|iyan|namin|kanila)\b/i.test(
      trimmed,
    )
  ) {
    return {
      detectedLanguage: "tl",
      confidence: 0.7,
      alternatives: [{ language: "en", confidence: 0.15 }],
    };
  }

  // Default to English for Latin script
  if (/^[a-zA-Z\s\d.,!?;:'"()-]+$/.test(trimmed)) {
    return {
      detectedLanguage: "en",
      confidence: 0.7,
      alternatives: [],
    };
  }

  return null;
}
