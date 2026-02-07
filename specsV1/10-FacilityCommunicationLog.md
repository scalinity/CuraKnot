# Feature Spec 10 — Facility Communication Log

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 3 (Workflow Expansion)
> Differentiator: Systematic tracking of facility interactions — major pain point unaddressed

---

## 1. Problem Statement

Families with loved ones in facilities (nursing homes, assisted living, hospitals) spend hours on the phone navigating bureaucracy. They speak with nurses, social workers, administrators, and billing departments. Details get lost: "Who did I talk to? What did they promise? When should I follow up?"

A dedicated communication log turns scattered notes into a searchable, actionable record. This creates accountability, reduces repeated calls, and provides evidence when issues arise.

---

## 2. Differentiation and Moat

- **Unaddressed pain point** — no app tracks facility communications
- **Creates accountability** — documented promises and follow-ups
- **Reduces caregiver frustration** — never forget who said what
- **Evidence for disputes** — timestamped records of conversations
- **Premium lever:** Call recording integration (where legal), automated follow-ups

---

## 3. Goals

- [ ] G1: Quick logging of facility calls with structured fields
- [ ] G2: Template-based logging for common call types
- [ ] G3: Automatic follow-up task creation from calls
- [ ] G4: Searchable log with filtering by facility, date, topic
- [ ] G5: Link calls to handoffs when significant updates occur
- [ ] G6: Contact directory integration for quick logging

---

## 4. Non-Goals

- [ ] NG1: No call recording (legal complexity; Phase 2)
- [ ] NG2: No direct facility system integration
- [ ] NG3: No automated transcription of calls
- [ ] NG4: No legal advice for disputes

---

## 5. UX Flow

### 5.1 Quick Log Entry

```
┌─────────────────────────────────┐
│ Log Facility Call               │
│ ═══════════════════════════════│
│                                 │
│ Facility: [Sunrise Care ▼]      │
│                                 │
│ Spoke With:                     │
│ [Nurse Sarah           ]        │
│                                 │
│ Their Role:                     │
│ [Nurse] [Social Worker]         │
│ [Admin] [Billing] [Other]       │
│                                 │
│ Call Type:                      │
│ [Status Update] [Question]      │
│ [Complaint] [Scheduling]        │
│ [Billing] [Other]               │
│                                 │
│ Summary:                        │
│ ┌─────────────────────────────┐ │
│ │ Discussed mom's new PT      │ │
│ │ schedule. Sarah said they'll│ │
│ │ start 3x/week on Monday.    │ │
│ │ I asked about the fall last │ │
│ │ week - she said incident    │ │
│ │ report will be ready Friday.│ │
│ └─────────────────────────────┘ │
│                                 │
│ Follow-up Needed?               │
│ [✓] Yes                         │
│     Date: [Friday, Feb 7]       │
│     Reason: Get incident report │
│                                 │
│ [Save Call Log]                 │
└─────────────────────────────────┘
```

### 5.2 Communication Log View

```
┌─────────────────────────────────┐
│ Facility Communications         │
│ ═══════════════════════════════│
│                                 │
│ [🔍 Search] [Filter ▼]          │
│                                 │
│ ─── This Week ─────────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📞 Sunrise Care             │ │
│ │ Today, 2:30 PM              │ │
│ │                             │ │
│ │ Spoke with: Nurse Sarah     │ │
│ │ Topic: PT Schedule Update   │ │
│ │                             │ │
│ │ ⏰ Follow-up: Friday        │ │
│ │    Get incident report      │ │
│ │                             │ │
│ │ [View] [Edit] [Create Task] │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📞 Dr. Smith's Office       │ │
│ │ Yesterday, 10:15 AM         │ │
│ │                             │ │
│ │ Spoke with: Lisa (receptionist)│
│ │ Topic: Appointment Reschedule│ │
│ │                             │ │
│ │ ✅ Resolved                 │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── Last Week ─────────────────│
│ [...]                           │
│                                 │
│ [+ Log New Call]                │
└─────────────────────────────────┘
```

### 5.3 Call Detail View

