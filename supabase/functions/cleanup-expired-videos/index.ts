import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface CleanupResult {
  success: boolean;
  deletedCount: number;
  freedBytes: number;
  errors: string[];
}

/**
 * Cleanup expired videos Edge Function
 *
 * This function should be called by a cron job (e.g., daily at 3 AM)
 * to clean up expired video messages and their storage files.
 *
 * Schedule via Supabase cron:
 * SELECT cron.schedule('cleanup-expired-videos', '0 3 * * *',
 *   $$ SELECT net.http_post(
 *     'https://<project>.supabase.co/functions/v1/cleanup-expired-videos',
 *     '{}',
 *     '{"Authorization": "Bearer <service_role_key>", "Content-Type": "application/json"}'
 *   ) $$
 * );
 */
serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // This function requires service role key (called by cron, not users)
    const authHeader = req.headers.get("Authorization");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!authHeader || !serviceKey) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Extract token from Bearer header
    const token = authHeader.replace("Bearer ", "");

    // Timing-safe comparison to prevent timing attacks
    const encoder = new TextEncoder();
    const tokenBytes = encoder.encode(token);
    const keyBytes = encoder.encode(serviceKey);
    const tokensMatch =
      tokenBytes.length === keyBytes.length &&
      crypto.subtle.timingSafeEqual(tokenBytes, keyBytes);

    // Only allow service role key - no user tokens for this sensitive operation
    if (!tokensMatch) {
      console.warn("Cleanup attempt with non-service-role token");
      return new Response(
        JSON.stringify({ error: "Unauthorized - service role required" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Initialize Supabase admin client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const result = await cleanupExpiredVideos(supabase);

    return new Response(JSON.stringify(result), {
      status: result.success ? 200 : 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Cleanup error occurred");
    return new Response(
      JSON.stringify({
        success: false,
        deletedCount: 0,
        freedBytes: 0,
        errors: ["Internal error occurred"],
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

async function cleanupExpiredVideos(
  supabase: ReturnType<typeof createClient>,
): Promise<CleanupResult> {
  const result: CleanupResult = {
    success: true,
    deletedCount: 0,
    freedBytes: 0,
    errors: [],
  };

  const now = new Date().toISOString();

  // Find expired videos (not saved forever, past expiration date)
  const { data: expiredVideos, error: fetchError } = await supabase
    .from("video_messages")
    .select("id, storage_key, thumbnail_key, file_size_bytes")
    .eq("save_forever", false)
    .lt("expires_at", now)
    .in("status", ["ACTIVE", "FLAGGED", "REMOVED"]);

  if (fetchError) {
    result.success = false;
    result.errors.push("Failed to fetch expired videos");
    return result;
  }

  if (!expiredVideos || expiredVideos.length === 0) {
    console.log("No expired videos to clean up");
    return result;
  }

  console.log(`Found ${expiredVideos.length} expired videos to clean up`);

  // Process each expired video
  for (const video of expiredVideos) {
    try {
      // Validate storage key format before using
      if (video.storage_key && !isValidStorageKey(video.storage_key)) {
        result.errors.push(`Invalid storage key format for video ${video.id}`);
        continue;
      }

      // Delete video file from storage
      if (video.storage_key) {
        const { error: videoDeleteError } = await supabase.storage
          .from("video-messages")
          .remove([video.storage_key]);

        if (videoDeleteError) {
          console.warn(`Failed to delete video file for video ${video.id}`);
          result.errors.push(`Storage delete failed for ${video.id}`);
        }
      }

      // Delete thumbnail if exists
      if (video.thumbnail_key) {
        // Validate thumbnail key format
        if (!isValidThumbnailKey(video.thumbnail_key)) {
          console.warn(`Invalid thumbnail key format for video ${video.id}`);
        } else {
          const { error: thumbDeleteError } = await supabase.storage
            .from("video-messages")
            .remove([video.thumbnail_key]);

          if (thumbDeleteError) {
            console.warn(`Failed to delete thumbnail for video ${video.id}`);
            // Non-fatal, continue
          }
        }
      }

      // Update video status to DELETED
      const { error: updateError } = await supabase
        .from("video_messages")
        .update({
          status: "DELETED",
          storage_key: null, // Clear storage key since file is deleted
          thumbnail_key: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", video.id);

      if (updateError) {
        result.errors.push(`Failed to update video ${video.id}`);
        continue;
      }

      result.deletedCount++;
      result.freedBytes += video.file_size_bytes || 0;

      console.log(
        `Deleted video ${video.id}, freed ${video.file_size_bytes || 0} bytes`,
      );
    } catch (videoError) {
      result.errors.push(`Error processing video ${video.id}`);
    }
  }

  // Also clean up orphaned reactions and views for deleted videos
  await cleanupOrphanedData(supabase);

  // Refresh the materialized view for accurate quota tracking
  try {
    await supabase.rpc("refresh_video_stats");
    console.log("Video stats refreshed");
  } catch (refreshError) {
    console.warn("Failed to refresh video stats");
    // Non-fatal
  }

  // Log summary (no PHI)
  console.log(
    `Cleanup complete: ${result.deletedCount} videos deleted, ` +
      `${(result.freedBytes / 1048576).toFixed(2)} MB freed, ` +
      `${result.errors.length} errors`,
  );

  return result;
}

// Validate storage key format
function isValidStorageKey(key: string): boolean {
  if (key.includes("..") || key.includes("//") || key.startsWith("/")) {
    return false;
  }
  const storageKeyRegex = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\.mp4$/i;
  return storageKeyRegex.test(key);
}

// Validate thumbnail key format
function isValidThumbnailKey(key: string): boolean {
  if (key.includes("..") || key.includes("//") || key.startsWith("/")) {
    return false;
  }
  const thumbnailKeyRegex = /^[0-9a-f-]{36}\/[0-9a-f-]{36}_thumb\.jpg$/i;
  return thumbnailKeyRegex.test(key);
}

async function cleanupOrphanedData(
  supabase: ReturnType<typeof createClient>,
): Promise<void> {
  // Delete reactions for deleted videos using a subquery approach
  // First get the deleted video IDs
  const { data: deletedVideos } = await supabase
    .from("video_messages")
    .select("id")
    .eq("status", "DELETED");

  if (deletedVideos && deletedVideos.length > 0) {
    const deletedIds = deletedVideos.map((v: { id: string }) => v.id);

    // Delete reactions
    const { error: reactionsError } = await supabase
      .from("video_reactions")
      .delete()
      .in("video_message_id", deletedIds);

    if (reactionsError) {
      console.warn("Failed to cleanup orphaned reactions");
    }

    // Delete views
    const { error: viewsError } = await supabase
      .from("video_views")
      .delete()
      .in("video_message_id", deletedIds);

    if (viewsError) {
      console.warn("Failed to cleanup orphaned views");
    }
  }

  // Optionally, delete very old DELETED records (e.g., > 30 days)
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { error: purgeError } = await supabase
    .from("video_messages")
    .delete()
    .eq("status", "DELETED")
    .lt("updated_at", thirtyDaysAgo.toISOString());

  if (purgeError) {
    console.warn("Failed to purge old deleted records");
  }
}
