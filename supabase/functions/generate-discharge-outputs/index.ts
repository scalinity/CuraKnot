// supabase/functions/generate-discharge-outputs/index.ts
// Generates tasks, handoff, shifts, and binder items from completed discharge wizard

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GenerateOutputsRequest {
  dischargeRecordId: string;
}

interface ChecklistItem {
  id: string;
  discharge_record_id: string;
  template_item_id: string;
  category: string;
  item_text: string;
  sort_order: number;
  is_completed: boolean;
  create_task: boolean;
  task_id: string | null;
  assigned_to: string | null;
  due_date: string | null;
  notes: string | null;
}

interface DischargeRecord {
  id: string;
  circle_id: string;
  patient_id: string;
  created_by: string;
  facility_name: string;
  discharge_date: string;
  admission_date: string | null;
  reason_for_stay: string;
  discharge_type: string;
  status: string;
  current_step: number;
  checklist_state_json: Record<string, unknown>;
  shift_assignments_json: Record<string, string>;
  medication_changes_json: MedicationChange[];
}

interface MedicationChange {
  id: string;
  name: string;
  changeType: string;
  dosage?: string;
  frequency?: string;
  instructions?: string;
  source: string;
}

interface GenerateOutputsResponse {
  tasksCreated: string[];
  handoffId: string | null;
  shiftsCreated: string[];
  binderItemsCreated: string[];
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Track partial success for rollback/retry scenarios
  const createdResources: {
    tasks: string[];
    shifts: string[];
    binderItems: string[];
    handoffId: string | null;
  } = {
    tasks: [],
    shifts: [],
    binderItems: [],
    handoffId: null,
  };