```
┌─────────────────────────────────┐
│ ← Call Details                  │
│ ═══════════════════════════════│
│                                 │
│ 📞 Sunrise Senior Care          │
│ February 4, 2026 at 2:30 PM     │
│ Duration: ~15 minutes           │
│                                 │
│ Spoke With: Nurse Sarah         │
│ Role: Floor Nurse               │
│ Phone: (555) 123-4567           │
│                                 │
│ Topic: Status Update            │
│                                 │
│ ─── Summary ───────────────────│
│ Discussed mom's new PT schedule.│
│ Sarah said they'll start 3x/week│
│ on Monday. I asked about the    │
│ fall last week - she said       │
│ incident report will be ready   │
│ Friday.                         │
│                                 │
│ ─── Follow-up ─────────────────│
│ ⏰ Friday, February 7           │
│ Get incident report             │
│ [Mark Complete] [Reschedule]    │
│                                 │
│ ─── Actions ───────────────────│
│ [Create Handoff from This]      │
│ [Create Task]                   │
│ [Add to Visit Pack]             │
│                                 │
│ Logged by: Jane                 │
│ Patient: Mom                    │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Call Log Entry

**Required Fields:**

- Facility/Provider (from binder or free text)
- Contact person name
- Contact role (multi-select)
- Call type (template-driven)
- Summary (free text)
- Date/time (defaults to now)

**Optional Fields:**

- Phone number
- Duration estimate
- Follow-up date and reason
- Linked handoff
- Linked tasks

### 6.2 Call Types and Templates

| Call Type          | Pre-filled Prompts                             |
| ------------------ | ---------------------------------------------- |
| Status Update      | "What was discussed? Any changes?"             |
| Question           | "What did you ask? What was the answer?"       |
| Complaint          | "What was the issue? What was their response?" |
| Scheduling         | "What was scheduled? Confirmed date/time?"     |
| Billing            | "Claim/account #? Amount? Resolution?"         |
| Discharge Planning | "Discharge date? Requirements? Next steps?"    |

### 6.3 Follow-up System

- [ ] Create task automatically from follow-up
- [ ] Reminder notification on follow-up date
- [ ] Mark follow-up complete from log entry
- [ ] Snooze/reschedule follow-up
- [ ] Chain follow-ups for ongoing issues

### 6.4 Search and Filter

- [ ] Full-text search of summaries
- [ ] Filter by facility
- [ ] Filter by contact person
- [ ] Filter by call type
- [ ] Filter by date range
- [ ] Filter by follow-up status (pending, complete, overdue)

### 6.5 Integration Points

- [ ] Create handoff from call log (for significant updates)
- [ ] Create task from call log
- [ ] Add call summary to Visit Pack
- [ ] Link to binder contacts
- [ ] Import facility from binder

---

## 7. Data Model

### 7.1 Communication Logs

```sql
CREATE TABLE IF NOT EXISTS communication_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Contact info
    facility_name text NOT NULL,
    facility_id uuid REFERENCES binder_items(id),  -- Link to binder contact
    contact_name text NOT NULL,
    contact_role text[],  -- NURSE, SOCIAL_WORKER, ADMIN, BILLING, DOCTOR, etc.
    contact_phone text,

    -- Call details
    call_type text NOT NULL,  -- STATUS_UPDATE, QUESTION, COMPLAINT, SCHEDULING, BILLING, etc.
    call_date timestamptz NOT NULL DEFAULT now(),
    duration_minutes int,
    summary text NOT NULL,

    -- Follow-up
    follow_up_date date,
    follow_up_reason text,
    follow_up_status text,  -- PENDING, COMPLETE, CANCELLED
    follow_up_completed_at timestamptz,
    follow_up_task_id uuid REFERENCES tasks(id),

    -- Linked entities
    linked_handoff_id uuid REFERENCES handoffs(id),

    -- Status
    resolution_status text DEFAULT 'OPEN',  -- OPEN, RESOLVED, ESCALATED

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_communication_logs_patient ON communication_logs(patient_id, call_date DESC);
CREATE INDEX idx_communication_logs_facility ON communication_logs(circle_id, facility_name, call_date DESC);
CREATE INDEX idx_communication_logs_followup ON communication_logs(follow_up_date) WHERE follow_up_status = 'PENDING';

-- Full-text search
CREATE INDEX idx_communication_logs_search ON communication_logs USING gin(
    to_tsvector('english', summary || ' ' || COALESCE(contact_name, '') || ' ' || COALESCE(facility_name, ''))
);
```

### 7.2 Call Type Templates

```sql
CREATE TABLE IF NOT EXISTS call_type_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    type_key text NOT NULL UNIQUE,
    display_name text NOT NULL,
    icon text,
    prompt_text text,
    default_follow_up_days int,
    is_active boolean NOT NULL DEFAULT true,
    sort_order int NOT NULL DEFAULT 0
);

-- Seed templates
INSERT INTO call_type_templates (type_key, display_name, icon, prompt_text, default_follow_up_days) VALUES
('STATUS_UPDATE', 'Status Update', 'info.circle', 'What was discussed? Any changes to care?', NULL),
('QUESTION', 'Question', 'questionmark.circle', 'What did you ask? What was the answer?', 3),
('COMPLAINT', 'Complaint', 'exclamationmark.triangle', 'What was the issue? What was their response?', 2),
('SCHEDULING', 'Scheduling', 'calendar', 'What was scheduled? Confirmed date/time?', NULL),
('BILLING', 'Billing', 'dollarsign.circle', 'Claim/account number? Amount? Resolution?', 7),
('DISCHARGE', 'Discharge Planning', 'house', 'Discharge date? Requirements? Next steps?', 1);
```

---

## 8. RLS & Security

- [ ] communication_logs: Readable by circle members; writable by contributors+
- [ ] Logs may contain sensitive information — same access as handoffs
- [ ] Search respects circle membership
- [ ] No public or external access

---

## 9. Edge Functions

### 9.1 search-communication-logs

```typescript
// GET /functions/v1/search-communication-logs
// Full-text search with filters

