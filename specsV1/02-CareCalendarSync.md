# Feature Spec 02 — Care Calendar Sync (Google/Apple/Outlook)

> Date: 2026-02-05 | Priority: HIGH | Phase: 1 (Foundation)
> Differentiator: Table-stakes integration that competitors lack

---

## 1. Problem Statement

Caregivers maintain multiple calendars: personal, work, and now care-related events scattered across CuraKnot tasks, appointments, and shifts. Without integration, they must manually duplicate entries or risk missing critical events. This cognitive overhead leads to missed appointments, forgotten tasks, and unnecessary stress.

Calendar sync is a baseline expectation for productivity apps in 2026. Its absence is a churn driver; its presence reduces friction and increases daily engagement.

---

## 2. Differentiation and Moat

- **Expected feature** — absence is a competitive disadvantage
- **Reduces double-entry** — single source of truth
- **Increases visibility** — care events appear alongside life events
- **Enables family coordination** — shared calendar subscribers see care events
- **Premium lever:** Multi-calendar sync, bi-directional sync, custom calendar creation

---

## 3. Goals

- [ ] G1: One-way sync of CuraKnot events to external calendars (Apple Calendar, Google Calendar, Outlook)
- [ ] G2: Sync task due dates as calendar events
- [ ] G3: Sync shift schedules as calendar blocks
- [ ] G4: Sync appointments from binder contacts as events
- [ ] G5: Support bi-directional sync for appointments (changes in external calendar update CuraKnot)
- [ ] G6: Generate subscribable iCal feed URL per circle/patient

---

## 4. Non-Goals

- [ ] NG1: No real-time sync (polling/webhook intervals acceptable)
- [ ] NG2: No full calendar replacement (CuraKnot is not a calendar app)
- [ ] NG3: No complex recurrence rule editing in CuraKnot
- [ ] NG4: No calendar sharing permissions management
- [ ] NG5: No support for non-standard calendar providers (Phase 2)

---

## 5. UX Flow

### 5.1 Initial Setup

1. **Entry:** Circle Settings → Calendar Sync
2. **Options:**
   - Connect Apple Calendar
   - Connect Google Calendar
   - Connect Outlook Calendar
   - Generate iCal feed URL (for any calendar app)
3. **OAuth flow** for Google/Outlook; native EventKit for Apple
4. **Select target calendar** or create new "CuraKnot - [Circle Name]" calendar
5. **Configure sync options:**
   - Sync tasks (due dates)
   - Sync shifts
   - Sync appointments
   - Include reminders
6. **Confirm:** "Calendar connected. Events will sync within 15 minutes."

### 5.2 Ongoing Sync

- Background sync every 15 minutes (configurable)
- Manual "Sync Now" button in settings
- Visual indicator showing last sync time
- Conflict resolution for bi-directional changes

### 5.3 iCal Feed

1. Generate unique, secret URL per user per circle
2. User adds URL to any calendar app
3. Read-only subscription (changes in CuraKnot appear in calendar)
4. URL revocable from settings

---

## 6. Functional Requirements

### 6.1 Event Types Synced

| CuraKnot Entity      | Calendar Event            | Details                                    |
| -------------------- | ------------------------- | ------------------------------------------ |
| Task with due date   | Event at due time         | Title: "CK: [task title]", 30min duration  |
| Task reminder        | Calendar reminder         | Attached to task event                     |
| Care shift           | All-day or timed block    | Title: "CK Shift: [patient] - [owner]"     |
| Appointment (binder) | Event at appointment time | Title: "CK Appt: [patient] - [provider]"   |
| Handoff follow-up    | Event                     | Title: "CK Follow-up: [brief description]" |

### 6.2 Sync Behavior

- [ ] Create: New CuraKnot event → Create calendar event
- [ ] Update: Modified CuraKnot event → Update calendar event
- [ ] Delete: Deleted/completed task → Remove calendar event (configurable)
- [ ] Bi-directional: Calendar event time change → Update CuraKnot (appointments only)

