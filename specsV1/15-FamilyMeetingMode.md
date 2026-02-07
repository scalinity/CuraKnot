# Feature Spec 15 — Family Meeting Mode

> Date: 2026-02-05 | Priority: LOW | Phase: 4 (Lifestyle & Emotional)
> Differentiator: Structured coordination for complex families

---

## 1. Problem Statement

Family care meetings happen regularly but poorly. Someone suggests "we should talk about Mom's care," but there's no agenda, decisions aren't documented, and follow-ups fall through. This leads to repeated conversations, family conflict, and care gaps.

A structured meeting mode provides agenda building, decision capture, action item assignment, and auto-generated meeting summaries as handoffs. This ritualizes coordination and reduces family friction.

---

## 2. Differentiation and Moat

- **Addresses family dynamics** — care is often about coordination, not just documentation
- **Reduces conflict** — documented decisions prevent "I never agreed to that"
- **Creates accountability** — action items assigned and tracked
- **Builds on existing features** — tasks, handoffs, notifications
- **Premium lever:** Video meeting integration, recurring meetings, templates

---

## 3. Goals

- [ ] G1: Create structured meeting agendas with discussion topics
- [ ] G2: Capture decisions made during meetings
- [ ] G3: Assign action items as tasks
- [ ] G4: Generate meeting summary as handoff
- [ ] G5: Send calendar invites for meetings
- [ ] G6: Support both in-person and virtual meetings

---

## 4. Non-Goals

- [ ] NG1: No built-in video conferencing (use FaceTime/Zoom)
- [ ] NG2: No real-time collaborative editing
- [ ] NG3: No meeting recording/transcription
- [ ] NG4: No voting/polling features

---

## 5. UX Flow

### 5.1 Meeting Setup

```
┌─────────────────────────────────┐
│ Plan a Family Meeting           │
│ ═══════════════════════════════│
│                                 │
│ Meeting Title:                  │
│ [Mom's Care Planning      ]     │
│                                 │
│ Date & Time:                    │
│ [Feb 15, 2026 at 7:00 PM  ▼]    │
│                                 │
│ Format:                         │
│ (●) In-person                   │
│ (○) Video call                  │
│                                 │
│ Invite circle members:          │
│ [✓] Jane (you)                  │
│ [✓] Mike                        │
│ [✓] Sarah                       │
│ [ ] Tom (viewer - notify only)  │
│                                 │
│ [Create Meeting & Build Agenda] │
└─────────────────────────────────┘
```

### 5.2 Agenda Builder

```
┌─────────────────────────────────┐
│ Meeting Agenda                  │
│ Feb 15, 2026 · 7:00 PM          │
│ ═══════════════════════════════│
│                                 │
│ Suggested Topics (from app):    │
│ ┌─────────────────────────────┐ │
│ │ [+] 3 overdue tasks         │ │
│ │ [+] Medication changes      │ │
│ │ [+] Upcoming appointment    │ │
│ └─────────────────────────────┘ │
│                                 │
│ Agenda Items:                   │
│ ┌─────────────────────────────┐ │
│ │ 1. Care schedule for March  │ │
│ │    Added by: Jane           │ │
│ │    [Edit] [Remove]          │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ 2. Discussion: assisted     │ │
│ │    living options           │ │
│ │    Added by: Mike           │ │
│ └─────────────────────────────┘ │
│                                 │
│ [+ Add Agenda Item]             │
│                                 │
│ Circle members can add items    │
│ until meeting starts.           │
│                                 │
│ [Send Invites]                  │
└─────────────────────────────────┘
```

### 5.3 During Meeting

```
┌─────────────────────────────────┐
│ Meeting in Progress             │
│ Started: 7:05 PM                │
│ ═══════════════════════════════│
│                                 │
│ Current Topic:                  │
│ ┌─────────────────────────────┐ │
│ │ 1. Care schedule for March  │ │
│ │                             │ │
│ │ Notes:                      │ │
│ │ [Discussion notes here...] │ │
│ │                             │ │
│ │ Decision:                   │ │
│ │ [Mike will cover weekends  ]│ │
│ │                             │ │
│ │ Action Items:               │ │
│ │ □ Mike: Update calendar     │ │
│ │ □ Jane: Inform facility     │ │
│ │                             │ │
│ │ [Mark Complete] [Skip]      │ │
│ └─────────────────────────────┘ │
│                                 │
│ Up Next: Assisted living options│
│                                 │
│ [End Meeting & Generate Summary]│
└─────────────────────────────────┘
```

### 5.4 Meeting Summary

