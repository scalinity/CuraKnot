# Feature Spec 06 — Smart Appointment Question Generator

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 2 (AI Differentiation)
> Differentiator: Extends Visit Pack from passive summary to active preparation

---

## 1. Problem Statement

Caregivers often leave appointments frustrated, realizing they forgot to ask important questions. The stress of the medical environment, time pressure, and information overload cause critical topics to slip. Generic "questions to ask your doctor" lists don't address the specific, evolving situation.

CuraKnot has rich context from handoffs and binder data. AI can analyze recent patterns and generate personalized questions that address the patient's specific circumstances — turning passive documentation into active appointment preparation.

---

## 2. Differentiation and Moat

- **Extends existing Visit Pack** — incremental development, significant value add
- **Personalized to patient data** — not generic advice lists
- **Pattern detection** — surfaces concerns caregiver may have missed
- **Reduces caregiver stress** — confidence walking into appointments
- **Creates viral moment** — "CuraKnot reminded me to ask about X"
- **Premium lever:** Specialist-specific templates, longitudinal tracking

---

## 3. Goals

- [ ] G1: Generate personalized questions based on recent handoffs and binder data
- [ ] G2: Integrate with Visit Pack generation workflow
- [ ] G3: Allow collaborative editing (circle members add their questions)
- [ ] G4: Prioritize questions by urgency and importance
- [ ] G5: Post-appointment capture: which questions were addressed?
- [ ] G6: Learn from user feedback to improve suggestions

---

## 4. Non-Goals

- [ ] NG1: No diagnostic questions that imply medical knowledge
- [ ] NG2: No provider-specific question sets (Phase 2)
- [ ] NG3: No automatic sending to providers
- [ ] NG4: No recording of provider responses (privacy concerns)

---

## 5. UX Flow

### 5.1 Pre-Appointment Trigger

1. **Entry:** Visit Pack creation → "Generate Questions" step
2. **Alternative:** Patient card → Upcoming appointment → "Prepare Questions"
3. **Notification:** "Appointment in 2 days. Want help preparing questions?"

### 5.2 Question Generation

```
┌─────────────────────────────────┐
│ Questions for Dr. Smith         │
│ February 10, 2026               │
│ ═══════════════════════════════│
│                                 │
│ AI Suggested Questions:         │
│                                 │
│ ⭐ HIGH PRIORITY                │
│ ┌─────────────────────────────┐ │
│ │ □ You mentioned dizziness   │ │
│ │   4 times this month. Ask:  │ │
│ │   "Could any medications    │ │
│ │   be causing dizziness?"    │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ □ Lisinopril was started    │ │
│ │   3 weeks ago. Ask:         │ │
│ │   "Is the blood pressure    │ │
│ │   medication working?"      │ │
│ └─────────────────────────────┘ │
│                                 │
│ 📋 ROUTINE                      │
│ ┌─────────────────────────────┐ │
│ │ □ "Are all current meds     │ │
│ │   still necessary?"         │ │
│ └─────────────────────────────┘ │
│                                 │
│ ➕ Your Questions:              │
│ ┌─────────────────────────────┐ │
│ │ □ Ask about PT referral     │ │
│ │   — Added by Jane (Sister)  │ │
│ └─────────────────────────────┘ │
│                                 │
│ [+ Add Question]                │
│                                 │
│ [Include in Visit Pack]         │
└─────────────────────────────────┘
```

### 5.3 During Appointment

- Printable/shareable checklist
- Mark questions as "Asked" or "Discussed"
- Quick notes field for responses

### 5.4 Post-Appointment

- Review which questions were addressed
- Capture decisions and outcomes
- Generate follow-up tasks automatically

---

## 6. Functional Requirements

### 6.1 Question Generation Engine

**Input Analysis:**

- [ ] Recent handoffs (14-30 days) — symptoms, concerns, changes
- [ ] Medication changes — new meds, dose changes, side effects
- [ ] Task backlog — overdue follow-ups, incomplete actions
- [ ] Previous appointment outcomes — unresolved questions
- [ ] Binder data — conditions, care plan, provider history

**Question Categories:**
| Category | Trigger | Example |
|----------|---------|---------|
| Symptom follow-up | Repeated mentions | "Dizziness mentioned 4x — ask about causes" |
| Medication review | New/changed meds | "Lisinopril started 3 weeks ago — ask about effectiveness" |
| Test results | Lab/imaging mentioned | "Blood work was done — ask about results" |
| Care plan | Treatment changes | "PT recommended — ask about starting" |
| Prognosis | Condition changes | "Ask about what to expect next" |
| Side effects | Med + symptom correlation | "Fatigue started after new med — ask about connection" |

### 6.2 Question Prioritization