### 6.3 Calendar Providers

| Provider          | Auth Method       | API                    | Bi-directional |
| ----------------- | ----------------- | ---------------------- | -------------- |
| Apple Calendar    | EventKit (native) | Local API              | Yes            |
| Google Calendar   | OAuth 2.0         | Google Calendar API v3 | Yes            |
| Microsoft Outlook | OAuth 2.0         | Microsoft Graph API    | Yes            |
| iCal Feed         | None (URL token)  | Static .ics file       | No (read-only) |

### 6.4 Conflict Resolution

- [ ] CuraKnot is source of truth for task/shift data
- [ ] External calendar is source of truth for appointment times (user may reschedule)
- [ ] Conflicts logged; user notified via in-app alert
- [ ] "Last write wins" with 5-minute grace period for rapid edits

### 6.5 Privacy Controls

- [ ] Per-event-type toggle (sync tasks but not shifts)
- [ ] Per-patient toggle (sync events for Mom but not Dad)
- [ ] Option to show minimal details ("CuraKnot Event" vs full title)
- [ ] iCal URL regeneration (revokes old URL)

---

## 7. Data Model

### 7.1 Calendar Connections

```sql
CREATE TABLE IF NOT EXISTS calendar_connections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    provider text NOT NULL,  -- APPLE | GOOGLE | OUTLOOK | ICAL_FEED
    provider_account_id text,  -- External account identifier
    calendar_id text,  -- Specific calendar within provider
    calendar_name text,
    access_token_encrypted text,  -- Encrypted OAuth token
    refresh_token_encrypted text,
    token_expires_at timestamptz,
    sync_config_json jsonb NOT NULL DEFAULT '{
        "syncTasks": true,
        "syncShifts": true,
        "syncAppointments": true,
        "includeReminders": true,
        "showMinimalDetails": false,
        "syncIntervalMinutes": 15
    }'::jsonb,
    last_sync_at timestamptz,
    last_sync_status text,  -- SUCCESS | FAILED | PARTIAL
    last_sync_error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, circle_id, provider)
);
```

### 7.2 Synced Events Mapping

```sql
CREATE TABLE IF NOT EXISTS calendar_event_mappings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id uuid NOT NULL REFERENCES calendar_connections(id) ON DELETE CASCADE,
    curaknot_entity_type text NOT NULL,  -- TASK | SHIFT | APPOINTMENT
    curaknot_entity_id uuid NOT NULL,
    external_event_id text NOT NULL,  -- Provider's event ID
    external_event_etag text,  -- For change detection
    last_synced_at timestamptz NOT NULL DEFAULT now(),
    sync_direction text NOT NULL DEFAULT 'OUTBOUND',  -- OUTBOUND | INBOUND | BIDIRECTIONAL
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(connection_id, curaknot_entity_type, curaknot_entity_id)
);
```

### 7.3 iCal Feed Tokens

```sql
CREATE TABLE IF NOT EXISTS ical_feed_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    token text NOT NULL UNIQUE,  -- Secret URL token
    feed_config_json jsonb NOT NULL DEFAULT '{
        "includeTasks": true,
        "includeShifts": true,
        "includeAppointments": true,
        "patientIds": null
    }'::jsonb,
    last_accessed_at timestamptz,
    access_count int NOT NULL DEFAULT 0,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, circle_id)
);
```

---

## 8. RLS & Security

- [ ] calendar_connections: Users can only access their own connections
- [ ] calendar_event_mappings: Access via connection ownership
- [ ] ical_feed_tokens: Users can only manage their own tokens
- [ ] OAuth tokens encrypted at rest using Supabase Vault
- [ ] iCal feed URLs are unguessable (cryptographic token)
- [ ] Feed access logged but not authenticated (standard iCal behavior)

---

## 9. Edge Functions

### 9.1 generate-ical-feed

