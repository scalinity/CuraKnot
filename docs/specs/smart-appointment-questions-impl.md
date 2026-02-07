# Implementation Spec: Smart Appointment Question Generator

> **Status**: Ready for Implementation
> **Version**: 1.0
> **Date**: 2026-02-05
> **Feature Spec**: `specsV1/06-SmartAppointmentQuestions.md`

---

## 1. Overview

AI-powered personalized question generation for medical appointments that analyzes recent handoffs and binder data to surface relevant questions for caregivers.

### Premium Tier Gating

| Tier   | Access Level                                     |
| ------ | ------------------------------------------------ |
| FREE   | No access (show preview with 2 sample questions) |
| PLUS   | Full feature access                              |
| FAMILY | Full features + enhanced templates               |

---

## 2. Database Schema

### 2.1 appointment_questions Table

```sql
CREATE TABLE IF NOT EXISTS appointment_questions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    appointment_pack_id uuid REFERENCES appointment_packs(id) ON DELETE SET NULL,

    question_text text NOT NULL CHECK (char_length(question_text) >= 10 AND char_length(question_text) <= 500),
    reasoning text CHECK (char_length(reasoning) <= 300),
    category text NOT NULL CHECK (category IN ('SYMPTOM', 'MEDICATION', 'TEST', 'CARE_PLAN', 'PROGNOSIS', 'SIDE_EFFECT', 'GENERAL')),

    source text NOT NULL CHECK (source IN ('AI_GENERATED', 'USER_ADDED', 'TEMPLATE')),
    source_handoff_ids uuid[] DEFAULT '{}',
    source_medication_ids uuid[] DEFAULT '{}',
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    priority text NOT NULL DEFAULT 'MEDIUM' CHECK (priority IN ('HIGH', 'MEDIUM', 'LOW')),
    priority_score int NOT NULL DEFAULT 0 CHECK (priority_score >= 0 AND priority_score <= 10),
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'DISCUSSED', 'NOT_DISCUSSED', 'DEFERRED')),
    sort_order int NOT NULL DEFAULT 0,

    response_notes text CHECK (char_length(response_notes) <= 2000),
    discussed_at timestamptz,
    discussed_by uuid REFERENCES users(id) ON DELETE SET NULL,
    follow_up_task_id uuid REFERENCES tasks(id) ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_appointment_questions_pack ON appointment_questions(appointment_pack_id) WHERE appointment_pack_id IS NOT NULL;
CREATE INDEX idx_appointment_questions_patient ON appointment_questions(patient_id, created_at DESC);
CREATE INDEX idx_appointment_questions_circle ON appointment_questions(circle_id);
CREATE INDEX idx_appointment_questions_pending ON appointment_questions(patient_id, status) WHERE status = 'PENDING';
```

### 2.2 question_templates Table

```sql
CREATE TABLE IF NOT EXISTS question_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category text NOT NULL CHECK (category IN ('SYMPTOM', 'MEDICATION', 'TEST', 'CARE_PLAN', 'PROGNOSIS', 'SIDE_EFFECT', 'GENERAL')),
    trigger_type text NOT NULL CHECK (trigger_type IN (
        'SYMPTOM_REPEATED', 'MED_NEW', 'MED_CHANGED', 'MED_SIDE_EFFECT',
        'TEST_PENDING', 'REFERRAL_PENDING', 'CONDITION_NEW', 'BASELINE'
    )),
    template_text text NOT NULL,
    template_variables text[] DEFAULT '{}',
    priority_default text NOT NULL DEFAULT 'MEDIUM' CHECK (priority_default IN ('HIGH', 'MEDIUM', 'LOW')),
    is_active boolean NOT NULL DEFAULT true,
    min_confidence_score numeric(3,2) DEFAULT 0.5 CHECK (min_confidence_score >= 0 AND min_confidence_score <= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_question_templates_active ON question_templates(trigger_type) WHERE is_active = true;
```

### 2.3 RLS Policies

```sql
-- Circle members can read
CREATE POLICY appointment_questions_select ON appointment_questions
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- Contributors+ can create
CREATE POLICY appointment_questions_insert ON appointment_questions
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Creator or Admin+ can update
CREATE POLICY appointment_questions_update ON appointment_questions
    FOR UPDATE USING (
        created_by = auth.uid() OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

-- Only Admin+ can delete
CREATE POLICY appointment_questions_delete ON appointment_questions
    FOR DELETE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));
```

---

## 3. Edge Function: generate-appointment-questions

### 3.1 Request/Response Contract

**Endpoint**: `POST /functions/v1/generate-appointment-questions`