interface SearchLogsRequest {
  circleId: string;
  patientId?: string;
  query?: string;
  facilityName?: string;
  callType?: string;
  dateFrom?: string;
  dateTo?: string;
  followUpStatus?: string;
  limit?: number;
  offset?: number;
}

interface SearchLogsResponse {
  logs: CommunicationLog[];
  total: number;
}
```

### 9.2 create-follow-up-task

```typescript
// POST /functions/v1/create-follow-up-task
// Creates task from communication log follow-up

interface CreateFollowUpRequest {
  logId: string;
}

interface CreateFollowUpResponse {
  taskId: string;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Quick Log Sheet

```swift
struct QuickCallLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CallLogViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    FacilityPicker(selection: $viewModel.selectedFacility)
                    TextField("Spoke with", text: $viewModel.contactName)
                    RolePicker(selection: $viewModel.contactRoles)
                }

                Section("Call Details") {
                    CallTypePicker(selection: $viewModel.callType)
                    DatePicker("When", selection: $viewModel.callDate)
                    TextEditor(text: $viewModel.summary)
                        .frame(minHeight: 100)
                }

                Section("Follow-up") {
                    Toggle("Needs follow-up", isOn: $viewModel.needsFollowUp)
                    if viewModel.needsFollowUp {
                        DatePicker("Date", selection: $viewModel.followUpDate, displayedComponents: .date)
                        TextField("Reason", text: $viewModel.followUpReason)
                    }
                }
            }
            .navigationTitle("Log Call")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}
```

### 10.2 Communication Log List

```swift
struct CommunicationLogListView: View {
    @StateObject private var viewModel = CommunicationLogListViewModel()
    @State private var searchText = ""
    @State private var showingFilters = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.groupedLogs, id: \.date) { group in
                    Section(group.dateHeader) {
                        ForEach(group.logs) { log in
                            NavigationLink {
                                CommunicationLogDetailView(log: log)
                            } label: {
                                CommunicationLogRow(log: log)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search calls")
            .onChange(of: searchText) { viewModel.search(query: searchText) }
            .navigationTitle("Facility Calls")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Log Call", systemImage: "plus") {
                        viewModel.showNewLog = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Filter", systemImage: "line.3.horizontal.decrease.circle") {
                        showingFilters = true
                    }
                }
            }
        }
    }
}
```

### 10.3 Call Log Row

```swift
struct CommunicationLogRow: View {
    let log: CommunicationLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.secondary)
                Text(log.facilityName)
                    .font(.headline)
                Spacer()
                Text(log.callDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Spoke with: \(log.contactName)")
                .font(.subheadline)

            Text(log.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let followUp = log.pendingFollowUp {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(followUp.isOverdue ? .red : .orange)
                    Text("Follow-up: \(followUp.date, style: .date)")
                        .font(.caption)
                        .foregroundStyle(followUp.isOverdue ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

---

## 11. Metrics

| Metric               | Target                  | Measurement               |
| -------------------- | ----------------------- | ------------------------- |
| Log adoption         | 30% of facility circles | Circles with ≥1 log/month |
| Logs per circle      | 4+ per month            | Average logs/month        |
| Follow-up completion | 70%                     | Completed / created       |
| Search usage         | 20% of log users        | Users who search logs     |
| Time savings         | Survey feedback         | User reported time saved  |

---

## 12. Risks & Mitigations

| Risk                | Impact | Mitigation                             |
| ------------------- | ------ | -------------------------------------- |
| Data entry friction | Medium | Quick templates; voice note option     |
| Incomplete logs     | Low    | Prompt for key fields; optional detail |
| Duplicate entries   | Low    | Recent log detection; merge option     |
| Privacy concerns    | Medium | Circle-only access; audit trail        |

---

## 13. Dependencies

- Binder contacts (for facility linking)
- Task system (for follow-ups)
- Handoff system (for linking)
- Search infrastructure

---

## 14. Testing Requirements

- [ ] Unit tests for search logic
- [ ] Unit tests for follow-up task creation
- [ ] Integration tests for log CRUD
- [ ] UI tests for quick log flow
- [ ] Search performance testing

---

## 15. Rollout Plan

1. **Alpha:** Basic log creation and list
2. **Beta:** Follow-up system; search
3. **GA:** Full feature with integrations
4. **Post-GA:** Voice notes; analytics

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Binder Contacts, Tasks, Handoffs