```typescript
// GET /functions/v1/ical-feed/{token}
// Returns .ics file for calendar subscription

interface ICalFeedRequest {
  token: string; // From URL path
}

// Response: text/calendar content type
// VCALENDAR with VEVENT entries
```

### 9.2 calendar-webhook (Google/Outlook)

```typescript
// POST /functions/v1/calendar-webhook
// Receives push notifications for calendar changes

interface CalendarWebhook {
  provider: "GOOGLE" | "OUTLOOK";
  resourceId: string;
  changeType: string;
  // Provider-specific payload
}
```

### 9.3 sync-calendar (Cron)

```typescript
// Runs every 15 minutes
// Processes all active calendar connections
// Handles token refresh, event sync, conflict detection
```

---

## 10. iOS Implementation Notes

### 10.1 Apple Calendar (EventKit)

```swift
import EventKit

class AppleCalendarManager {
    private let eventStore = EKEventStore()

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func syncEvent(task: CareTask, to calendar: EKCalendar) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = "CK: \(task.title)"
        event.startDate = task.dueAt
        event.endDate = task.dueAt.addingTimeInterval(30 * 60)
        event.calendar = calendar
        event.notes = "Created by CuraKnot"

        try eventStore.save(event, span: .thisEvent)
    }
}
```

### 10.2 Google/Outlook OAuth

- Use ASWebAuthenticationSession for OAuth flow
- Store tokens in Keychain (encrypted)
- Implement token refresh logic
- Handle revocation gracefully

### 10.3 Background Sync

- Use BGAppRefreshTask for periodic sync
- Respect user's battery/data preferences
- Sync on app foreground after threshold

### 10.4 UI Components

- CalendarConnectionsView: List of connected calendars
- CalendarSetupSheet: OAuth flow and calendar selection
- SyncStatusBadge: Shows last sync time and status
- ConflictResolutionAlert: Handles bi-directional conflicts

---

## 11. Metrics

| Metric                   | Target                 | Measurement                              |
| ------------------------ | ---------------------- | ---------------------------------------- |
| Calendar connection rate | 40% of active users    | Users with ≥1 calendar connected         |
| Sync success rate        | 99%                    | Successful syncs / attempted syncs       |
| Bi-directional adoption  | 60% of connected users | Users with bi-directional enabled        |
| iCal feed adoption       | 20% of users           | Users with active iCal feed              |
| Churn reduction          | -15%                   | Compare connected vs non-connected users |

---

## 12. Risks & Mitigations

| Risk                   | Impact | Mitigation                                  |
| ---------------------- | ------ | ------------------------------------------- |
| OAuth token expiration | Medium | Proactive refresh; graceful re-auth flow    |
| API rate limits        | Medium | Batched sync; exponential backoff           |
| Sync conflicts         | Low    | Clear conflict UI; source-of-truth rules    |
| Privacy concerns       | Medium | Granular controls; minimal details option   |
| Calendar API changes   | Low    | Abstract provider layer; monitor changelogs |

---

## 13. Dependencies

- EventKit framework (Apple Calendar)
- Google Calendar API v3 client
- Microsoft Graph API client
- Supabase Vault for token encryption
- Background task scheduling

---

## 14. Testing Requirements

- [ ] Unit tests for event mapping logic
- [ ] Unit tests for iCal generation
- [ ] Integration tests for each provider
- [ ] Integration tests for conflict resolution
- [ ] E2E tests for full sync cycle
- [ ] Manual testing with real calendar accounts

---

## 15. Rollout Plan

1. **Alpha:** Apple Calendar only (simplest, no OAuth)
2. **Beta:** Add Google Calendar with OAuth
3. **GA:** Add Outlook; iCal feed generation
4. **Post-GA:** Bi-directional sync; calendar creation

---

### Linkage

- Product: CuraKnot
- Stack: iOS EventKit + Supabase Edge Functions + External OAuth
- Baseline: `./CuraKnot-spec.md`
- Related: Tasks, Shifts, Appointments