```typescript
interface GenerateQuestionsRequest {
  patient_id: string;
  circle_id: string;
  appointment_pack_id?: string;
  appointment_date?: string; // ISO-8601
  range_days?: number; // Default: 30
  max_questions?: number; // Default: 10
}

interface GenerateQuestionsResponse {
  success: true;
  questions: GeneratedQuestion[];
  analysis_context: {
    handoffs_analyzed: number;
    date_range: { start: string; end: string };
    patterns_detected: PatternAnalysis;
    template_questions_added: number;
  };
  subscription_status: SubscriptionStatus;
}

interface GeneratedQuestion {
  id: string;
  question_text: string;
  reasoning: string;
  category: string;
  source: "AI_GENERATED" | "TEMPLATE";
  source_handoff_ids: string[];
  source_medication_ids: string[];
  priority: "HIGH" | "MEDIUM" | "LOW";
  priority_score: number;
}
```

### 3.2 Priority Scoring Algorithm

```typescript
function calculatePriorityScore(context: QuestionContext): number {
  let score = 0;

  // Recency: mentioned in last 7 days (+3)
  if (context.lastMentionDays <= 7) score += 3;
  else if (context.lastMentionDays <= 14) score += 2;
  else if (context.lastMentionDays <= 21) score += 1;

  // Frequency: +2 per mention (max +6)
  score += Math.min(context.mentionCount, 3) * 2;

  // Medication safety: +2
  if (context.category === "MEDICATION" || context.category === "SIDE_EFFECT") {
    score += 2;
  }

  // High correlation: +2
  if (context.correlationScore && context.correlationScore >= 0.7) {
    score += 2;
  }

  // Unresolved: +3
  if (context.previouslyAskedNotAnswered) score += 3;

  return Math.min(score, 10);
}

function categorizePriority(score: number): "HIGH" | "MEDIUM" | "LOW" {
  if (score >= 6) return "HIGH";
  if (score >= 3) return "MEDIUM";
  return "LOW";
}
```

---

## 4. iOS Components

### 4.1 File Structure

```
ios/CuraKnot/Features/AppointmentQuestions/
├── Models/
│   └── AppointmentQuestion.swift
├── Services/
│   └── AppointmentQuestionService.swift
├── ViewModels/
│   └── QuestionGeneratorViewModel.swift
├── Views/
│   ├── QuestionGeneratorView.swift
│   ├── QuestionRow.swift
│   ├── AddQuestionSheet.swift
│   ├── PostAppointmentView.swift
│   └── EmptyQuestionsView.swift
└── Components/
    ├── AnalysisContextView.swift
    ├── GeneratingQuestionsOverlay.swift
    └── PriorityBadge.swift
```

### 4.2 Core Models

```swift
enum QuestionCategory: String, Codable, CaseIterable {
    case symptom = "SYMPTOM"
    case medication = "MEDICATION"
    case test = "TEST"
    case carePlan = "CARE_PLAN"
    case prognosis = "PROGNOSIS"
    case sideEffect = "SIDE_EFFECT"
    case general = "GENERAL"
}

enum QuestionSource: String, Codable {
    case aiGenerated = "AI_GENERATED"
    case userAdded = "USER_ADDED"
    case template = "TEMPLATE"
}

enum QuestionPriority: String, Codable, CaseIterable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

enum QuestionStatus: String, Codable {
    case pending = "PENDING"
    case discussed = "DISCUSSED"
    case notDiscussed = "NOT_DISCUSSED"
    case deferred = "DEFERRED"
}
```

### 4.3 GRDB Model