```
┌─────────────────────────────────┐
│ Meeting Summary                 │
│ ═══════════════════════════════│
│                                 │
│ Mom's Care Planning             │
│ Feb 15, 2026 · 45 minutes       │
│ Attendees: Jane, Mike, Sarah    │
│                                 │
│ ─── Decisions Made ────────────│
│                                 │
│ 1. Care schedule: Mike will     │
│    cover weekends in March      │
│                                 │
│ 2. Assisted living: Will tour   │
│    3 facilities before April    │
│                                 │
│ ─── Action Items ──────────────│
│                                 │
│ □ Mike: Update calendar (Mar 1) │
│ □ Jane: Inform facility (Feb 16)│
│ □ Sarah: Research facilities    │
│                                 │
│ ─── Next Meeting ──────────────│
│ March 1, 2026 at 7:00 PM        │
│                                 │
│ [Publish as Handoff]            │
│ [Create All Tasks]              │
│ [Schedule Next Meeting]         │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Meeting Setup

- [ ] Title, date/time, format (in-person/virtual)
- [ ] Invite circle members
- [ ] Calendar integration (send invites)
- [ ] Recurring meeting option

### 6.2 Agenda Building

- [ ] Anyone invited can add agenda items
- [ ] Suggested topics from app data (overdue tasks, changes, etc.)
- [ ] Reorder items
- [ ] Lock agenda at meeting start

### 6.3 During Meeting

- [ ] Navigate through agenda items
- [ ] Capture notes per item
- [ ] Capture decisions
- [ ] Create action items (become tasks)
- [ ] Mark items complete or skip
- [ ] Track meeting duration

### 6.4 Meeting Summary

- [ ] Auto-generated summary
- [ ] Lists all decisions
- [ ] Lists all action items
- [ ] Publish as handoff
- [ ] Create tasks from action items
- [ ] Schedule follow-up meeting

### 6.5 Notifications

- [ ] Calendar invites
- [ ] Reminder before meeting
- [ ] Summary sent after meeting
- [ ] Action item reminders

---

## 7. Data Model

### 7.1 Meetings

```sql
CREATE TABLE IF NOT EXISTS family_meetings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Meeting details
    title text NOT NULL,
    scheduled_at timestamptz NOT NULL,
    format text NOT NULL DEFAULT 'IN_PERSON',  -- IN_PERSON | VIDEO
    meeting_link text,  -- For video meetings

    -- Status
    status text NOT NULL DEFAULT 'SCHEDULED',  -- SCHEDULED | IN_PROGRESS | COMPLETED | CANCELLED
    started_at timestamptz,
    ended_at timestamptz,

    -- Summary
    summary_handoff_id uuid REFERENCES handoffs(id),

    -- Recurrence
    recurrence_rule text,  -- RRULE format
    parent_meeting_id uuid REFERENCES family_meetings(id),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.2 Meeting Attendees

```sql
CREATE TABLE IF NOT EXISTS meeting_attendees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id uuid NOT NULL REFERENCES family_meetings(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'INVITED',  -- INVITED | ACCEPTED | DECLINED | ATTENDED
    invited_at timestamptz NOT NULL DEFAULT now(),
    responded_at timestamptz,
    UNIQUE(meeting_id, user_id)
);
```

### 7.3 Agenda Items

```sql
CREATE TABLE IF NOT EXISTS meeting_agenda_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id uuid NOT NULL REFERENCES family_meetings(id) ON DELETE CASCADE,
    added_by uuid NOT NULL,

    -- Content
    title text NOT NULL,
    description text,
    sort_order int NOT NULL,

    -- During meeting
    status text NOT NULL DEFAULT 'PENDING',  -- PENDING | IN_PROGRESS | COMPLETED | SKIPPED
    notes text,
    decision text,

    created_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.4 Meeting Action Items

```sql
CREATE TABLE IF NOT EXISTS meeting_action_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id uuid NOT NULL REFERENCES family_meetings(id) ON DELETE CASCADE,
    agenda_item_id uuid REFERENCES meeting_agenda_items(id) ON DELETE SET NULL,

    -- Action
    description text NOT NULL,
    assigned_to uuid,
    due_date date,

    -- Task linkage
    task_id uuid REFERENCES tasks(id),

    created_at timestamptz NOT NULL DEFAULT now()
);
```

---

## 8. RLS & Security

- [ ] family_meetings: Readable by circle members
- [ ] meeting_attendees: Readable by circle members
- [ ] meeting_agenda_items: Writable by meeting attendees
- [ ] meeting_action_items: Writable by meeting attendees
- [ ] Summary handoff follows standard handoff RLS

---

## 9. Edge Functions

### 9.1 generate-meeting-summary

```typescript
// POST /functions/v1/generate-meeting-summary

interface GenerateSummaryRequest {
  meetingId: string;
}

interface GenerateSummaryResponse {
  handoffId: string;
  tasksCreated: string[];
}
```

### 9.2 send-meeting-invites

```typescript
// POST /functions/v1/send-meeting-invites

interface SendInvitesRequest {
  meetingId: string;
}

