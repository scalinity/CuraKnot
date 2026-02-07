# Feature Spec 09 — Hospital Discharge Planning Wizard

> Date: 2026-02-05 | Priority: HIGH | Phase: 3 (Workflow Expansion)
> Differentiator: Critical transition support at highest-risk caregiving moment

---

## 1. Problem Statement

Hospital discharge is the most dangerous transition in caregiving. 20% of patients are readmitted within 30 days. Discharge instructions are overwhelming: new medications, equipment needs, follow-up appointments, home modifications, and care schedule changes. Families receive a paper packet and are sent home.

CuraKnot can provide a structured wizard that transforms chaotic discharge into a manageable checklist, automatically creating tasks, updating the binder, and establishing a care rhythm for the critical post-discharge period.

---

## 2. Differentiation and Moat

- **Addresses highest-risk moment** — measurable impact on readmissions
- **Creates immediate value** — activated during crisis, creates lasting engagement
- **Structured workflow** — reduces cognitive load when overwhelmed
- **Auto-populates CuraKnot** — tasks, binder, shifts created automatically
- **Premium lever:** Advanced discharge templates, facility-specific checklists

---

## 3. Goals

- [ ] G1: Guided workflow for hospital-to-home transitions
- [ ] G2: Pre-built checklists organized by discharge timeline (before, day-of, first week)
- [ ] G3: Medication reconciliation prompt with scanner integration
- [ ] G4: Automatic task creation from checklist items
- [ ] G5: Equipment and supply checklist with ordering resources
- [ ] G6: Follow-up appointment scheduling with calendar integration
- [ ] G7: Create structured "Discharge Handoff" capturing all key information

---

## 4. Non-Goals

- [ ] NG1: No clinical assessment of discharge readiness
- [ ] NG2: No direct hospital system integration (Phase 2)
- [ ] NG3: No equipment ordering within app
- [ ] NG4: No insurance pre-authorization assistance

---

## 5. UX Flow

### 5.1 Wizard Entry

```
┌─────────────────────────────────┐
│ 🏥 Discharge Planning           │
│ ═══════════════════════════════│
│                                 │
│ [Patient] is coming home from   │
│ the hospital. Let's make sure   │
│ everything is ready.            │
│                                 │
│ Discharge Date:                 │
│ [February 10, 2026        ▼]    │
│                                 │
│ Discharge From:                 │
│ [General Hospital          ]    │
│                                 │
│ Reason for Stay:                │
│ [Hip replacement surgery   ]    │
│                                 │
│ [Start Planning]                │
│                                 │
└─────────────────────────────────┘
```

### 5.2 Wizard Steps

1. **Before Discharge** — Hospital tasks, questions for care team
2. **Medications** — Reconciliation, pharmacy prep, pill organizer
3. **Equipment & Supplies** — DME, supplies, home modifications
4. **Home Preparation** — Safety, bedroom setup, accessibility
5. **Care Schedule** — First week shifts, caregiver assignments
6. **Follow-ups** — Appointments, home health, therapy
7. **Review & Create** — Summary and task generation

### 5.3 Checklist Screen Example

```
┌─────────────────────────────────┐
│ Step 2: Medications             │
│ ═══════════════════════════════│
│                                 │
│ 💊 Before Leaving Hospital      │
│ ┌─────────────────────────────┐ │
│ │ □ Get written medication    │ │
│ │   list from discharge nurse │ │
│ │                             │ │
│ │ □ Review each medication    │ │
│ │   with nurse or pharmacist  │ │
│ │                             │ │
│ │ □ Ask about drug interactions│ │
│ │   with existing meds        │ │
│ │                             │ │
│ │ □ Confirm which old meds    │ │
│ │   to stop taking            │ │
│ └─────────────────────────────┘ │
│                                 │
│ 🏠 At Home                      │
│ ┌─────────────────────────────┐ │
│ │ □ Pick up new prescriptions │ │
│ │   Pharmacy: [CVS      ▼]    │ │
│ │   Assigned to: [Jane  ▼]    │ │
│ │   Due: [Feb 10      ▼]      │ │
│ │                             │ │
│ │ □ Set up pill organizer     │ │
│ │                             │ │
│ │ □ Schedule medication times │ │
│ └─────────────────────────────┘ │
│                                 │
│ [📸 Scan Medication List]       │
│                                 │
│ [← Back]            [Next →]    │
└─────────────────────────────────┘
```

### 5.4 Review & Create

