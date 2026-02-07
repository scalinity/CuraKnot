/**
 * Event correlation detection
 *
 * Finds temporal correlations between symptom patterns and events:
 * - Medication additions/changes (from binder_items)
 * - Facility transitions (from handoffs with type='FACILITY_UPDATE')
 *
 * Correlation window: ±7 days from first mention
 * Strength: STRONG (≤3 days), POSSIBLE (4-7 days)
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { ConcernCategory, type CorrelatedEvent } from "./types.ts";

const CORRELATION_WINDOW_DAYS = 7;
const STRONG_THRESHOLD_DAYS = 3;

/**
 * Sanitize title for safe inclusion in event descriptions
 * Prevents XSS and removes potentially dangerous characters
 */
function sanitizeTitle(title: string | null): string | null {
  if (!title) return null;
  return title
    .replace(/[<>]/g, "") // Remove HTML tags
    .replace(/['"]/g, "") // Remove quotes
    .replace(/;/g, "") // Remove SQL delimiters
    .replace(/--/g, "") // Remove SQL comments
    .substring(0, 100) // Limit length
    .trim();
}

interface MedicationRecord {
  id: string;
  title: string | null;
  created_at: string;
  updated_at: string;
}

interface FacilityHandoff {
  id: string;
  title: string | null;
  created_at: string;
}

export async function correlateEvents(
  supabase: SupabaseClient,
  patientId: string,
  _circleId: string,
  _category: ConcernCategory,
  firstMentionDate: Date,
): Promise<CorrelatedEvent[]> {
  const correlations: CorrelatedEvent[] = [];

  // Calculate date window
  const windowStart = new Date(firstMentionDate);
  windowStart.setDate(windowStart.getDate() - CORRELATION_WINDOW_DAYS);

  const windowEnd = new Date(firstMentionDate);
  windowEnd.setDate(windowEnd.getDate() + CORRELATION_WINDOW_DAYS);

  // Fetch medication additions/changes
  // Query medications where created_at OR updated_at falls within the window
  const { data: medications, error: medError } = await supabase
    .from("binder_items")
    .select("id, title, created_at, updated_at")
    .eq("patient_id", patientId)
    .eq("type", "MED")
    .or(
      `and(created_at.gte.${windowStart.toISOString()},created_at.lte.${windowEnd.toISOString()}),` +
        `and(updated_at.gte.${windowStart.toISOString()},updated_at.lte.${windowEnd.toISOString()})`,
    );

  if (medError) {
    console.error("Error fetching medications:", medError);
  } else if (medications) {
    for (const med of medications as MedicationRecord[]) {
      const createdDate = new Date(med.created_at);
      const updatedDate = new Date(med.updated_at);

      // Validate dates
      if (isNaN(createdDate.getTime())) {
        // SECURITY: Don't log medication ID (PHI linkage)
        console.warn("Invalid medication date encountered, skipping");
        continue;
      }

      // Check which date is closer to first mention
      const createdDiff = Math.abs(
        Math.floor(
          (firstMentionDate.getTime() - createdDate.getTime()) /
            (24 * 60 * 60 * 1000),
        ),
      );
      const updatedDiff = !isNaN(updatedDate.getTime())
        ? Math.abs(
            Math.floor(
              (firstMentionDate.getTime() - updatedDate.getTime()) /
                (24 * 60 * 60 * 1000),
            ),
          )
        : Infinity;

      // Determine which event to use (prefer updated if it's more recent and closer)
      let medDate: Date;
      let daysDiff: number;
      let eventDescription: string;

      // Sanitize title for safe event description
      const safeTitle = sanitizeTitle(med.title);

      // Check if updated date is valid before comparing
      const updatedDateValid = !isNaN(updatedDate.getTime());
      if (
        updatedDiff < createdDiff &&
        updatedDateValid &&
        updatedDate > createdDate
      ) {
        // Medication was updated (dosage/schedule change)
        medDate = updatedDate;
        daysDiff = updatedDiff;
        eventDescription = safeTitle
          ? `${safeTitle} was changed`
          : "A medication was changed";
      } else {
        // Medication was added
        medDate = createdDate;
        daysDiff = createdDiff;
        eventDescription = safeTitle
          ? `${safeTitle} was added`
          : "A medication was added";
      }

      if (daysDiff <= CORRELATION_WINDOW_DAYS) {
        correlations.push({
          eventType: "MEDICATION",
          eventId: med.id,
          eventDescription,
          eventDate: medDate.toISOString(),
          daysDifference: daysDiff,
          strength: daysDiff <= STRONG_THRESHOLD_DAYS ? "STRONG" : "POSSIBLE",
        });
      }
    }
  }

  // Fetch facility change handoffs
  const { data: facilityHandoffs, error: facilityError } = await supabase
    .from("handoffs")
    .select("id, title, created_at")
    .eq("patient_id", patientId)
    .eq("type", "FACILITY_UPDATE")
    .gte("created_at", windowStart.toISOString())
    .lte("created_at", windowEnd.toISOString());

  if (facilityError) {
    console.error("Error fetching facility handoffs:", facilityError);
  } else if (facilityHandoffs) {
    for (const handoff of facilityHandoffs as FacilityHandoff[]) {
      const handoffDate = new Date(handoff.created_at);
      const daysDiff = Math.abs(
        Math.floor(
          (firstMentionDate.getTime() - handoffDate.getTime()) /
            (24 * 60 * 60 * 1000),
        ),
      );

      // Sanitize title for safe event description
      const safeHandoffTitle = sanitizeTitle(handoff.title);
      correlations.push({
        eventType: "FACILITY_CHANGE",
        eventId: handoff.id,
        eventDescription: safeHandoffTitle || "A facility change occurred",
        eventDate: handoff.created_at,
        daysDifference: daysDiff,
        strength: daysDiff <= STRONG_THRESHOLD_DAYS ? "STRONG" : "POSSIBLE",
      });
    }
  }

  // Sort by strength (STRONG first) then by days difference
  correlations.sort((a, b) => {
    if (a.strength !== b.strength) {
      return a.strength === "STRONG" ? -1 : 1;
    }
    return a.daysDifference - b.daysDifference;
  });

  return correlations;
}

export type { CorrelatedEvent };
