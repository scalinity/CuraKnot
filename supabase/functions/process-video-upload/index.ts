import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Validate UUID format
function isValidUUID(str: string): boolean {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

// Validate storage key format (prevent path traversal)
function isValidStorageKey(key: string): boolean {
  // Must not contain path traversal
  if (key.includes("..") || key.includes("//") || key.startsWith("/")) {
    return false;
  }
  // Must match expected pattern: circleId/videoId.mp4
  const storageKeyRegex = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\.mp4$/i;
  return storageKeyRegex.test(key);
}

// Sanitize caption (remove potential injection and XSS)
// IMPORTANT: First decode any pre-encoded entities, then sanitize to prevent XSS bypass
function sanitizeCaption(caption: string | undefined): string | null {
  if (!caption) return null;
  
  // Step 1: Decode any pre-encoded HTML entities to normalize input
  // This prevents XSS bypass via pre-encoded entities like &lt;script&gt;
  let decoded = caption
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&#x2F;/g, '/')
    .replace(/&#47;/g, '/');
  
  // Step 2: Limit length and strip HTML tags
  decoded = decoded
    .slice(0, 500)
    .replace(/<[^>]*>/g, ''); // Strip HTML tags
  
  // Step 3: Re-encode special characters for safe display
  const sanitized = decoded
    .replace(/&/g, '&amp;')  // Must be first to not double-encode
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
    .trim();
  
  return sanitized || null;
}

// Magic bytes validation for video files
const VIDEO_MAGIC_BYTES: { [key: string]: number[] } = {
  // MP4 / MOV / QuickTime (ftyp box)
  mp4_ftyp: [0x00, 0x00, 0x00], // First 3 bytes vary, check for 'ftyp' at offset 4
  // MP4 specific brands
  mp4_isom: [0x69, 0x73, 0x6F, 0x6D], // 'isom'
  mp4_mp41: [0x6D, 0x70, 0x34, 0x31], // 'mp41'
  mp4_mp42: [0x6D, 0x70, 0x34, 0x32], // 'mp42'
  mp4_avc1: [0x61, 0x76, 0x63, 0x31], // 'avc1'
  mov_qt: [0x71, 0x74, 0x20, 0x20],   // 'qt  ' (QuickTime)
  // HEVC/H.265 brands
  hevc_hvc1: [0x68, 0x76, 0x63, 0x31], // 'hvc1'
  hevc_hev1: [0x68, 0x65, 0x76, 0x31], // 'hev1'
};

async function validateVideoMagicBytes(
  supabase: ReturnType<typeof createClient>,
  storageKey: string
): Promise<{ valid: boolean; error?: string }> {
  try {
    // Get a signed URL for the file (short-lived for security)
    const { data: signedData, error: signError } = await supabase.storage
      .from("video-messages")
      .createSignedUrl(storageKey, 60); // 60 seconds expiry

    if (signError || !signedData?.signedUrl) {
      return { valid: false, error: "Failed to access file for validation" };
    }

    // Use Range header to download ONLY the first 32 bytes (DoS prevention)
    const response = await fetch(signedData.signedUrl, {
      method: "GET",
      headers: {
        "Range": "bytes=0-31",
      },
    });

    if (!response.ok && response.status !== 206) {
      return { valid: false, error: "Failed to read file for validation" };
    }

    // Read the partial content
    const buffer = await response.arrayBuffer();
    const bytes = new Uint8Array(buffer);

    // Validate we got enough bytes
    if (bytes.length < 12) {
      return { valid: false, error: "File too small to be a valid video" };
    }

    // Check for 'ftyp' at offset 4 (standard for MP4/MOV containers)
    const ftypSignature = [0x66, 0x74, 0x79, 0x70]; // 'ftyp'
    const hasFtyp = ftypSignature.every((byte, i) => bytes[4 + i] === byte);

    if (!hasFtyp) {
      return { valid: false, error: "Invalid video format: not an MP4/MOV container" };
    }

    // Check brand at offset 8 (4 bytes)
    const brand = Array.from(bytes.slice(8, 12));
    const validBrands = [
      VIDEO_MAGIC_BYTES.mp4_isom,
      VIDEO_MAGIC_BYTES.mp4_mp41,
      VIDEO_MAGIC_BYTES.mp4_mp42,
      VIDEO_MAGIC_BYTES.mp4_avc1,
      VIDEO_MAGIC_BYTES.mov_qt,
      VIDEO_MAGIC_BYTES.hevc_hvc1,
      VIDEO_MAGIC_BYTES.hevc_hev1,
    ];

    const isValidBrand = validBrands.some(validBrand =>
      validBrand.every((byte, i) => brand[i] === byte)
    );

    // Also accept common brands that start with 'M' (M4V, etc.)
    const isM4Brand = bytes[8] === 0x4D; // 'M'

    if (!isValidBrand && !isM4Brand) {
      // Log the brand for debugging but don't expose to user
      console.warn("Unknown video brand:", String.fromCharCode(...brand));
      // Be lenient - if it has ftyp, it's likely a valid video
    }

    return { valid: true };
  } catch (err) {
    console.error("Magic bytes validation error:", err);
    return { valid: false, error: "File validation failed" };
  }
}

interface ProcessVideoRequest {
  videoId: string;
  circleId: string;
  patientId: string;
  storageKey: string;
  caption?: string;
  durationSeconds: number;
  fileSizeBytes: number;
  retentionDays: number;
}

interface ProcessVideoResponse {
  success: boolean;
  videoMessageId?: string;
  thumbnailKey?: string;
  error?: {
    code: string;
    message: string;
  };
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Extract client info for audit
  const clientIP = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null;
  const userAgent = req.headers.get("user-agent") || null;

  try {
    // Initialize Supabase client with service role for admin operations
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(
        {
          success: false,
          error: {
            code: "UNAUTHORIZED",
            message: "Missing Authorization header",
          },
        },
        401,
      );
    }

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authHeader } },
      },
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      return jsonResponse(
        {
          success: false,
          error: { code: "UNAUTHORIZED", message: "Invalid token" },
        },
        401,
      );
    }

    // Rate limiting check via RPC
    const { data: rateLimitResult, error: rateLimitError } = await supabaseAdmin.rpc(
      "check_rate_limit",
      {
        p_user_id: user.id,
      },
    );

    if (rateLimitError) {
      console.error("Rate limit check error:", rateLimitError.message);
      return jsonResponse(
        {
          success: false,
          error: { code: "RATE_LIMITED", message: "Too many uploads. Please try again later." },
        },
        429,
      );
    }

    if (!rateLimitResult?.allowed) {
      return jsonResponse(
        {
          success: false,
          error: { code: "RATE_LIMITED", message: "Too many uploads. Please try again later." },
        },
        429,
      );
    }

    // Parse request body
    const body: ProcessVideoRequest = await req.json();

    // Validate required fields exist
    if (
      !body.videoId ||
      !body.circleId ||
      !body.patientId ||
      !body.storageKey
    ) {
      return jsonResponse(
        {
          success: false,
          error: {
            code: "INVALID_REQUEST",
            message: "Missing required fields",
          },
        },
        400,
      );
    }

    // Validate UUID formats (prevent SQL injection)
    if (!isValidUUID(body.videoId)) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_REQUEST", message: "Invalid videoId format" },
        },
        400,
      );
    }

    if (!isValidUUID(body.circleId)) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_REQUEST", message: "Invalid circleId format" },
        },
        400,
      );
    }

    if (!isValidUUID(body.patientId)) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_REQUEST", message: "Invalid patientId format" },
        },
        400,
      );
    }

    // Validate storage key format (prevent path traversal)
    if (!isValidStorageKey(body.storageKey)) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_REQUEST", message: "Invalid storageKey format" },
        },
        400,
      );
    }

    // Validate numeric fields
    if (typeof body.durationSeconds !== "number" || body.durationSeconds <= 0 || body.durationSeconds > 120) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_REQUEST", message: "Invalid duration" },
        },
        400,
      );
    }

    if (typeof body.fileSizeBytes !== "number" || body.fileSizeBytes <= 0 || body.fileSizeBytes > 100 * 1024 * 1024) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_REQUEST", message: "Invalid file size" },
        },
        400,
      );
    }

    if (typeof body.retentionDays !== "number" || body.retentionDays <= 0 || body.retentionDays > 365) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_REQUEST", message: "Invalid retention days" },
        },
        400,
      );
    }

    // Sanitize caption
    const sanitizedCaption = sanitizeCaption(body.caption);

    // Verify user is a member of the circle using parameterized query
    const { data: membership, error: memberError } = await supabaseAdmin
      .from("circle_members")
      .select("id, role")
      .eq("circle_id", body.circleId)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (memberError || !membership) {
      return jsonResponse(
        {
          success: false,
          error: { code: "FORBIDDEN", message: "Not a member of this circle" },
        },
        403,
      );
    }

    // Verify the reservation exists and belongs to this user (PENDING record from reserve_video_quota)
    const { data: reservation, error: reservationError } = await supabaseAdmin
      .from("video_messages")
      .select("id, created_by, circle_id, patient_id, status, quota_reserved_bytes")
      .eq("id", body.videoId)
      .eq("created_by", user.id)
      .eq("status", "PENDING")
      .single();

    if (reservationError || !reservation) {
      return jsonResponse(
        {
          success: false,
          error: { 
            code: "INVALID_RESERVATION", 
            message: "Reservation not found or expired. Please try uploading again." 
          },
        },
        400,
      );
    }

    // Verify the circle matches the reservation
    if (reservation.circle_id !== body.circleId) {
      return jsonResponse(
        {
          success: false,
          error: { 
            code: "INVALID_RESERVATION", 
            message: "Reservation circle mismatch" 
          },
        },
        400,
      );
    }

    // Validate magic bytes of uploaded file
    const magicBytesResult = await validateVideoMagicBytes(supabaseAdmin, body.storageKey);
    if (!magicBytesResult.valid) {
      // Delete the invalid file
      await supabaseAdmin.storage.from("video-messages").remove([body.storageKey]);
      
      // Release the quota reservation
      await supabaseAdmin.rpc("finalize_video_quota", {
        p_reservation_id: body.videoId,
        p_user_id: user.id,
        p_finalize: false,
      });
      
      return jsonResponse(
        {
          success: false,
          error: {
            code: "INVALID_FILE",
            message: magicBytesResult.error || "Invalid video file format",
          },
        },
        400,
      );
    }

    // Generate thumbnail key (sanitized based on validated storage key)
    const thumbnailKey = body.storageKey.replace(".mp4", "_thumb.jpg");

    // Try to generate thumbnail (best-effort)
    let thumbnailGenerated = false;
    try {
      thumbnailGenerated = await generateThumbnail(
        supabaseAdmin,
        body.storageKey,
        thumbnailKey,
      );
    } catch (thumbError) {
      console.warn("Thumbnail generation failed (non-fatal)");
    }

    // Finalize the reservation (update PENDING record to ACTIVE with actual data)
    const { data: finalizeResult, error: finalizeError } = await supabaseAdmin.rpc(
      "finalize_video_quota",
      {
        p_reservation_id: body.videoId,
        p_user_id: user.id,
        p_finalize: true,
        p_actual_bytes: body.fileSizeBytes,
        p_storage_key: body.storageKey,
      },
    );

    if (finalizeError) {
      console.error("Finalize error:", finalizeError.message);
      
      // Clean up storage on failure
      await supabaseAdmin.storage
        .from("video-messages")
        .remove([body.storageKey]);

      return jsonResponse(
        {
          success: false,
          error: { code: "FINALIZE_FAILED", message: "Failed to confirm upload" },
        },
        500,
      );
    }

    // Calculate expiration date
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + body.retentionDays);

    // Update the video record with remaining fields (thumbnail, caption, expiry)
    const { error: updateError } = await supabaseAdmin
      .from("video_messages")
      .update({
        thumbnail_key: thumbnailGenerated ? thumbnailKey : null,
        caption: sanitizedCaption,
        duration_seconds: body.durationSeconds,
        expires_at: expiresAt.toISOString(),
        processed_at: new Date().toISOString(),
      })
      .eq("id", body.videoId);

    if (updateError) {
      console.error("Update error:", updateError.message);
      // Non-fatal: the video is already active, just missing some metadata
    }

    // Get the final video record
    const { data: finalVideo, error: fetchError } = await supabaseAdmin
      .from("video_messages")
      .select()
      .eq("id", body.videoId)
      .single();

    // Send notification to circle members (async, don't block response)
    notifyCircleMembers(
      supabaseAdmin,
      body.circleId,
      user.id,
      body.patientId,
      body.videoId,
    ).catch((err) => console.error("Notification error"));

    // Refresh materialized view for quota tracking (async)
    supabaseAdmin
      .rpc("refresh_video_stats")
      .then(() => console.log("Video stats refreshed"))
      .catch(() => console.warn("Failed to refresh video stats"));

    // Log video creation for audit
    await supabaseAdmin.rpc("log_video_action", {
      p_video_id: body.videoId,
      p_user_id: user.id,
      p_action: "CREATE",
      p_details: {
        circle_id: body.circleId,
        patient_id: body.patientId,
        file_size_bytes: body.fileSizeBytes,
        duration_seconds: body.durationSeconds,
      },
      p_ip_address: clientIP,
      p_user_agent: userAgent,
    }).catch((err: Error) => {
      // Non-fatal: log but don't fail the request
      console.warn("Audit logging failed:", err.message);
    });

    return jsonResponse({
      success: true,
      videoMessageId: body.videoId,
      thumbnailKey: thumbnailGenerated ? thumbnailKey : null,
    });
  } catch (error) {
    console.error("Process video error");
    return jsonResponse(
      {
        success: false,
        error: { code: "INTERNAL_ERROR", message: "An unexpected error occurred" },
      },
      500,
    );
  }
});