```
┌─────────────────────────────────┐
│ Ready to Go Home!               │
│ ═══════════════════════════════│
│                                 │
│ Here's what we'll set up:       │
│                                 │
│ 📋 Tasks to Create: 12          │
│ • 4 medication tasks            │
│ • 3 equipment tasks             │
│ • 2 appointment tasks           │
│ • 3 care schedule tasks         │
│                                 │
│ 📁 Binder Updates: 5            │
│ • 3 new medications             │
│ • 2 new contacts                │
│                                 │
│ 📅 Shifts Scheduled: 7          │
│ • First week coverage           │
│                                 │
│ 📝 Discharge Handoff            │
│ • Captures all discharge info   │
│                                 │
│ [Create Everything]             │
│                                 │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Wizard Steps

| Step          | Purpose                   | Outputs                     |
| ------------- | ------------------------- | --------------------------- |
| Setup         | Capture discharge context | Discharge record created    |
| Medications   | Med reconciliation        | Binder meds, med tasks      |
| Equipment     | DME and supplies          | Equipment tasks, resources  |
| Home Prep     | Safety and accessibility  | Home prep tasks             |
| Care Schedule | First week coverage       | Shifts created              |
| Follow-ups    | Appointments and therapy  | Appointment tasks, contacts |
| Review        | Confirm and create        | All entities created        |

### 6.2 Checklist Templates

**Pre-built checklists by discharge type:**

- General medical discharge
- Surgical (orthopedic, cardiac, abdominal)
- Stroke/neurological
- Cardiac event
- Fall/injury
- Psychiatric

**Checklist structure:**

```typescript
interface ChecklistTemplate {
  id: string;
  name: string;
  dischargeType: string;
  sections: ChecklistSection[];
}

interface ChecklistSection {
  title: string;
  timing: "BEFORE_DISCHARGE" | "DAY_OF" | "FIRST_3_DAYS" | "FIRST_WEEK";
  items: ChecklistItem[];
}

interface ChecklistItem {
  id: string;
  text: string;
  isRequired: boolean;
  taskTemplate?: TaskTemplate;
  binderItemTemplate?: BinderItemTemplate;
  resourceLinks?: ResourceLink[];
  assignable: boolean;
  dueDateOffset?: number; // Days from discharge
}
```

### 6.3 Task Generation

- [ ] Each completed checklist item can generate a task
- [ ] Tasks have appropriate due dates relative to discharge
- [ ] Tasks assigned to selected circle members
- [ ] Tasks linked back to discharge record for context

### 6.4 Medication Integration

- [ ] Prompt to scan medication list (use Document Scanner)
- [ ] Import medications to binder with "source: DISCHARGE"
- [ ] Flag medication changes vs existing list
- [ ] Create verification tasks for ambiguous meds

### 6.5 Shift Scheduling

- [ ] Quick scheduler for first 7 days post-discharge
- [ ] Pre-fill with available circle members
- [ ] Higher coverage suggested for first 48-72 hours
- [ ] Integration with existing shift feature

### 6.6 Discharge Handoff

- [ ] Auto-generated handoff summarizing discharge
- [ ] Includes: reason, medications, restrictions, follow-ups
- [ ] Structured format matching handoff template
- [ ] Published to timeline for circle visibility

---

## 7. Data Model

### 7.1 Discharge Records

```sql
CREATE TABLE IF NOT EXISTS discharge_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Discharge info
    facility_name text NOT NULL,
    discharge_date date NOT NULL,
    admission_date date,
    reason_for_stay text NOT NULL,
    discharge_type text,  -- GENERAL | SURGICAL | STROKE | CARDIAC | etc.

    -- Status
    status text NOT NULL DEFAULT 'IN_PROGRESS',  -- IN_PROGRESS | COMPLETED | CANCELLED
    current_step int NOT NULL DEFAULT 1,
    completed_at timestamptz,

    -- Outputs
    generated_tasks uuid[],
    generated_handoff_id uuid,
    generated_shifts uuid[],

    -- Metadata
    checklist_state_json jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.2 Checklist Templates (System)

```sql
CREATE TABLE IF NOT EXISTS discharge_checklist_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    discharge_type text NOT NULL,
    description text,
    sections_json jsonb NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    sort_order int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Seed with default templates
INSERT INTO discharge_checklist_templates (name, discharge_type, sections_json) VALUES
('General Discharge', 'GENERAL', '{"sections": [...]}'),
('Orthopedic Surgery', 'SURGICAL_ORTHO', '{"sections": [...]}'),
('Cardiac Event', 'CARDIAC', '{"sections": [...]}');
```

### 7.3 Checklist Progress

```sql
CREATE TABLE IF NOT EXISTS discharge_checklist_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    discharge_record_id uuid NOT NULL REFERENCES discharge_records(id) ON DELETE CASCADE,
    template_item_id text NOT NULL,
    section_name text NOT NULL,

    -- Status
    is_completed boolean NOT NULL DEFAULT false,
    completed_at timestamptz,
    completed_by uuid,

    -- Task linkage
    task_id uuid REFERENCES tasks(id),
    assigned_to uuid,
    due_date date,
    notes text,

    created_at timestamptz NOT NULL DEFAULT now()
);
```

---

## 8. RLS & Security

