import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface TranscribeResponse {
  success: boolean;
  job_id?: string;
  status?: string;
  transcript?: string;
  duration_ms?: number;
  language?: string;
  error?: {
    code: string;
    message: string;
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

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

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // GET request - poll job status
    if (req.method === "GET") {
      const url = new URL(req.url);
      const jobId = url.pathname.split("/").pop();

      if (!jobId) {
        return new Response(
          JSON.stringify({
            success: false,
            error: { code: "ASR_JOB_NOT_FOUND", message: "Job ID required" },
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Validate user authentication
      const {
        data: { user: getUser },
        error: getUserError,
      } = await supabaseUser.auth.getUser();

      if (getUserError || !getUser) {
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

      // Look up handoff by ID (job_id = handoff_id in this implementation)
      const { data: handoff, error } = await supabaseService
        .from("handoffs")
        .select("id, raw_transcript, status, audio_storage_key, circle_id")
        .eq("id", jobId)
        .single();

      if (error || !handoff) {
        return new Response(
          JSON.stringify({
            success: false,
            error: { code: "ASR_JOB_NOT_FOUND", message: "Job not found" },
          }),
          {
            status: 404,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Verify user is a member of the handoff's circle
      const { data: getMembership } = await supabaseService
        .from("circle_members")
        .select("role")
        .eq("circle_id", handoff.circle_id)
        .eq("user_id", getUser.id)
        .eq("status", "ACTIVE")
        .single();

      if (!getMembership) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "AUTH_NOT_MEMBER",
              message: "Not a member of this circle",
            },
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Check if transcription is complete
      if (handoff.raw_transcript) {
        return new Response(
          JSON.stringify({
            success: true,
            job_id: jobId,
            status: "COMPLETED",
            transcript: handoff.raw_transcript,
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          job_id: jobId,
          status: "RUNNING",
          progress: 0.5,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // POST request - start transcription
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

    // Parse multipart form data
    const formData = await req.formData();
    const handoffId = formData.get("handoff_id") as string;
    const audioFile = formData.get("audio") as File;

    if (!handoffId || !audioFile) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "UPLOAD_UNSUPPORTED_MIME",
            message: "Missing handoff_id or audio file",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check file size (50MB limit)
    if (audioFile.size > 50 * 1024 * 1024) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "UPLOAD_TOO_LARGE",
            message: "File exceeds 50MB limit",
          },
        }),
        {
          status: 413,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // SECURITY: Validate audio file magic bytes before upload
    // Prevents uploading non-audio files that could exploit downstream processors
    const audioBuffer = await audioFile.arrayBuffer();
    const header = new Uint8Array(audioBuffer.slice(0, 12));
    const isM4A =
      header.length >= 8 &&
      header[4] === 0x66 &&
      header[5] === 0x74 &&
      header[6] === 0x79 &&
      header[7] === 0x70; // "ftyp" at offset 4
    const isMP3ID3 =
      header.length >= 3 &&
      header[0] === 0x49 &&
      header[1] === 0x44 &&
      header[2] === 0x33; // "ID3"
    const isMP3Sync =
      header.length >= 2 && header[0] === 0xff && (header[1] & 0xe0) === 0xe0; // MPEG sync word
    const isAAC =
      header.length >= 2 &&
      header[0] === 0xff &&
      (header[1] === 0xf1 || header[1] === 0xf9); // ADTS
    const isWAV =
      header.length >= 4 &&
      header[0] === 0x52 &&
      header[1] === 0x49 &&
      header[2] === 0x46 &&
      header[3] === 0x46; // "RIFF"
    const isOGG =
      header.length >= 4 &&
      header[0] === 0x4f &&
      header[1] === 0x67 &&
      header[2] === 0x67 &&
      header[3] === 0x53; // "OggS"

    if (!isM4A && !isMP3ID3 && !isMP3Sync && !isAAC && !isWAV && !isOGG) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "UPLOAD_UNSUPPORTED_MIME",
            message:
              "Unsupported audio format. Accepted: M4A, MP3, AAC, WAV, OGG",
          },
        }),
        {
          status: 415,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify handoff exists and user has access
    const { data: handoff, error: handoffError } = await supabaseService
      .from("handoffs")
      .select("id, circle_id, created_by")
      .eq("id", handoffId)
      .single();

    if (handoffError || !handoff) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_NOT_MEMBER", message: "Handoff not found" },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify membership
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", handoff.circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership || membership.role === "VIEWER") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_NOT_MEMBER",
            message: "Insufficient permissions",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Upload audio to storage (audioBuffer already read during magic bytes validation)
    const storageKey = `${handoff.circle_id}/${handoffId}/${Date.now()}.m4a`;

    const { error: uploadError } = await supabaseService.storage
      .from("handoff-audio")
      .upload(storageKey, audioBuffer, {
        contentType: audioFile.type || "audio/mp4",
        upsert: true,
      });

    if (uploadError) {
      console.error("Upload error:", uploadError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "UPLOAD_NETWORK_ERROR",
            message: "Failed to upload audio",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update handoff with storage key
    await supabaseService
      .from("handoffs")
      .update({ audio_storage_key: storageKey })
      .eq("id", handoffId);

    // Transcribe audio using OpenAI gpt-4o-mini-transcribe
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    let transcript = "";

    if (openaiApiKey) {
      try {
        // Create form data for OpenAI Whisper API
        const formDataForOpenAI = new FormData();
        formDataForOpenAI.append(
          "file",
          new Blob([audioBuffer], { type: audioFile.type || "audio/mp4" }),
          "audio.m4a",
        );
        formDataForOpenAI.append("model", "gpt-4o-mini-transcribe");
        formDataForOpenAI.append("response_format", "text");

        const openaiResponse = await fetch(
          "https://api.openai.com/v1/audio/transcriptions",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${openaiApiKey}`,
            },
            body: formDataForOpenAI,
          },
        );

        if (!openaiResponse.ok) {
          const errorText = await openaiResponse.text();
          console.error("OpenAI transcription error:", errorText);
          throw new Error(`OpenAI API error: ${openaiResponse.status}`);
        }

        transcript = await openaiResponse.text();
      } catch (transcriptionError) {
        console.error("Transcription failed:", transcriptionError);
        // Store placeholder if transcription fails
        transcript = "[Transcription failed - please retry]";
      }
    } else {
      // No API key configured - store placeholder
      console.warn("OPENAI_API_KEY not configured");
      transcript = "[Transcription pending - API key not configured]";
    }

    // Update handoff with transcript
    await supabaseService
      .from("handoffs")
      .update({ raw_transcript: transcript })
      .eq("id", handoffId);

    const response: TranscribeResponse = {
      success: true,
      job_id: handoffId,
      status: transcript.startsWith("[") ? "PENDING" : "COMPLETED",
      transcript: transcript.startsWith("[") ? undefined : transcript,
    };

    return new Response(JSON.stringify(response), {
      status: transcript.startsWith("[") ? 202 : 200,
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