```swift
struct AppointmentQuestion: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    var appointmentPackId: UUID?
    var questionText: String
    var reasoning: String?
    var category: QuestionCategory
    let source: QuestionSource
    var sourceHandoffIds: [UUID]
    var sourceMedicationIds: [UUID]
    let createdBy: UUID
    var priority: QuestionPriority
    var priorityScore: Int
    var status: QuestionStatus
    var sortOrder: Int
    var responseNotes: String?
    var discussedAt: Date?
    var discussedBy: UUID?
    var followUpTaskId: UUID?
    let createdAt: Date
    var updatedAt: Date

    static var databaseTableName: String { "appointment_questions" }

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case appointmentPackId = "appointment_pack_id"
        case questionText = "question_text"
        case reasoning
        case category
        case source
        case sourceHandoffIds = "source_handoff_ids"
        case sourceMedicationIds = "source_medication_ids"
        case createdBy = "created_by"
        case priority
        case priorityScore = "priority_score"
        case status
        case sortOrder = "sort_order"
        case responseNotes = "response_notes"
        case discussedAt = "discussed_at"
        case discussedBy = "discussed_by"
        case followUpTaskId = "follow_up_task_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

---

## 5. Acceptance Criteria

### 5.1 Question Generation (Must Have)

- [ ] AC-1.1: Generate 3-10 personalized questions from handoffs (14-30 days)
- [ ] AC-1.2: HIGH priority for symptoms mentioned 3+ times in last 7 days
- [ ] AC-1.3: Include medication effectiveness questions for new meds
- [ ] AC-1.4: Detect medication-symptom correlation for side effects
- [ ] AC-1.5: Fall back to templates if <3 handoffs

### 5.2 Prioritization (Must Have)

- [ ] AC-2.1: Score ≥6 → HIGH priority
- [ ] AC-2.2: Score 3-5 → MEDIUM priority
- [ ] AC-2.3: Score <3 → LOW priority
- [ ] AC-2.4: Medication questions get +2 boost

### 5.3 Collaborative Editing (Must Have)

- [ ] AC-3.1: CONTRIBUTOR+ can add questions
- [ ] AC-3.2: Show author and timestamp on user questions
- [ ] AC-3.3: AI questions show reasoning
- [ ] AC-3.4: Drag-and-drop reordering
- [ ] AC-3.5: Offline queue with sync

### 5.4 Premium Gating (Must Have)

- [ ] AC-4.1: FREE tier sees paywall with 2 sample questions
- [ ] AC-4.2: PLUS/FAMILY has full access
- [ ] AC-4.3: Show upgrade prompt on feature access

### 5.5 Post-Appointment (Should Have)

- [ ] AC-5.1: Mark questions DISCUSSED/NOT_DISCUSSED/DEFERRED
- [ ] AC-5.2: Capture response notes
- [ ] AC-5.3: Create follow-up tasks from deferred questions

### 5.6 Visit Pack Integration (Should Have)

- [ ] AC-6.1: Include questions in Visit Pack PDF
- [ ] AC-6.2: Show priority badges and checkboxes
- [ ] AC-6.3: Limit to top 15 questions

---

## 6. Integration Points

### 6.1 DependencyContainer

Add `AppointmentQuestionService` to container.

### 6.2 Patient Detail View

Add navigation link to QuestionGeneratorView.

### 6.3 Visit Pack Generation

Include questions in `generate-appointment-pack` Edge Function.

### 6.4 Notifications

Schedule appointment prep notification 2 days before.

---

## 7. Error Handling

| Error                 | HTTP Status | User Message                                     |
| --------------------- | ----------- | ------------------------------------------------ |
| AUTH_INVALID_TOKEN    | 401         | Session expired. Please sign in again.           |
| AUTH_ROLE_FORBIDDEN   | 403         | You don't have permission for this action.       |
| SUBSCRIPTION_REQUIRED | 402         | Upgrade to Plus for AI question generation.      |
| INSUFFICIENT_DATA     | 422         | Add more handoffs to get personalized questions. |
| LLM_API_ERROR         | 503         | AI unavailable. Using standard questions.        |

---

## 8. Test Scenarios

| ID   | Scenario                          | Expected                         |
| ---- | --------------------------------- | -------------------------------- |
| TS-1 | Generate with 10 handoffs, 3 meds | 5-10 questions with priorities   |
| TS-2 | Generate with 1 handoff           | "Not enough data" + manual add   |
| TS-3 | FREE tier attempts generation     | Upgrade paywall shown            |
| TS-4 | Add question manually             | Appears in "Your Questions"      |
| TS-5 | 4x "dizziness" mentions           | HIGH priority question generated |
| TS-6 | New med + symptom correlation     | Side effect question generated   |
| TS-7 | Mark question as DEFERRED         | Can create follow-up task        |
| TS-8 | Offline question addition         | Syncs when online                |

---

## 9. Files to Create/Modify

### New Files

1. `supabase/migrations/XXX_appointment_questions.sql`
2. `supabase/functions/generate-appointment-questions/index.ts`
3. `ios/CuraKnot/Features/AppointmentQuestions/` (full module)
4. `ios/CuraKnot/Core/Database/Models/AppointmentQuestion.swift`

### Modified Files

1. `ios/CuraKnot/App/DependencyContainer.swift` - Add service
2. `ios/CuraKnot/Features/Circle/PatientDetailView.swift` - Add nav link
3. `supabase/functions/generate-appointment-pack/index.ts` - Include questions

---

**Verdict**: READY FOR IMPLEMENTATION