- [ ] discharge_records: Readable by circle members; writable by contributors+
- [ ] discharge_checklist_items: Access through discharge record
- [ ] Discharge handoff follows standard handoff RLS
- [ ] Templates are system-wide, read-only for users

---

## 9. Edge Functions

### 9.1 generate-discharge-outputs

```typescript
// POST /functions/v1/generate-discharge-outputs
// Creates tasks, handoff, shifts from completed wizard

interface GenerateOutputsRequest {
  dischargeRecordId: string;
}

interface GenerateOutputsResponse {
  tasksCreated: string[];
  handoffId: string;
  shiftsCreated: string[];
  binderItemsCreated: string[];
}
```

### 9.2 get-discharge-template

```typescript
// GET /functions/v1/get-discharge-template
// Returns appropriate template based on discharge type

interface GetTemplateRequest {
  dischargeType: string;
}

interface GetTemplateResponse {
  template: DischargeChecklistTemplate;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Wizard Container

```swift
struct DischargeWizardView: View {
    @StateObject private var viewModel: DischargeWizardViewModel
    @State private var currentStep = 1

    let totalSteps = 7

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: Double(currentStep), total: Double(totalSteps))
                    .padding()

                // Step content
                TabView(selection: $currentStep) {
                    DischargeSetupStep(viewModel: viewModel).tag(1)
                    MedicationsStep(viewModel: viewModel).tag(2)
                    EquipmentStep(viewModel: viewModel).tag(3)
                    HomePrepStep(viewModel: viewModel).tag(4)
                    CareScheduleStep(viewModel: viewModel).tag(5)
                    FollowUpsStep(viewModel: viewModel).tag(6)
                    ReviewStep(viewModel: viewModel).tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Navigation
                HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            withAnimation { currentStep -= 1 }
                        }
                    }
                    Spacer()
                    Button(currentStep == totalSteps ? "Create All" : "Next") {
                        if currentStep == totalSteps {
                            viewModel.generateOutputs()
                        } else {
                            withAnimation { currentStep += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Discharge Planning")
        }
    }
}
```

### 10.2 Checklist Section

```swift
struct ChecklistSectionView: View {
    let section: ChecklistSection
    @Binding var completedItems: Set<String>
    let onItemUpdate: (ChecklistItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(section.timing.icon)
                Text(section.title)
                    .font(.headline)
            }

            ForEach(section.items) { item in
                ChecklistItemRow(
                    item: item,
                    isCompleted: completedItems.contains(item.id),
                    onToggle: { completed in
                        onItemUpdate(item, completed)
                    }
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
```

### 10.3 Quick Shift Scheduler

```swift
struct QuickShiftSchedulerView: View {
    @ObservedObject var viewModel: DischargeWizardViewModel
    let dischargeDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule coverage for the first week")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(0..<7, id: \.self) { dayOffset in
                let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: dischargeDate)!
                ShiftDayRow(
                    date: date,
                    assignedMember: viewModel.shiftAssignments[dayOffset],
                    availableMembers: viewModel.circleMembers,
                    onAssign: { member in
                        viewModel.assignShift(dayOffset: dayOffset, to: member)
                    }
                )
            }

            // Priority indicator
            HStack {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("First 48 hours are highest risk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

---

## 11. Metrics

| Metric            | Target            | Measurement                            |
| ----------------- | ----------------- | -------------------------------------- |
| Wizard starts     | Track volume      | Discharge records created              |
| Wizard completion | 70%               | Completed / started                    |
| Tasks generated   | 10+ per discharge | Average tasks created                  |
| 30-day engagement | +40%              | Engagement after discharge vs baseline |
| User satisfaction | 4.5+              | Post-wizard rating                     |

---

## 12. Risks & Mitigations

| Risk                   | Impact | Mitigation                             |
| ---------------------- | ------ | -------------------------------------- |
| Overwhelming checklist | Medium | Progressive disclosure; prioritization |
| Missed items           | Medium | Required items flagged; review step    |
| Incorrect templates    | Low    | Easy template switching; customization |
| Timing pressure        | High   | Save progress; mobile-friendly         |

---

## 13. Dependencies

- Task creation (existing)
- Binder medications (existing)
- Document Scanner (for med lists)
- Shift feature (existing)
- Handoff creation (existing)
- Calendar sync (for appointments)

---

## 14. Testing Requirements

- [ ] Unit tests for task generation logic
- [ ] Unit tests for checklist state management
- [ ] Integration tests for full wizard flow
- [ ] UI tests for each step
- [ ] User testing with real discharge scenarios

---

## 15. Rollout Plan

1. **Alpha:** Basic wizard with general template
2. **Beta:** Multiple templates; medication integration
3. **GA:** Full feature with shifts and handoff generation
4. **Post-GA:** Hospital-specific templates; analytics

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Medication Reconciliation, Shift Mode, Document Scanner
