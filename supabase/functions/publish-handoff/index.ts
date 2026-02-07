import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface MedChange {
  name: string;
  change: string;
  details?: string;
  effective?: string;
}

interface NextStep {
  action: string;
  suggested_owner?: string;
  due?: string;
  priority?: string;
}

interface StructuredBrief {
  title: string;
  summary: string;
  status?: {
    mood_energy?: string;
    pain?: number;
    appetite?: string;
    sleep?: string;
    mobility?: string;
    safety_flags?: string[];
  };
  changes?: {
    med_changes?: MedChange[];
    symptom_changes?: { symptom: string; details?: string }[];
    care_plan_changes?: { area: string; details?: string }[];
  };
  questions_for_clinician?: { question: string; priority?: string }[];
  next_steps?: NextStep[];
  keywords?: string[];
}

interface PublishRequest {
  handoff_id: string;
  structured_json: StructuredBrief;
  confirmations?: {
    med_changes_confirmed?: boolean;
    due_dates_confirmed?: boolean;
  };
}

interface PublishResponse {
  success: boolean;
  handoff_id?: string;
  revision?: number;
  published_at?: string;
  notifications_queued?: number;
  error?: {
    code: string;
    message: string;
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

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
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Get current user
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
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
    const body: PublishRequest = await req.json();
    const { handoff_id, structured_json, confirmations } = body;

    if (!handoff_id || !structured_json) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "STRUCT_VALIDATION_FAILED",
            message: "Missing required fields",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate structured brief
    if (!structured_json.title || structured_json.title.length > 80) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "STRUCT_VALIDATION_FAILED",
            message: "Title is required and must be <= 80 characters",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (structured_json.summary && structured_json.summary.length > 600) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "STRUCT_VALIDATION_FAILED",
            message: "Summary must be <= 600 characters",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if med changes require confirmation
    const hasMedChanges =
      structured_json.changes?.med_changes &&
      structured_json.changes.med_changes.length > 0;

    if (hasMedChanges && !confirmations?.med_changes_confirmed) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "STRUCT_REQUIRES_CONFIRMATION",
            message: "Medication changes require explicit confirmation",
          },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get handoff
    const { data: handoff, error: handoffError } = await supabaseService
      .from("handoffs")
      .select("*, circles(id, name)")
      .eq("id", handoff_id)
      .single();

    if (handoffError || !handoff) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "SYNC_SERVER_ERROR", message: "Handoff not found" },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check user is member with contributor role
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
            code: "AUTH_ROLE_FORBIDDEN",
            message: "Insufficient permissions",
          },
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Determine revision number
    const revision =
      handoff.status === "DRAFT" ? 1 : handoff.current_revision + 1;
    const publishedAt = handoff.published_at || new Date().toISOString();

    // Create revision record
    const { error: revisionError } = await supabaseService
      .from("handoff_revisions")
      .insert({
        handoff_id,
        revision,
        structured_json,
        edited_by: user.id,
      });

    if (revisionError) {
      console.error("Failed to create revision:", revisionError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SYNC_SERVER_ERROR",
            message: "Failed to create revision",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update handoff
    const { error: updateError } = await supabaseService
      .from("handoffs")
      .update({
        status: "PUBLISHED",
        published_at: publishedAt,
        current_revision: revision,
        title: structured_json.title,
        summary: structured_json.summary,
        keywords: structured_json.keywords || [],
        updated_at: new Date().toISOString(),
      })
      .eq("id", handoff_id);

    if (updateError) {
      console.error("Failed to update handoff:", updateError);
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SYNC_SERVER_ERROR",
            message: "Failed to publish handoff",
          },
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create tasks from next_steps
    if (structured_json.next_steps && structured_json.next_steps.length > 0) {
      const tasks = structured_json.next_steps.map((step) => ({
        circle_id: handoff.circle_id,
        patient_id: handoff.patient_id,
        handoff_id,
        created_by: user.id,
        owner_user_id: step.suggested_owner || user.id,
        title: step.action,
        due_at: step.due,
        priority: step.priority || "MED",
        status: "OPEN",
      }));

      await supabaseService.from("tasks").insert(tasks);
    }

    // Create audit event
    await supabaseService.from("audit_events").insert({
      circle_id: handoff.circle_id,
      actor_user_id: user.id,
      event_type: revision === 1 ? "HANDOFF_PUBLISHED" : "HANDOFF_REVISED",
      object_type: "handoff",
      object_id: handoff_id,
      metadata_json: { revision },
    });

    // Notify circle members
    const { data: members } = await supabaseService
      .from("circle_members")
      .select("user_id")
      .eq("circle_id", handoff.circle_id)
      .eq("status", "ACTIVE")
      .neq("user_id", user.id);

    let notificationsQueued = 0;
    if (members && members.length > 0) {
      const notifications = members.map((m) => ({
        user_id: m.user_id,
        circle_id: handoff.circle_id,
        notification_type: "HANDOFF_PUBLISHED",
        title: "New Handoff",
        body: structured_json.title,
        data_json: { handoff_id, circle_id: handoff.circle_id },
      }));

      await supabaseService.from("notification_outbox").insert(notifications);
      notificationsQueued = notifications.length;
    }

    const response: PublishResponse = {
      success: true,
      handoff_id,
      revision,
      published_at: publishedAt,
      notifications_queued: notificationsQueued,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
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