  try {
    // Create Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request
    const rawBody = await req.json();
    const { dischargeRecordId } = validateRequest(rawBody);

    if (!dischargeRecordId) {
      return new Response(
        JSON.stringify({ error: "dischargeRecordId is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch discharge record
    const { data: record, error: recordError } = await supabase
      .from("discharge_records")
      .select("*")
      .eq("id", dischargeRecordId)
      .single();

    if (recordError || !record) {
      return new Response(
        JSON.stringify({ error: "Discharge record not found" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const dischargeRecord = record as DischargeRecord;

    // Validate required fields exist
    if (
      !dischargeRecord.circle_id ||
      !dischargeRecord.patient_id ||
      !dischargeRecord.discharge_date ||
      !dischargeRecord.facility_name
    ) {
      return new Response(
        JSON.stringify({ error: "Discharge record is missing required fields" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate discharge_date is a valid date
    const parsedDischargeDate = new Date(dischargeRecord.discharge_date);
    if (isNaN(parsedDischargeDate.getTime())) {
      return new Response(
        JSON.stringify({ error: "Discharge date is not a valid date" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify user has access to this circle
    const { data: membership, error: membershipError } = await supabase
      .from("circle_members")
      .select("role")
      .eq("circle_id", dischargeRecord.circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (membershipError || !membership) {
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify user has premium subscription (PLUS or FAMILY required for discharge wizard)
    const { data: subscription, error: subscriptionError } = await supabase
      .from("subscriptions")
      .select("plan, status")
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    const allowedPlans = ["PLUS", "FAMILY"];
    if (
      subscriptionError ||
      !subscription ||
      !allowedPlans.includes(subscription.plan)
    ) {
      return new Response(
        JSON.stringify({
          error: "Premium subscription required",
          code: "PREMIUM_REQUIRED",
          requiredPlans: allowedPlans,
        }),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch checklist items
    const { data: checklistItems, error: checklistError } = await supabase
      .from("discharge_checklist_items")
      .select("*")
      .eq("discharge_record_id", dischargeRecordId);

    if (checklistError) {
      throw checklistError;
    }

    const items = (checklistItems || []) as ChecklistItem[];

    // Generate outputs with current date for proper due date calculation
    const now = new Date();

    // 1. Create tasks from checklist items
    const itemsToCreateTasks = items.filter(
      (item) => item.create_task && !item.task_id,
    );

    for (const item of itemsToCreateTasks) {
      const dueDate = item.due_date
        ? item.due_date
        : calculateDueDate(dischargeRecord.discharge_date, item.category, now);

      const sanitizedTitle = sanitizeTaskTitle(item.item_text);

      const { data: task, error: taskError } = await supabase
        .from("tasks")
        .insert({
          circle_id: dischargeRecord.circle_id,
          patient_id: dischargeRecord.patient_id,
          created_by: user.id,
          owner_user_id: item.assigned_to || user.id,
          title: `[Discharge] ${sanitizedTitle}`,
          description: `From discharge checklist for ${sanitizeForMarkdown(dischargeRecord.facility_name)}`,
          due_at: dueDate,
          priority: item.category === "MEDICATIONS" ? "HIGH" : "MED",
          status: "OPEN",
        })
        .select("id")
        .single();

      if (!taskError && task) {
        createdResources.tasks.push(task.id);

        // Update checklist item with task ID
        await supabase
          .from("discharge_checklist_items")
          .update({ task_id: task.id })
          .eq("id", item.id);
      }
    }

    // 2. Create medication binder items
    const medChanges = dischargeRecord.medication_changes_json || [];
    for (const med of medChanges) {
      // Case-insensitive comparison for changeType
      const changeType = (med.changeType || "").toUpperCase();
      if (changeType === "NEW" || changeType === "DOSE_CHANGED") {
        const { data: binderItem, error: binderError } = await supabase
          .from("binder_items")
          .insert({
            circle_id: dischargeRecord.circle_id,
            patient_id: dischargeRecord.patient_id,
            created_by: user.id,
            type: "MED",
            title: sanitizeTaskTitle(med.name),
            item_data_json: JSON.stringify({
              dosage: sanitizeForMarkdown(med.dosage || ""),
              frequency: sanitizeForMarkdown(med.frequency || ""),
              instructions: sanitizeForMarkdown(med.instructions || ""),
              source: "DISCHARGE",
              discharge_record_id: dischargeRecordId,
            }),
          })
          .select("id")
          .single();

        if (!binderError && binderItem) {
          createdResources.binderItems.push(binderItem.id);
        }
      }
    }

    // 3. Create shift assignments
    const shiftAssignments = dischargeRecord.shift_assignments_json || {};
    for (const [dayOffsetStr, memberId] of Object.entries(shiftAssignments)) {
      const dayOffset = parseInt(dayOffsetStr);
      if (isNaN(dayOffset) || dayOffset < 0 || dayOffset > 30) {
        continue; // Skip invalid day offsets
      }

      // Validate memberId is a valid UUID
      const uuidPattern =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidPattern.test(memberId)) {
        continue; // Skip invalid member IDs
      }

      const shiftDate = addDays(
        new Date(dischargeRecord.discharge_date),
        dayOffset,
      );

      const { data: shift, error: shiftError } = await supabase
        .from("care_shifts")
        .insert({
          circle_id: dischargeRecord.circle_id,
          patient_id: dischargeRecord.patient_id,
          user_id: memberId,
          shift_date: shiftDate.toISOString().split("T")[0],
          shift_type: "DAY",
          status: "SCHEDULED",
          notes: `Post-discharge care - Day ${dayOffset + 1}`,
        })
        .select("id")
        .single();

      if (!shiftError && shift) {
        createdResources.shifts.push(shift.id);
      }
    }

    // 4. Create discharge handoff with sanitized content
    const handoffSummary = generateHandoffSummary(
      dischargeRecord,
      items,
      medChanges,
    );

    const { data: handoff, error: handoffError } = await supabase
      .from("handoffs")
      .insert({
        circle_id: dischargeRecord.circle_id,
        patient_id: dischargeRecord.patient_id,
        created_by: user.id,
        type: "OTHER",
        title: `Discharge from ${sanitizeTaskTitle(dischargeRecord.facility_name)}`,
        summary: handoffSummary,
        status: "PUBLISHED",
        published_at: new Date().toISOString(),
        current_revision: 1,
        source: "APP",
      })
      .select("id")
      .single();

    if (!handoffError && handoff) {
      createdResources.handoffId = handoff.id;

      // Create handoff revision
      await supabase.from("handoff_revisions").insert({
        handoff_id: handoff.id,
        revision_number: 1,
        created_by: user.id,
        content_json: JSON.stringify({
          title: `Discharge from ${sanitizeForMarkdown(dischargeRecord.facility_name)}`,
          summary: handoffSummary,
          facility: sanitizeForMarkdown(dischargeRecord.facility_name),
          discharge_date: dischargeRecord.discharge_date,
          reason: sanitizeForMarkdown(dischargeRecord.reason_for_stay),
          discharge_type: dischargeRecord.discharge_type,
          medication_changes: medChanges.map((m) => ({
            name: sanitizeForMarkdown(m.name),
            changeType: m.changeType,
            dosage: sanitizeForMarkdown(m.dosage || ""),
          })),
          tasks_created: createdResources.tasks.length,
          shifts_scheduled: createdResources.shifts.length,
        }),
        change_description: "Initial discharge handoff",
      });
    }

    // 5. Update discharge record as completed
    await supabase
      .from("discharge_records")
      .update({
        status: "COMPLETED",
        completed_at: new Date().toISOString(),
        completed_by: user.id,
        generated_tasks: createdResources.tasks,
        generated_handoff_id: createdResources.handoffId,
        generated_shifts: createdResources.shifts,
        generated_binder_items: createdResources.binderItems,
      })
      .eq("id", dischargeRecordId);

    // Return response
    const response: GenerateOutputsResponse = {
      tasksCreated: createdResources.tasks,
      handoffId: createdResources.handoffId,
      shiftsCreated: createdResources.shifts,
      binderItemsCreated: createdResources.binderItems,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    // Sanitize error logging - never include PHI
    const sanitizedErr = sanitizeError(error as Error);
    console.error("Error generating discharge outputs:", sanitizedErr);

    // Include partial success info in error response for client recovery
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        partialSuccess: {
          tasksCreated: createdResources.tasks.length,
          shiftsCreated: createdResources.shifts.length,
          binderItemsCreated: createdResources.binderItems.length,
          handoffCreated: createdResources.handoffId !== null,
        },
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// Helper functions

// Sanitization helpers
function sanitizeForMarkdown(input: string): string {
  if (!input) return "";

  // Normalize Unicode first to prevent bypass attacks
  const normalized = input.normalize("NFC");

  return (
    normalized
      // IMPORTANT: Ampersand MUST be first to prevent double-encoding
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#x27;")
      .replace(/\//g, "&#x2F;")
      // Remove null bytes which could bypass filters (security measure)
      .split(String.fromCharCode(0))
      .join("")
      .substring(0, 1000)
  ); // Limit length
}

function sanitizeTaskTitle(text: string): string {
  if (!text) return "";
  return text
    .replace(/[\n\r\t]/g, " ")
    .replace(/\s+/g, " ")
    .replace(/</g, "")
    .replace(/>/g, "")
    .substring(0, 200)
    .trim();
}

function sanitizeError(error: Error): Record<string, unknown> {
  // Never include error.message which may contain PHI
  return {
    type: error.name || "UnknownError",
    timestamp: new Date().toISOString(),
  };
}

// Request validation
function validateRequest(body: unknown): { dischargeRecordId: string } {
  if (typeof body !== "object" || body === null) {
    throw new Error("Request body must be an object");
  }

  const req = body as Record<string, unknown>;

  if (typeof req.dischargeRecordId !== "string") {
    throw new Error("dischargeRecordId must be a string");
  }

  if (req.dischargeRecordId.length > 100) {
    throw new Error("dischargeRecordId too long");
  }

  // UUID format validation
  const uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(req.dischargeRecordId)) {
    throw new Error("dischargeRecordId must be a valid UUID");
  }

  return { dischargeRecordId: req.dischargeRecordId };
}

function calculateDueDate(
  dischargeDate: string,
  category: string,
  now: Date,
): string {
  const date = new Date(dischargeDate);
  let dueDate: Date;

  switch (category) {
    case "BEFORE_LEAVING":
      dueDate = date; // Due on discharge day
      break;
    case "MEDICATIONS":
      dueDate = date; // Due on discharge day
      break;
    case "EQUIPMENT":
    case "HOME_PREP":
      // Due day before discharge, but never in the past
      dueDate = addDays(date, -1);
      if (dueDate < now) {
        dueDate = now; // If in the past, use today
      }
      break;
    case "FIRST_WEEK":
      dueDate = addDays(date, 7); // Due within first week
      break;
    default:
      dueDate = addDays(date, 3); // Default 3 days after
  }

  // Final check: never return a past date
  if (dueDate < now) {
    dueDate = now;
  }

  return dueDate.toISOString();
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function generateHandoffSummary(
  record: DischargeRecord,
  items: ChecklistItem[],
  medChanges: MedicationChange[],
): string {
  const lines: string[] = [];

  // Header - sanitize user-provided data
  lines.push(
    `Discharged from ${sanitizeForMarkdown(record.facility_name)} on ${formatDate(record.discharge_date)}.`,
  );

  // Reason - sanitize
  lines.push(
    `\n**Reason for stay:** ${sanitizeForMarkdown(record.reason_for_stay)}`,
  );

  // Medication changes - sanitize each field
  if (medChanges.length > 0) {
    lines.push("\n**Medication Changes:**");
    for (const med of medChanges) {
      const changeLabel = getChangeLabel(med.changeType);
      lines.push(`- ${sanitizeForMarkdown(med.name)}: ${changeLabel}`);
      if (med.dosage) {
        lines.push(`  Dosage: ${sanitizeForMarkdown(med.dosage)}`);
      }
    }
  }

  // Checklist completion
  const completedCount = items.filter((i) => i.is_completed).length;
  lines.push(
    `\n**Checklist:** ${completedCount}/${items.length} items completed`,
  );

  // First week items - sanitize
  const firstWeekItems = items.filter(
    (i) => i.category === "FIRST_WEEK" && !i.is_completed,
  );
  if (firstWeekItems.length > 0) {
    lines.push("\n**First Week Priorities:**");
    for (const item of firstWeekItems.slice(0, 5)) {
      lines.push(`- ${sanitizeForMarkdown(item.item_text)}`);
    }
  }

  return lines.join("\n");
}

function formatDate(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

function getChangeLabel(changeType: string): string {
  switch (changeType) {
    case "NEW":
      return "Started";
    case "STOPPED":
      return "Stopped";
    case "DOSE_CHANGED":
      return "Dose changed";
    case "SCHEDULE_CHANGED":
      return "Schedule changed";
    default:
      return changeType;
  }
}
