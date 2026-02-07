import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

// ============================================================================
// Cleanup Translation Cache (Cron Job)
//
// Runs daily to:
// 1. Remove expired translation cache entries
// 2. Mark handoff translations as stale when source content changed
//
// Auth: Requires service role key via Authorization header (cron/admin only)
// ============================================================================

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // This function is designed for cron jobs / admin use only.
    // Validate the Authorization header contains a valid service role key or
    // the Supabase cron secret.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse("AUTH_MISSING", "Missing Authorization header", 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Verify the bearer token matches the service role key (cron jobs use this)
    // Use timing-safe comparison to prevent timing attacks
    const token = authHeader.replace("Bearer ", "");
    const tokenBytes = new TextEncoder().encode(token);
    const keyBytes = new TextEncoder().encode(supabaseServiceKey);
    const isValidToken =
      tokenBytes.length === keyBytes.length && crypto.subtle.timingSafeEqual
        ? await (async () => {
            try {
              return crypto.subtle.timingSafeEqual(tokenBytes, keyBytes);
            } catch {
              // Fallback for environments without timingSafeEqual
              return token === supabaseServiceKey;
            }
          })()
        : token === supabaseServiceKey;

    if (!isValidToken) {
      return errorResponse(
        "AUTH_INVALID",
        "Unauthorized: cleanup requires service role access",
        403,
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 1. Delete expired translation cache entries
    const { data: expiredEntries, error: deleteError } = await supabase
      .from("translation_cache")
      .delete()
      .lt("expires_at", new Date().toISOString())
      .select("id");

    if (deleteError) {
      console.error(
        "Error deleting expired cache entries:",
        deleteError.message,
      );
    }

    const entriesRemoved = expiredEntries?.length || 0;

    // 2. Mark handoff translations as stale using RPC
    let entriesMarkedStale = 0;
    const { data: staleResult, error: staleError } = await supabase.rpc(
      "mark_stale_translations",
    );

    if (staleError) {
      // If the RPC doesn't exist yet, log the error. Do NOT use an age-based
      // fallback since that incorrectly marks valid translations as stale.
      console.error(
        "mark_stale_translations RPC failed — skipping stale marking:",
        staleError.message,
      );
    } else {
      entriesMarkedStale = typeof staleResult === "number" ? staleResult : 0;
    }

    // 3. Log cleanup results
    console.log(
      `Translation cache cleanup: removed=${entriesRemoved}, stale=${entriesMarkedStale}`,
    );

    return jsonResponse({
      success: true,
      entriesRemoved,
      entriesMarkedStale,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error(
      "cleanup-translation-cache error:",
      error instanceof Error ? error.message : "Unknown error",
    );
    return errorResponse("INTERNAL_ERROR", "An internal error occurred", 500);
  }
});