interface SendInvitesResponse {
  invitesSent: number;
  calendarEventCreated: boolean;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Meeting Flow

```swift
struct FamilyMeetingView: View {
    @StateObject private var viewModel: FamilyMeetingViewModel
    let meeting: FamilyMeeting

    var body: some View {
        NavigationStack {
            Group {
                switch meeting.status {
                case .scheduled:
                    AgendaBuilderView(viewModel: viewModel)
                case .inProgress:
                    MeetingInProgressView(viewModel: viewModel)
                case .completed:
                    MeetingSummaryView(viewModel: viewModel)
                case .cancelled:
                    MeetingCancelledView()
                }
            }
            .navigationTitle(meeting.title)
        }
    }
}
```

### 10.2 Agenda Builder

```swift
struct AgendaBuilderView: View {
    @ObservedObject var viewModel: FamilyMeetingViewModel
    @State private var showingAddItem = false

    var body: some View {
        List {
            // Suggested topics
            if !viewModel.suggestedTopics.isEmpty {
                Section("Suggested Topics") {
                    ForEach(viewModel.suggestedTopics) { topic in
                        Button {
                            viewModel.addSuggestedTopic(topic)
                        } label: {
                            Label(topic.title, systemImage: "plus.circle")
                        }
                    }
                }
            }

            // Agenda
            Section("Agenda") {
                ForEach(viewModel.agendaItems) { item in
                    AgendaItemRow(item: item)
                }
                .onMove { viewModel.reorderItems(from: $0, to: $1) }

                Button("Add Item", systemImage: "plus") {
                    showingAddItem = true
                }
            }

            // Actions
            Section {
                Button("Send Invites", systemImage: "envelope") {
                    viewModel.sendInvites()
                }

                Button("Start Meeting", systemImage: "play.fill") {
                    viewModel.startMeeting()
                }
                .disabled(viewModel.agendaItems.isEmpty)
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddAgendaItemSheet(onAdd: viewModel.addItem)
        }
    }
}
```

### 10.3 Meeting In Progress

```swift
struct MeetingInProgressView: View {
    @ObservedObject var viewModel: FamilyMeetingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressView(value: viewModel.progress)
                .padding()

            // Current topic
            if let currentItem = viewModel.currentAgendaItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(currentItem.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        // Notes
                        VStack(alignment: .leading) {
                            Text("Notes")
                                .font(.headline)
                            TextEditor(text: $viewModel.currentNotes)
                                .frame(minHeight: 100)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                        }

                        // Decision
                        VStack(alignment: .leading) {
                            Text("Decision")
                                .font(.headline)
                            TextField("What was decided?", text: $viewModel.currentDecision)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Action items
                        VStack(alignment: .leading) {
                            Text("Action Items")
                                .font(.headline)
                            ForEach(viewModel.currentActionItems) { item in
                                ActionItemRow(item: item)
                            }
                            Button("Add Action Item", systemImage: "plus") {
                                viewModel.showAddActionItem = true
                            }
                        }
                    }
                    .padding()
                }
            }

            // Navigation
            HStack {
                Button("Skip") {
                    viewModel.skipItem()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Complete & Next") {
                    viewModel.completeItem()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("End Meeting") {
                    viewModel.endMeeting()
                }
            }
        }
    }
}
```

---

## 11. Metrics

| Metric                   | Target         | Measurement                     |
| ------------------------ | -------------- | ------------------------------- |
| Meeting feature adoption | 15% of circles | Circles with ≥1 meeting         |
| Meetings per circle      | 1+ per month   | Active meeting circles          |
| Action item completion   | 70%            | Tasks created and completed     |
| Summary publish rate     | 90%            | Summaries published as handoffs |
| Attendee participation   | 80%            | Accepted / invited              |

---

## 12. Risks & Mitigations

| Risk                        | Impact | Mitigation                     |
| --------------------------- | ------ | ------------------------------ |
| Feature complexity          | Medium | Streamlined UI; guided flow    |
| Low adoption                | Medium | Suggest when circle has issues |
| Incomplete meetings         | Low    | Auto-save; resume later        |
| Calendar integration issues | Medium | Fallback to manual scheduling  |

---

## 13. Dependencies

- Calendar sync feature
- Task creation (existing)
- Handoff creation (existing)
- Push notifications

---

## 14. Testing Requirements

- [ ] Unit tests for meeting state machine
- [ ] Unit tests for summary generation
- [ ] Integration tests for task creation
- [ ] UI tests for meeting flow
- [ ] Calendar integration testing

---

## 15. Rollout Plan

1. **Alpha:** Basic meeting + agenda
2. **Beta:** In-meeting capture; summaries
3. **GA:** Calendar integration; tasks
4. **Post-GA:** Recurring meetings; templates

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Tasks, Handoffs, Calendar Sync
