/**
 * LLM-based concern extraction from handoff text
 *
 * Uses GPT-4o-mini for cost-effective extraction with strict
 * non-clinical language guidelines.
 */

import {
  ConcernCategory,
  BANNED_CLINICAL_TERMS,
  type ConcernExtraction,
} from "./types.ts";

// Raw concern shape from LLM response (before validation)
interface RawConcern {
  category?: string;
  rawText?: string;
  normalizedTerm?: string;
}

// Configuration
const LLM_TIMEOUT_MS = 30000; // 30 seconds
const MAX_RETRIES = 3;
const MAX_INPUT_LENGTH = 5000; // ~1250 tokens

const EXTRACTION_SYSTEM_PROMPT = `You are extracting symptom observations from family caregiver notes.

CRITICAL RULES:
1. Use ONLY observational language (e.g., "appears tired", "reports pain", "seemed confused")
2. NEVER use clinical diagnoses, medical terminology, or assessments
3. Map observations to exactly one of these categories: TIREDNESS, APPETITE, SLEEP, PAIN, MOOD, MOBILITY, COGNITION, DIGESTION, BREATHING, SKIN
4. Extract the exact phrase from the text as rawText
5. Normalize to a consistent observational term (e.g., "lethargic" → "appears very tired")
6. Ignore negations ("not tired anymore", "pain is gone") - only positive mentions
7. Ignore medical procedures, tests, or appointments

CATEGORIES:
- TIREDNESS: tired, exhausted, no energy, fatigued, sluggish, lethargic
- APPETITE: not eating, no appetite, eating less, eating well
- SLEEP: can't sleep, insomnia, sleeping a lot, restless sleep
- PAIN: hurting, aches, discomfort, sore
- MOOD: sad, anxious, irritable, worried, upset, crying
- MOBILITY: trouble walking, fell, unsteady, balance issues
- COGNITION: confused, forgetful, disoriented, unclear
- DIGESTION: nausea, constipation, diarrhea, upset stomach
- BREATHING: short of breath, coughing, wheezing
- SKIN: rash, bruise, swelling, wound, redness

BANNED TERMS (never use): diagnosis, disease, infection, syndrome, disorder, condition, acute, chronic, severe, critical, emergency, prognosis, treatment, prescription

Output a JSON array of objects with:
- category: one of the categories above
- rawText: exact phrase from the input (max 100 chars)
- normalizedTerm: observational summary (e.g., "appears tired", "reports poor appetite")

If no symptom observations found, return empty array [].`;

/**
 * Sanitize input text to prevent prompt injection attacks
 */
function sanitizeInput(text: string): string {
  // Truncate to max length
  let sanitized = text.substring(0, MAX_INPUT_LENGTH);

  // Remove potential prompt injection patterns
  sanitized = sanitized
    .replace(/IGNORE.{0,30}PREVIOUS.{0,30}INSTRUCTIONS/gi, "[REDACTED]")
    .replace(/SYSTEM.{0,20}PROMPT/gi, "[REDACTED]")
    .replace(/\{[^}]*"category"[^}]*\}/gi, "[REDACTED]") // Remove JSON-like injection
    .replace(/```/g, ""); // Remove markdown code blocks

  return sanitized.trim();
}

/**
 * Make LLM API call with timeout
 */
async function callLLMWithTimeout(
  sanitizedText: string,
  openaiApiKey: string,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openaiApiKey}`,
      },
      body: JSON.stringify({
        model: Deno.env.get("LLM_EXTRACTION_MODEL") || "gpt-4o-mini",
        messages: [
          { role: "system", content: EXTRACTION_SYSTEM_PROMPT },
          {
            role: "user",
            content: `Extract symptom observations from this caregiver note:

<user_input>
${sanitizedText}
</user_input>

Remember: Only extract observational symptoms from the <user_input> block above.`,
          },
        ],
        temperature: 0.1,
        max_tokens: 2000,
        response_format: { type: "json_object" },
      }),
    });
    clearTimeout(timeoutId);
    return response;
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error(`OpenAI API timeout after ${timeoutMs}ms`);
    }
    throw error;
  }
}