```typescript
interface GeneratedQuestion {
  id: string;
  text: string;
  priority: "HIGH" | "MEDIUM" | "LOW";
  category: QuestionCategory;
  reasoning: string; // Why this question was generated
  sourceHandoffs: string[]; // Handoffs that informed this
  sourceMedications?: string[];
}

// Priority scoring
function calculatePriority(question: QuestionContext): Priority {
  let score = 0;

  // Recency boost
  if (question.mentionedInLast7Days) score += 3;

  // Frequency boost
  score += question.mentionCount * 2;

  // Medication safety boost
  if (question.involvesMedication) score += 2;

  // Unresolved boost
  if (question.previouslyAskedNotAnswered) score += 3;

  return score >= 6 ? "HIGH" : score >= 3 ? "MEDIUM" : "LOW";
}
```

### 6.3 Collaborative Editing

- [ ] Circle members can add their own questions
- [ ] Questions show author and timestamp
- [ ] Comments on questions (clarifications)
- [ ] Voting/starring to prioritize
- [ ] Real-time sync for collaborative editing

### 6.4 Visit Pack Integration

- [ ] Questions included in Visit Pack PDF
- [ ] Separate "Questions" section with checkboxes
- [ ] Shareable via secure link (for clinician view)
- [ ] Print-friendly format

### 6.5 Post-Appointment Workflow

- [ ] Mark questions as Discussed / Not Discussed / Deferred
- [ ] Capture brief response notes
- [ ] Auto-generate tasks for follow-ups
- [ ] Create "After Visit" handoff with decisions

---

## 7. Data Model

### 7.1 Appointment Questions

```sql
CREATE TABLE IF NOT EXISTS appointment_questions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    appointment_pack_id uuid REFERENCES appointment_packs(id) ON DELETE SET NULL,

    -- Question content
    question_text text NOT NULL,
    reasoning text,  -- Why generated/added
    category text,  -- SYMPTOM | MEDICATION | TEST | CARE_PLAN | PROGNOSIS

    -- Source tracking
    source text NOT NULL,  -- AI_GENERATED | USER_ADDED
    source_handoffs uuid[],  -- Handoffs that informed this
    created_by uuid NOT NULL,

    -- Priority and status
    priority text NOT NULL DEFAULT 'MEDIUM',  -- HIGH | MEDIUM | LOW
    status text NOT NULL DEFAULT 'PENDING',  -- PENDING | DISCUSSED | NOT_DISCUSSED | DEFERRED
    sort_order int NOT NULL DEFAULT 0,

    -- Post-appointment
    response_notes text,
    discussed_at timestamptz,
    follow_up_task_id uuid REFERENCES tasks(id),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_appointment_questions_pack ON appointment_questions(appointment_pack_id);
CREATE INDEX idx_appointment_questions_patient ON appointment_questions(patient_id, created_at DESC);
```

### 7.2 Question Templates (System)

```sql
CREATE TABLE IF NOT EXISTS question_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category text NOT NULL,
    trigger_type text NOT NULL,  -- SYMPTOM_REPEATED | MED_NEW | MED_CHANGED | etc.
    template_text text NOT NULL,
    priority_default text NOT NULL DEFAULT 'MEDIUM',
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Seed templates
INSERT INTO question_templates (category, trigger_type, template_text, priority_default) VALUES
('SYMPTOM', 'SYMPTOM_REPEATED', 'You mentioned {symptom} {count} times recently. Could this be related to medications or a new condition?', 'HIGH'),
('MEDICATION', 'MED_NEW', '{medication} was started {duration} ago. Is it working as expected? Any side effects to watch for?', 'MEDIUM'),
('MEDICATION', 'MED_SIDE_EFFECT', 'Could {symptom} be a side effect of {medication}?', 'HIGH'),
('TEST', 'TEST_PENDING', 'What were the results of the recent {test_type}?', 'MEDIUM'),
('CARE_PLAN', 'REFERRAL_PENDING', 'Can we move forward with the {referral_type} referral?', 'MEDIUM');
```

---

## 8. RLS & Security

- [ ] appointment_questions: Readable by circle members; writable by contributors+
- [ ] Questions with response_notes are sensitive — same access as handoffs
- [ ] No automated sharing with providers without explicit consent
- [ ] Audit log for question generation (HIPAA compliance)

---

## 9. Edge Functions

### 9.1 generate-appointment-questions

```typescript
// POST /functions/v1/generate-appointment-questions
// Analyzes patient data and generates personalized questions

interface GenerateQuestionsRequest {
  patientId: string;
  appointmentDate?: string;
  providerId?: string; // For provider-specific questions (future)
  rangeStartDays?: number; // Default 30
}

interface GenerateQuestionsResponse {
  questions: GeneratedQuestion[];
  analysisContext: {
    handoffsAnalyzed: number;
    symptomsDetected: string[];
    medicationChanges: MedChange[];
  };
}
```