// Helper function for JSON responses
function jsonResponse(data: ProcessVideoResponse, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Generate thumbnail from video (placeholder implementation)
async function generateThumbnail(
  _supabase: ReturnType<typeof createClient>,
  _videoStorageKey: string,
  _thumbnailStorageKey: string,
): Promise<boolean> {
  // In production, you would:
  // 1. Download video from storage
  // 2. Use FFmpeg (via Deno) or a video processing API to extract first frame
  // 3. Resize to 320x180
  // 4. Upload as JPEG to storage

  // For MVP, we'll skip thumbnail generation and let the iOS app
  // generate thumbnails client-side using AVAssetImageGenerator
  // The app will cache thumbnails locally

  // Return false to indicate no thumbnail was generated server-side
  // The iOS app will handle this gracefully
  return false;
}

// Send push notifications to circle members
async function notifyCircleMembers(
  supabase: ReturnType<typeof createClient>,
  circleId: string,
  senderId: string,
  patientId: string,
  videoId: string,
): Promise<void> {
  // Get circle info using parameterized query
  const { data: circle } = await supabase
    .from("circles")
    .select("name")
    .eq("id", circleId)
    .single();

  // Get sender info
  const { data: sender } = await supabase
    .from("users")
    .select("display_name")
    .eq("id", senderId)
    .single();

  // Get patient info
  const { data: patient } = await supabase
    .from("patients")
    .select("name")
    .eq("id", patientId)
    .single();

  // Get all active circle members except sender
  const { data: members } = await supabase
    .from("circle_members")
    .select("user_id")
    .eq("circle_id", circleId)
    .eq("status", "ACTIVE")
    .neq("user_id", senderId);

  if (!members || members.length === 0) return;

  const memberIds = members.map((m: { user_id: string }) => m.user_id);

  // Get device tokens
  const { data: tokens } = await supabase
    .from("push_tokens")
    .select("token, platform")
    .in("user_id", memberIds);

  if (!tokens || tokens.length === 0) return;

  // Create notification payload (no PHI in logs)
  const title = `New Video from ${sender?.display_name || "Someone"}`;
  const body = `A video message for ${patient?.name || "your loved one"} in ${circle?.name || "your circle"}`;

  // Log notification count only (no PHI)
  console.log("Sending push notifications:", tokens.length);

  // In production, integrate with APNs/FCM here
  // The NotificationManager on iOS handles displaying local notifications
}
