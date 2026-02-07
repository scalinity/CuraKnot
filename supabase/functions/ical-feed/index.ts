import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

/**
 * iCal Feed Edge Function
 *
 * Generates iCalendar (.ics) format feeds for calendar subscriptions.
 * Access via GET /functions/v1/ical-feed/{token}
 *
 * Token validation is handled by the validate_ical_token database function.
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface FeedConfig {
  include_tasks: boolean;
  include_shifts: boolean;
  include_appointments: boolean;
  include_handoff_followups: boolean;
  patient_ids: string[] | null;
  show_minimal_details: boolean;
  lookahead_days: number;
}

interface TaskEvent {
  id: string;
  circle_id: string;
  patient_id: string | null;
  title: string;
  description: string | null;
  due_at: string;
  priority: string;
  status: string;
  patients: { display_name: string } | null;
}

interface ShiftEvent {
  id: string;
  circle_id: string;
  patient_id: string | null;
  owner_user_id: string;
  start_time: string;
  end_time: string;
  status: string;
  notes: string | null;
  patients: { display_name: string } | null;
  users: { display_name: string } | null;
}

interface AppointmentEvent {
  id: string;
  circle_id: string;
  patient_id: string | null;
  title: string;
  content_json: string;
  patients: { display_name: string } | null;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only allow GET requests
  if (req.method !== "GET") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }

  try {
    // Extract token from URL path
    const url = new URL(req.url);
    const pathParts = url.pathname.split("/");
    const token = pathParts[pathParts.length - 1];

    if (!token || token === "ical-feed") {
      return new Response("Token required", {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }

    // SECURITY: Validate token format (43 chars base64url - 32 bytes encoded)
    // This prevents injection attacks before database query
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
      return new Response("Invalid token format", {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }

    // Create Supabase client with service role (bypasses RLS for feed generation)
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error(
        "Missing required environment variables: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY",
      );
      return new Response("Internal server error", {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // SECURITY: Validate token using database function
    // Token comparison is done server-side in PostgreSQL which uses constant-time
    // string comparison for equality checks, preventing timing attacks.
    // The regex validation above ensures consistent early rejection of malformed tokens.
    const { data: tokenValidation, error: validationError } =
      await supabase.rpc("validate_ical_token", { p_token: token });

    if (validationError) {
      console.error(
        "Token validation error:",
        validationError.message || "Unknown error",
      );
      return new Response("Internal server error", {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }

    const validation = tokenValidation?.[0];
    if (!validation?.is_valid) {
      const errorMessages: Record<string, string> = {
        TOKEN_NOT_FOUND: "Invalid feed URL",
        TOKEN_REVOKED: "This feed URL has been revoked",
        TOKEN_EXPIRED: "This feed URL has expired",
        RATE_LIMITED: "Too many requests. Please try again later.",
      };
      return new Response(
        errorMessages[validation?.error_code] || "Invalid token",
        {
          status:
            validation?.error_code === "TOKEN_NOT_FOUND"
              ? 404
              : validation?.error_code === "RATE_LIMITED"
                ? 429
                : 403,
          headers: { ...corsHeaders, "Content-Type": "text/plain" },
        },
      );
    }

    const circleId = validation.circle_id;
    const feedConfig: FeedConfig = validation.feed_config;

    // SECURITY: Default to minimal details to prevent PHI leakage in calendar feeds.
    // Only show full details if explicitly opted in.
    if (feedConfig.show_minimal_details === undefined || feedConfig.show_minimal_details === null) {
      feedConfig.show_minimal_details = true;
    }

    // Clamp lookahead_days to prevent resource exhaustion (0-365 days)
    feedConfig.lookahead_days = Math.max(
      0,
      Math.min(365, feedConfig.lookahead_days || 90),
    );

    // SECURITY: Validate patient_ids belong to this circle if specified
    if (feedConfig.patient_ids && feedConfig.patient_ids.length > 0) {
      const { data: validPatients, error: patientError } = await supabase
        .from("patients")
        .select("id")
        .eq("circle_id", circleId)
        .in("id", feedConfig.patient_ids);

      if (patientError) {
        console.error(
          "Patient validation error:",
          patientError.message || "Unknown error",
        );
        return new Response("Internal server error", {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "text/plain" },
        });
      }

      // Filter to only valid patient IDs that belong to this circle
      const validPatientIds = new Set(validPatients?.map((p) => p.id) || []);
      feedConfig.patient_ids = feedConfig.patient_ids.filter((id) =>
        validPatientIds.has(id),
      );

      // Log if any patient IDs were invalid (potential attack or stale data)
      if (feedConfig.patient_ids.length !== validPatientIds.size) {
        console.warn(
          `Feed ${token.substring(0, 8)}... had invalid patient IDs filtered out`,
        );
      }
    }

    // Get circle info for calendar name
    const { data: circle } = await supabase
      .from("circles")
      .select("name")
      .eq("id", circleId)
      .single();

    const calendarName = `CuraKnot - ${circle?.name || "Care Circle"}`;

    // Calculate date range
    const now = new Date();
    const startDate = new Date(now);
    startDate.setDate(startDate.getDate() - 7); // Include 7 days in past
    const endDate = new Date(now);
    endDate.setDate(endDate.getDate() + feedConfig.lookahead_days);

    const events: string[] = [];

    // Fetch tasks
    if (feedConfig.include_tasks) {
      let taskQuery = supabase
        .from("tasks")
        .select(
          "id, circle_id, patient_id, title, description, due_at, priority, status, patients(display_name)",
        )
        .eq("circle_id", circleId)
        .eq("status", "OPEN")
        .not("due_at", "is", null)
        .gte("due_at", startDate.toISOString())
        .lte("due_at", endDate.toISOString());

      if (feedConfig.patient_ids && feedConfig.patient_ids.length > 0) {
        taskQuery = taskQuery.in("patient_id", feedConfig.patient_ids);
      }

      const { data: tasks, error: taskError } = await taskQuery;

      if (taskError) {
        console.error(
          "Task query error:",
          taskError.message || "Unknown error",
        );
        // Continue with empty tasks rather than failing entire feed
      } else if (tasks) {
        for (const task of tasks as unknown as TaskEvent[]) {
          events.push(formatTaskEvent(task, feedConfig.show_minimal_details));
        }
      }
    }

    // Fetch shifts
    if (feedConfig.include_shifts) {
      let shiftQuery = supabase
        .from("care_shifts")
        .select(
          "id, circle_id, patient_id, owner_user_id, start_time, end_time, status, notes, patients(display_name), users:owner_user_id(display_name)",
        )
        .eq("circle_id", circleId)
        .in("status", ["SCHEDULED", "IN_PROGRESS"])
        .gte("start_time", startDate.toISOString())
        .lte("start_time", endDate.toISOString());

      if (feedConfig.patient_ids && feedConfig.patient_ids.length > 0) {
        shiftQuery = shiftQuery.in("patient_id", feedConfig.patient_ids);
      }

      const { data: shifts, error: shiftError } = await shiftQuery;

      if (shiftError) {
        console.error(
          "Shift query error:",
          shiftError.message || "Unknown error",
        );
        // Continue with empty shifts rather than failing entire feed
      } else if (shifts) {
        for (const shift of shifts as unknown as ShiftEvent[]) {
          events.push(formatShiftEvent(shift, feedConfig.show_minimal_details));
        }
      }
    }

    // Fetch appointments (from binder items with type CONTACT that have appointment data)
    if (feedConfig.include_appointments) {
      let appointmentQuery = supabase
        .from("binder_items")
        .select(
          "id, circle_id, patient_id, title, content_json, patients(display_name)",
        )
        .eq("circle_id", circleId)
        .eq("type", "CONTACT")
        .eq("is_active", true);

      if (feedConfig.patient_ids && feedConfig.patient_ids.length > 0) {
        appointmentQuery = appointmentQuery.in(
          "patient_id",
          feedConfig.patient_ids,
        );
      }

      const { data: appointments, error: appointmentError } =
        await appointmentQuery;

      if (appointmentError) {
        console.error(
          "Appointment query error:",
          appointmentError.message || "Unknown error",
        );
        // Continue with empty appointments rather than failing entire feed
      } else if (appointments) {
        for (const appt of appointments as unknown as AppointmentEvent[]) {
          // Parse content_json to check for appointment data
          try {
            const content = JSON.parse(appt.content_json);
            if (content.nextAppointment) {
              const appointmentDate = new Date(content.nextAppointment);
              if (appointmentDate >= startDate && appointmentDate <= endDate) {
                events.push(
                  formatAppointmentEvent(
                    appt,
                    content,
                    feedConfig.show_minimal_details,
                  ),
                );
              }
            }
          } catch (e) {
            // Log parsing errors for debugging but continue processing
            console.warn(
              `Skipping appointment ${appt.id} - invalid JSON: ${e instanceof Error ? e.message : "Unknown error"}`,
            );
          }
        }
      }
    }

    // Generate iCalendar content
    const icalContent = generateICalendar(calendarName, events);

    // Audit log successful feed access (non-blocking)
    console.log(
      JSON.stringify({
        event: "ical_feed_accessed",
        feed_token_id: validation.token_id,
        circle_id: circleId,
        event_count: events.length,
        accessed_at: new Date().toISOString(),
      }),
    );

    // Return iCalendar response
    return new Response(icalContent, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/calendar; charset=utf-8",
        "Content-Disposition": `attachment; filename="curaknot-calendar.ics"`,
        "Cache-Control": "private, max-age=900", // 15 minute cache for calendar apps
      },
    });
  } catch (error) {
    console.error(
      "iCal feed error:",
      error instanceof Error ? error.message : "Unknown error",
    );
    return new Response("Internal server error", {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
});

// MARK: - Event Formatters

function formatTaskEvent(task: TaskEvent, minimal: boolean): string {
  const dueDate = new Date(task.due_at);
  const endDate = new Date(dueDate.getTime() + 30 * 60 * 1000); // 30 minutes

  const title = minimal ? "CuraKnot Event" : `CK: ${task.title}`;

  const description = minimal
    ? ""
    : [
        task.description,
        task.patients?.display_name
          ? `Patient: ${task.patients.display_name}`
          : null,
        `Priority: ${task.priority}`,
      ]
        .filter(Boolean)
        .join("\\n");

  return formatVEvent({
    uid: `task-${task.id}@curaknot.app`,
    summary: title,
    description,
    dtstart: formatDateTime(dueDate),
    dtend: formatDateTime(endDate),
    categories: "TASK",
  });
}

function formatShiftEvent(shift: ShiftEvent, minimal: boolean): string {
  const startDate = new Date(shift.start_time);
  const endDate = new Date(shift.end_time);

  const patientName = shift.patients?.display_name || "Patient";
  const ownerName = shift.users?.display_name || "Caregiver";

  const title = minimal
    ? "CuraKnot Shift"
    : `CK Shift: ${patientName} - ${ownerName}`;

  const description = minimal ? "" : shift.notes || "";

  return formatVEvent({
    uid: `shift-${shift.id}@curaknot.app`,
    summary: title,
    description,
    dtstart: formatDateTime(startDate),
    dtend: formatDateTime(endDate),
    categories: "SHIFT",
  });
}

function formatAppointmentEvent(
  appt: AppointmentEvent,
  content: any,
  minimal: boolean,
): string {
  const appointmentDate = new Date(content.nextAppointment);
  const endDate = new Date(appointmentDate.getTime() + 60 * 60 * 1000); // 1 hour

  const patientName = appt.patients?.display_name || "Patient";
  const providerName = content.name || appt.title;

  const title = minimal
    ? "CuraKnot Appointment"
    : `CK Appt: ${patientName} - ${providerName}`;

  const description = minimal
    ? ""
    : [content.organization, content.address, content.phone, content.notes]
        .filter(Boolean)
        .join("\\n");

  const location = content.address || "";

  return formatVEvent({
    uid: `appt-${appt.id}@curaknot.app`,
    summary: title,
    description,
    dtstart: formatDateTime(appointmentDate),
    dtend: formatDateTime(endDate),
    location,
    categories: "APPOINTMENT",
  });
}

// MARK: - iCalendar Helpers

interface VEventParams {
  uid: string;
  summary: string;
  description?: string;
  dtstart: string;
  dtend: string;
  location?: string;
  categories?: string;
}

function formatVEvent(params: VEventParams): string {
  const lines: string[] = [
    "BEGIN:VEVENT",
    foldLine(`UID:${params.uid}`),
    foldLine(`DTSTAMP:${formatDateTime(new Date())}`),
    foldLine(`DTSTART:${params.dtstart}`),
    foldLine(`DTEND:${params.dtend}`),
    foldLine(`SUMMARY:${escapeICalText(params.summary)}`),
  ];

  if (params.description) {
    lines.push(
      foldLine(
        `DESCRIPTION:${escapeICalText(truncateText(params.description))}`,
      ),
    );
  }

  if (params.location) {
    lines.push(foldLine(`LOCATION:${escapeICalText(params.location)}`));
  }

  if (params.categories) {
    lines.push(foldLine(`CATEGORIES:${params.categories}`));
  }

  lines.push("END:VEVENT");

  return lines.join("\r\n");
}

function generateICalendar(calendarName: string, events: string[]): string {
  const header = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//CuraKnot//Care Calendar//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${escapeICalText(calendarName)}`,
    "X-WR-TIMEZONE:UTC",
    "REFRESH-INTERVAL;VALUE=DURATION:PT15M",
  ].join("\r\n");

  const footer = "END:VCALENDAR";

  return `${header}\r\n${events.join("\r\n")}\r\n${footer}`;
}

function formatDateTime(date: Date): string {
  // Format as iCalendar datetime (UTC)
  return date
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}/, "");
}

function escapeICalText(text: string): string {
  // Escape special characters in iCalendar text per RFC 5545 Section 3.3.11
  // Order matters: backslash must be escaped first
  return text
    .replace(/\\/g, "\\\\") // Escape backslash
    .replace(/;/g, "\\;") // Escape semicolon
    .replace(/,/g, "\\,") // Escape comma
    .replace(/\r\n/g, "\\n") // Convert CRLF to escaped newline
    .replace(/\r/g, "\\n") // Convert standalone CR to escaped newline
    .replace(/\n/g, "\\n"); // Convert LF to escaped newline
}

/**
 * Truncate text to prevent resource exhaustion
 * Calendar apps may struggle with very long descriptions
 */
function truncateText(text: string, maxLength: number = 500): string {
  if (text.length <= maxLength) {
    return text;
  }
  return text.substring(0, maxLength - 3) + "...";
}

/**
 * Fold long lines per RFC 5545 Section 3.1
 * Lines longer than 75 octets must be folded with CRLF + space/tab
 */
function foldLine(line: string): string {
  const maxLength = 75;
  if (line.length <= maxLength) {
    return line;
  }

  const parts: string[] = [];
  let remaining = line;

  // First line can be up to maxLength
  parts.push(remaining.substring(0, maxLength));
  remaining = remaining.substring(maxLength);

  // Continuation lines are prefixed with space, so they can hold maxLength-1 chars
  while (remaining.length > 0) {
    const chunkSize = maxLength - 1; // Account for leading space
    parts.push(" " + remaining.substring(0, chunkSize));
    remaining = remaining.substring(chunkSize);
  }

  return parts.join("\r\n");
}