### 9.2 analyze-handoff-patterns

```typescript
// Internal function for pattern detection

interface PatternAnalysis {
  repeatedSymptoms: {
    symptom: string;
    count: number;
    recentMentions: Date[];
  }[];
  medicationCorrelations: {
    medication: string;
    potentialSideEffects: string[];
  }[];
  unresolvedConcerns: {
    concern: string;
    firstMentioned: Date;
    stillRelevant: boolean;
  }[];
}
```

---

## 10. iOS Implementation Notes

### 10.1 Question Generation View

```swift
struct QuestionGeneratorView: View {
    @StateObject private var viewModel: QuestionGeneratorViewModel
    let patient: Patient
    let appointmentDate: Date?

    var body: some View {
        NavigationStack {
            List {
                // AI Generated Section
                Section("AI Suggested Questions") {
                    ForEach(viewModel.generatedQuestions) { question in
                        QuestionRow(
                            question: question,
                            onToggle: viewModel.toggleQuestion
                        )
                    }
                }

                // User Added Section
                Section("Your Questions") {
                    ForEach(viewModel.userQuestions) { question in
                        QuestionRow(
                            question: question,
                            onToggle: viewModel.toggleQuestion
                        )
                    }

                    Button("Add Question") {
                        viewModel.showAddQuestion = true
                    }
                }
            }
            .navigationTitle("Appointment Questions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Generate") {
                        viewModel.generateQuestions()
                    }
                }
            }
        }
        .task {
            await viewModel.loadExistingQuestions()
        }
    }
}
```

### 10.2 Question Row Component

```swift
struct QuestionRow: View {
    let question: AppointmentQuestion
    let onToggle: (AppointmentQuestion) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                onToggle(question)
            } label: {
                Image(systemName: question.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(question.isSelected ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // Priority badge
                if question.priority == .high {
                    Text("HIGH PRIORITY")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }

                // Question text
                Text(question.text)
                    .font(.body)

                // Reasoning
                if let reasoning = question.reasoning {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Source
                if question.source == .aiGenerated {
                    Label("AI Suggested", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

### 10.3 Post-Appointment Capture

```swift
struct PostAppointmentView: View {
    @ObservedObject var viewModel: AppointmentQuestionsViewModel

    var body: some View {
        List {
            Section("Questions Discussed") {
                ForEach(viewModel.questions) { question in
                    PostAppointmentQuestionRow(
                        question: question,
                        onStatusChange: viewModel.updateStatus,
                        onNotesChange: viewModel.updateNotes
                    )
                }
            }

            Section {
                Button("Create After-Visit Handoff") {
                    viewModel.createAfterVisitHandoff()
                }
            }
        }
        .navigationTitle("After Visit")
    }
}
```

---

## 11. Metrics

| Metric                      | Target             | Measurement                        |
| --------------------------- | ------------------ | ---------------------------------- |
| Question generation usage   | 60% of Visit Packs | Packs with generated questions     |
| Questions per pack          | 5+                 | Average AI + user questions        |
| Question relevance          | 80%                | Questions marked as discussed      |
| User question additions     | 2+ per pack        | User-added questions               |
| Post-appointment completion | 50%                | Users who complete post-visit flow |
| Feature satisfaction        | 4.5+               | In-app rating                      |

---

## 12. Risks & Mitigations

| Risk                        | Impact | Mitigation                             |
| --------------------------- | ------ | -------------------------------------- |
| Irrelevant questions        | Medium | Show reasoning; allow dismiss/edit     |
| Missing important topics    | Medium | Supplement with generic best practices |
| Information overload        | Medium | Prioritization; limit to top 10        |
| Privacy in shared questions | Low    | Clear attribution; circle access only  |

---

## 13. Dependencies

- Visit Pack feature (existing)
- Handoff and binder data models (existing)
- LLM API for question generation
- AI Care Coach infrastructure (shared)

---

## 14. Testing Requirements

- [ ] Unit tests for pattern detection logic
- [ ] Unit tests for priority scoring
- [ ] Integration tests for question generation
- [ ] UI tests for question management
- [ ] A/B testing for question relevance

---

## 15. Rollout Plan

1. **Alpha:** Basic question generation with limited templates
2. **Beta:** Full AI generation; collaborative editing
3. **GA:** Post-appointment workflow; task integration
4. **Post-GA:** Provider-specific templates; learning from feedback

---

### Linkage

- Product: CuraKnot
- Stack: Supabase Edge Functions + LLM API + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Visit Pack, AI Care Coach, Operational Insights