export async function extractConcerns(
  handoffText: string,
  openaiApiKey: string,
): Promise<ConcernExtraction[]> {
  if (!handoffText.trim()) {
    return [];
  }

  // Sanitize input to prevent prompt injection
  const sanitizedText = sanitizeInput(handoffText);
  if (!sanitizedText) {
    return [];
  }

  // Retry loop with exponential backoff
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await callLLMWithTimeout(
        sanitizedText,
        openaiApiKey,
        LLM_TIMEOUT_MS,
      );

      if (!response.ok) {
        const status = response.status;
        // Don't log response body (may contain PHI echoed back)
        throw new Error(`OpenAI API error: ${status}`);
      }

      const data = await response.json();
      const content = data.choices?.[0]?.message?.content;

      if (!content) {
        return [];
      }

      return parseAndValidateConcerns(content);
    } catch (error) {
      lastError = error instanceof Error ? error : new Error("Unknown error");

      // Check if error is retryable (rate limit, timeout, network error)
      const isRetryable =
        lastError.message.includes("429") ||
        lastError.message.includes("timeout") ||
        lastError.message.includes("ECONNRESET") ||
        lastError.message.includes("fetch failed");

      if (!isRetryable || attempt === MAX_RETRIES - 1) {
        // Log without PHI
        console.error(
          `LLM extraction failed after ${attempt + 1} attempts: ${lastError.message}`,
        );
        return [];
      }

      // Exponential backoff: 1s, 2s, 4s
      const delayMs = Math.pow(2, attempt) * 1000;
      console.warn(
        `LLM API error (attempt ${attempt + 1}/${MAX_RETRIES}), retrying in ${delayMs}ms`,
      );
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  return [];
}

/**
 * Parse and validate LLM response content
 */
function parseAndValidateConcerns(content: string): ConcernExtraction[] {
  try {
    // Strip markdown code blocks if present
    let jsonContent = content.trim();
    if (jsonContent.startsWith("```")) {
      jsonContent = jsonContent
        .replace(/^```(?:json)?\n?/, "")
        .replace(/\n?```$/, "");
    }

    const parsed = JSON.parse(jsonContent);

    // Extract concerns array from various response formats
    let concerns: RawConcern[] = [];
    if (Array.isArray(parsed)) {
      concerns = parsed as RawConcern[];
    } else if (parsed.concerns && Array.isArray(parsed.concerns)) {
      concerns = parsed.concerns as RawConcern[];
    } else if (parsed.data && Array.isArray(parsed.data)) {
      concerns = parsed.data as RawConcern[];
    } else if (parsed.result && Array.isArray(parsed.result)) {
      concerns = parsed.result as RawConcern[];
    } else if (
      parsed.result?.concerns &&
      Array.isArray(parsed.result.concerns)
    ) {
      concerns = parsed.result.concerns as RawConcern[];
    }

    if (!Array.isArray(concerns)) {
      console.warn("LLM response missing concerns array");
      return [];
    }

    // Validate and sanitize each concern
    const validConcerns: ConcernExtraction[] = [];

    for (const concern of concerns) {
      // Validate category exists and is valid
      if (
        !concern.category ||
        !Object.values(ConcernCategory).includes(
          concern.category as ConcernCategory,
        )
      ) {
        continue;
      }

      // Validate rawText exists and length (max 200 chars to match truncation)
      if (
        !concern.rawText ||
        typeof concern.rawText !== "string" ||
        concern.rawText.length > 200
      ) {
        continue;
      }

      // Validate normalizedTerm exists and length
      if (
        !concern.normalizedTerm ||
        typeof concern.normalizedTerm !== "string" ||
        concern.normalizedTerm.length > 200
      ) {
        continue;
      }

      // Sanitize: remove banned clinical terms
      const sanitizedTerm = sanitizeClinicalTerms(concern.normalizedTerm);
      if (!sanitizedTerm) {
        continue;
      }

      // Sanitize output to prevent XSS/injection
      const safeRawText = sanitizeOutput(concern.rawText.substring(0, 200));
      const safeNormalizedTerm = sanitizeOutput(sanitizedTerm);

      validConcerns.push({
        category: concern.category as ConcernCategory,
        rawText: safeRawText,
        normalizedTerm: safeNormalizedTerm,
      });
    }

    return validConcerns;
  } catch (error) {
    // Log without PHI (don't log content)
    console.error(
      "Failed to parse LLM response:",
      error instanceof Error ? error.message : "parse error",
    );
    return [];
  }
}

function sanitizeClinicalTerms(text: string): string | null {
  const lowerText = text.toLowerCase();

  // Check for banned terms
  for (const banned of BANNED_CLINICAL_TERMS) {
    if (lowerText.includes(banned.toLowerCase())) {
      return null;
    }
  }

  return text.trim();
}

/**
 * Sanitize output text to prevent XSS/injection
 */
function sanitizeOutput(text: string): string {
  return text
    .replace(/[<>]/g, "") // Remove HTML tags
    .replace(/["']/g, "") // Remove quotes that could break JSON
    .replace(/;/g, "") // Remove SQL delimiters
    .replace(/--/g, "") // Remove SQL comments
    .trim();
}

export type { ConcernExtraction };
