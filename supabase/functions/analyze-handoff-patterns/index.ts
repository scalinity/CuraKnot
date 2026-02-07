/**
 * Edge Function: analyze-handoff-patterns
 *
 * Analyzes handoffs to detect symptom patterns using LLM extraction.
 * Triggered daily via cron job or manually via POST request.
 *
 * Pattern Types:
 * - FREQUENCY: Concern mentioned 3+ times in 30 days
 * - TREND: Increasing or decreasing mentions over time
 * - CORRELATION: Concern started near medication/facility change
 * - NEW: First mention in last 7 days
 * - ABSENCE: Previously frequent concern not mentioned recently
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { extractConcerns, type ConcernExtraction } from "./extractConcerns.ts";
import { detectPatterns } from "./detectPatterns.ts";
import { correlateEvents, type CorrelatedEvent } from "./correlateEvents.ts";
import { ConcernCategory, PatternType } from "./types.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Types for Supabase query results
interface PatientRecord {
  id: string;
  circle_id: string;
}

interface HandoffRecord {
  id: string;
  title: string | null;
  summary: string | null;
  body: string | null;
  created_at: string;
}

interface PatternIdRecord {
  id: string;
}

interface AnalyzeRequest {
  patientId?: string;
  circleId?: string;
  rangeStartDays?: number;
}

interface AnalyzeResponse {
  patientsAnalyzed: number;
  patternsCreated: number;
  patternsUpdated: number;
  // SECURITY: Use index instead of patientId to avoid PHI in API response
  errors: Array<{ patientIndex: number; error: string }>;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const openaiKey = Deno.env.get("OPENAI_API_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Missing Supabase configuration" }),
        {
          status: 500,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    if (!openaiKey) {
      return new Response(JSON.stringify({ error: "Missing OpenAI API key" }), {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Get user from JWT (for manual triggers)
    let userId: string | null = null;
    const authHeader = req.headers.get("Authorization");
    if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser(token);
      if (authError) {
        console.error("Auth error (details redacted)");
        return new Response(
          JSON.stringify({ error: "Authentication failed" }),
          {
            status: 401,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          },
        );
      }
      userId = user?.id ?? null;
    }

    // Parse request body
    let requestBody: AnalyzeRequest = {};
    if (req.method === "POST") {
      try {
        requestBody = await req.json();
      } catch {
        // Empty body is OK for cron trigger
      }
    }

    const { patientId, circleId, rangeStartDays = 30 } = requestBody;

    // SECURITY: Validate UUID format to prevent injection
    const UUID_REGEX =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (patientId && !UUID_REGEX.test(patientId)) {
      return new Response(
        JSON.stringify({ error: "Invalid patient ID format" }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }
    if (circleId && !UUID_REGEX.test(circleId)) {
      return new Response(
        JSON.stringify({ error: "Invalid circle ID format" }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // SECURITY: Verify user has access to requested patient/circle
    if (userId && (patientId || circleId)) {
      // Resolve target circle ID - must await if fetching from patient
      let targetCircleId: string | undefined = circleId;
      if (!targetCircleId && patientId) {
        const { data: patient } = await supabase
          .from("patients")
          .select("circle_id")
          .eq("id", patientId)
          .single();
        targetCircleId = patient?.circle_id;
      }

      if (targetCircleId) {
        const { data: membership } = await supabase
          .from("circle_members")
          .select("id")
          .eq("circle_id", targetCircleId)
          .eq("user_id", userId)
          .eq("status", "ACTIVE")
          .single();

        if (!membership) {
          return new Response(
            JSON.stringify({
              error: "Unauthorized access to patient data",
            }),
            {
              status: 403,
              headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
            },
          );
        }
      }
    }

    // Fetch patients to analyze
    let patientsQuery = supabase.from("patients").select("id, circle_id");

    if (patientId) {
      patientsQuery = patientsQuery.eq("id", patientId);
    } else if (circleId) {
      patientsQuery = patientsQuery.eq("circle_id", circleId);
    }

    const { data: patients, error: patientsError } = await patientsQuery;

    if (patientsError) {
      throw new Error(`Failed to fetch patients: ${patientsError.message}`);
    }

    if (!patients || patients.length === 0) {
      return new Response(
        JSON.stringify({
          patientsAnalyzed: 0,
          patternsCreated: 0,
          patternsUpdated: 0,
          errors: [],
        }),
        { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    // Cast to typed array
    const typedPatients = patients as PatientRecord[];

    // Filter patients by subscription (only PLUS/FAMILY circles)
    // PERFORMANCE: Batch fetch all circle owners instead of N+1 queries
    const circleIds = [...new Set(typedPatients.map((p) => p.circle_id))];

    // Batch fetch all owners in one query
    const { data: allMemberships } = await supabase
      .from("circle_members")
      .select("circle_id, user_id")
      .in("circle_id", circleIds)
      .eq("role", "OWNER");

    if (!allMemberships || allMemberships.length === 0) {
      return new Response(
        JSON.stringify({
          patientsAnalyzed: 0,
          patternsCreated: 0,
          patternsUpdated: 0,
          errors: [{ patientId: "all", error: "No circle owners found" }],
        }),
        { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    // Build owner lookup map
    const ownerByCircle = new Map<string, string>();
    for (const m of allMemberships) {
      ownerByCircle.set(m.circle_id, m.user_id);
    }

    // PERFORMANCE: Check feature access for all owners in parallel
    const accessibleCircles = new Set<string>();
    const accessChecks = Array.from(ownerByCircle.entries()).map(
      async ([cId, ownerId]) => {
        const { data: hasAccess } = await supabase.rpc("has_feature_access", {
          p_user_id: ownerId,
          p_feature: "symptom_patterns",
        });
        return { circleId: cId, hasAccess: !!hasAccess };
      },
    );
    const accessResults = await Promise.all(accessChecks);
    for (const { circleId, hasAccess } of accessResults) {
      if (hasAccess) {
        accessibleCircles.add(circleId);
      }
    }

    const eligiblePatients = typedPatients.filter((p) =>
      accessibleCircles.has(p.circle_id),
    );

    if (eligiblePatients.length === 0) {
      return new Response(
        JSON.stringify({
          patientsAnalyzed: 0,
          patternsCreated: 0,
          patternsUpdated: 0,
          errors: [
            {
              patientId: "all",
              error: "No eligible patients (subscription required)",
            },
          ],
        }),
        { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    const response: AnalyzeResponse = {
      patientsAnalyzed: 0,
      patternsCreated: 0,
      patternsUpdated: 0,
      errors: [],
    };

    // Process each patient
    for (const patient of eligiblePatients) {
      try {
        const result = await analyzePatientHandoffs(
          supabase,
          patient.id,
          patient.circle_id,
          rangeStartDays,
          openaiKey,
        );
        response.patientsAnalyzed++;
        response.patternsCreated += result.created;
        response.patternsUpdated += result.updated;
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : "Unknown error";
        // SECURITY: Don't log patient ID (PHI) - use generic error
        console.error("Error analyzing patient:", errorMessage);
        // SECURITY: Use index instead of patient ID to avoid PHI in response
        response.errors.push({
          patientIndex: eligiblePatients.indexOf(patient),
          error: errorMessage,
        });
      }
    }

    return new Response(JSON.stringify(response), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Fatal error:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Internal server error",
      }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});

async function analyzePatientHandoffs(
  supabase: SupabaseClient,
  patientId: string,
  circleId: string,
  rangeStartDays: number,
  openaiKey: string,
): Promise<{ created: number; updated: number }> {
  const rangeStart = new Date();
  rangeStart.setDate(rangeStart.getDate() - rangeStartDays);

  // Fetch handoffs for this patient
  const { data: handoffs, error: handoffsError } = await supabase
    .from("handoffs")
    .select("id, title, summary, body, created_at")
    .eq("patient_id", patientId)
    .eq("status", "PUBLISHED")
    .gte("created_at", rangeStart.toISOString())
    .order("created_at", { ascending: true });

  if (handoffsError) {
    throw new Error(`Failed to fetch handoffs: ${handoffsError.message}`);
  }

  if (!handoffs || handoffs.length === 0) {
    return { created: 0, updated: 0 };
  }

  // Cast to typed array
  const typedHandoffs = handoffs as HandoffRecord[];

  // Extract concerns from each handoff
  const allExtractions: Array<
    ConcernExtraction & { handoffId: string; createdAt: Date }
  > = [];

  for (const handoff of typedHandoffs) {
    const text = [handoff.title, handoff.summary, handoff.body]
      .filter(Boolean)
      .join(" ");

    if (!text.trim()) continue;

    try {
      const concerns = await extractConcerns(text, openaiKey);
      for (const concern of concerns) {
        allExtractions.push({
          ...concern,
          handoffId: handoff.id,
          createdAt: new Date(handoff.created_at),
        });
      }
    } catch (error) {
      // SECURITY: Don't log handoff ID (PHI linkage) - use generic error
      const errorMsg =
        error instanceof Error ? error.message : "extraction failed";
      console.error("Failed to extract concerns from handoff:", errorMsg);
      // Continue with other handoffs
    }
  }

  if (allExtractions.length === 0) {
    return { created: 0, updated: 0 };
  }

  // Group extractions by category
  const byCategory = new Map<ConcernCategory, typeof allExtractions>();
  for (const extraction of allExtractions) {
    const existing = byCategory.get(extraction.category) || [];
    existing.push(extraction);
    byCategory.set(extraction.category, existing);
  }

  let created = 0;
  let updated = 0;

  // Detect patterns for each category
  for (const [category, extractions] of byCategory) {
    const mentions = extractions.map((e) => ({
      handoffId: e.handoffId,
      createdAt: e.createdAt,
      normalizedTerm: e.normalizedTerm,
      rawText: e.rawText,
    }));

    const patterns = detectPatterns(category, mentions);

    for (const pattern of patterns) {
      // Generate pattern hash for deduplication
      const patternHash = await generatePatternHash(
        circleId,
        patientId,
        category,
        pattern.type,
      );

      // Get correlations for CORRELATION type or any pattern with recent first mention
      let correlatedEvents: CorrelatedEvent[] = [];
      if (
        pattern.type === PatternType.CORRELATION ||
        pattern.type === PatternType.NEW
      ) {
        correlatedEvents = await correlateEvents(
          supabase,
          patientId,
          circleId,
          category,
          pattern.firstMentionDate,
        );
      }

      // Upsert pattern
      const patternData = {
        circle_id: circleId,
        patient_id: patientId,
        concern_category: category,
        concern_keywords: [...new Set(mentions.map((m) => m.normalizedTerm))],
        pattern_type: pattern.type,
        pattern_hash: patternHash,
        mention_count: pattern.mentionCount,
        first_mention_at: pattern.firstMentionDate.toISOString(),
        last_mention_at: pattern.lastMentionDate.toISOString(),
        trend: pattern.trend ?? null,
        correlated_events:
          correlatedEvents.length > 0 ? correlatedEvents : null,
        source_handoff_ids: [...new Set(mentions.map((m) => m.handoffId))],
        updated_at: new Date().toISOString(),
      };

      // CORRECTNESS: Use maybeSingle() to handle 0 results without throwing
      const { data: existingPatternData } = await supabase
        .from("detected_patterns")
        .select("id")
        .eq("pattern_hash", patternHash)
        .maybeSingle();

      const existingPattern = existingPatternData as PatternIdRecord | null;

      if (existingPattern) {
        // Update existing pattern
        const { error: updateError } = await supabase
          .from("detected_patterns")
          .update(patternData)
          .eq("id", existingPattern.id);

        if (updateError) {
          console.error(`Failed to update pattern:`, updateError);
        } else {
          updated++;
          // Update mentions
          await upsertMentions(supabase, existingPattern.id, mentions);
        }
      } else {
        // Create new pattern
        const { data: newPatternData, error: insertError } = await supabase
          .from("detected_patterns")
          .insert(patternData)
          .select("id")
          .single();

        const newPattern = newPatternData as PatternIdRecord | null;

        if (insertError) {
          console.error(`Failed to create pattern:`, insertError);
        } else if (newPattern) {
          created++;
          // Create mentions
          await upsertMentions(supabase, newPattern.id, mentions);
        }
      }
    }
  }

  return { created, updated };
}

async function generatePatternHash(
  circleId: string,
  patientId: string,
  category: ConcernCategory,
  patternType: PatternType,
): Promise<string> {
  // Include circleId to prevent cross-circle hash collisions
  const data = `${circleId}:${patientId}:${category}:${patternType}`;
  const encoder = new TextEncoder();
  const dataBuffer = encoder.encode(data);
  const hashBuffer = await crypto.subtle.digest("SHA-256", dataBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function upsertMentions(
  supabase: SupabaseClient,
  patternId: string,
  mentions: Array<{
    handoffId: string;
    createdAt: Date;
    normalizedTerm: string;
    rawText: string;
  }>,
): Promise<void> {
  // Batch insert mentions
  const chunks = chunkArray(mentions, 100);
  for (const chunk of chunks) {
    const { error } = await supabase.from("pattern_mentions").upsert(
      chunk.map((m) => ({
        pattern_id: patternId,
        handoff_id: m.handoffId,
        matched_text: m.rawText.substring(0, 500), // Truncate
        normalized_term: m.normalizedTerm,
        mentioned_at: m.createdAt.toISOString(),
      })),
      { onConflict: "pattern_id,handoff_id" },
    );

    if (error) {
      console.error(`Failed to upsert mentions:`, error);
    }
  }
}

// Helper function to chunk array into smaller arrays
function chunkArray<T>(array: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}
