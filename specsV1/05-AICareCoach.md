# Feature Spec 05 — AI Care Coach (Conversational Guidance)

> Date: 2026-02-05 | Priority: HIGH | Phase: 2 (AI Differentiation)
> Differentiator: Context-aware AI guidance — no competitor offers this

---

## 1. Problem Statement

Caregivers face constant uncertainty: "Is this symptom serious?", "How do I talk to the doctor about hospice?", "What should I do after a fall?", "How do I manage my own stress?". They turn to Google, get overwhelmed or scared, and often delay action or make suboptimal decisions.

An AI Care Coach can provide thoughtful, personalized guidance based on the patient's context (from handoffs, binder, and history) without replacing medical advice. It transforms CuraKnot from a passive record-keeping tool into an active caregiving partner.

---

## 2. Differentiation and Moat

- **First caregiving app with context-aware AI** — unique in category
- **Personalized to patient context** — not generic advice
- **Reduces anxiety and decision paralysis** — immediate, relevant support
- **Builds trust and engagement** — users return for guidance
- **Data moat** — AI improves with usage; hard to replicate
- **Premium lever:** Advanced coaching, unlimited conversations, specialized templates

---

## 3. Goals

- [ ] G1: Conversational AI interface for caregiving questions
- [ ] G2: Context-aware responses using patient's handoffs, binder, and history
- [ ] G3: Clear non-clinical framing — operational guidance, not medical advice
- [ ] G4: Suggested actions that integrate with CuraKnot (create task, update binder)
- [ ] G5: Conversation history with bookmarking for important advice
- [ ] G6: Proactive suggestions based on recent handoffs (opt-in)

---

## 4. Non-Goals

- [ ] NG1: No clinical diagnosis or medical recommendations
- [ ] NG2: No prescription or medication dosing advice
- [ ] NG3: No replacement for professional healthcare providers
- [ ] NG4: No emergency response (direct to 911 for emergencies)
- [ ] NG5: No therapy or mental health treatment (resource referrals only)

---

## 5. UX Flow

### 5.1 Entry Points

- **Tab bar:** New "Coach" tab (or floating action button)
- **Contextual:** "Ask Coach" button on handoff detail, medication detail
- **Proactive:** Push notification with suggestion (opt-in)
- **Siri:** "Hey Siri, ask CuraKnot coach about..."

### 5.2 Conversation Interface

```
┌─────────────────────────────────┐
│ Care Coach           [Patient ▼]│
│ ═══════════════════════════════│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ You: Mom has been more      │ │
│ │ tired lately. Should I be   │ │
│ │ worried?                    │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Coach: I can see from your  │ │
│ │ recent handoffs that you've │ │
│ │ mentioned tiredness 4 times │ │
│ │ in the past week. This is   │ │
│ │ worth discussing with the   │ │
│ │ doctor. Here are some       │ │
│ │ questions to ask:           │ │
│ │                             │ │
│ │ • Could medications be      │ │
│ │   causing fatigue?          │ │
│ │ • Should we check iron or   │ │
│ │   thyroid levels?           │ │
│ │                             │ │
│ │ [Create Task: Schedule      │ │
│ │  doctor appointment]        │ │
│ │                             │ │
│ │ ⚠️ This is not medical      │ │
│ │ advice. Consult a provider. │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Type your question...]    [→]  │
└─────────────────────────────────┘
```

### 5.3 Conversation Topics

| Topic Category       | Example Questions                    | Context Used                |
| -------------------- | ------------------------------------ | --------------------------- |
| Symptom concerns     | "Is this rash normal?"               | Recent handoffs, conditions |
| Medication questions | "What are side effects of X?"        | Binder meds                 |
| Care coordination    | "How do I share info with new aide?" | Circle members              |
| Doctor preparation   | "What should I ask about Y?"         | Handoffs, meds, tasks       |
| Caregiver wellness   | "I'm feeling overwhelmed"            | Activity patterns           |
| Care transitions     | "Mom is coming home from hospital"   | Discharge handoffs          |
| End-of-life          | "How do I talk about hospice?"       | Patient context             |

### 5.4 Guardrails

- **Medical disclaimer** on every response
- **Emergency redirect:** "If this is an emergency, call 911"
- **Professional referral:** "I recommend discussing this with [provider type]"
- **Uncertainty acknowledgment:** "I'm not sure about X, but here's what I can help with..."
- **Scope limitation:** "This is outside what I can help with. Here are resources..."

---

## 6. Functional Requirements

### 6.1 Context Retrieval

- [ ] Access last 30 days of handoffs for context
- [ ] Access patient's binder (meds, conditions, contacts)
- [ ] Access recent tasks and their status
- [ ] Access circle member information (for coordination questions)
- [ ] Respect privacy: only data user has access to

### 6.2 Response Generation

- [ ] Use LLM with system prompt defining coach persona
- [ ] Include relevant patient context in prompts
- [ ] Structure responses with clear sections
- [ ] Always include disclaimer and appropriate referrals
- [ ] Generate actionable suggestions (tasks, binder updates)

### 6.3 Action Integration

- [ ] "Create Task" button in responses → pre-filled task editor
- [ ] "Add to Questions" → adds to Visit Pack questions list
- [ ] "Update Binder" → opens binder item editor
- [ ] "Call [Contact]" → initiates phone call
- [ ] "Share with Circle" → creates shareable summary

### 6.4 Conversation Management

- [ ] Conversation history stored per user per patient
- [ ] Bookmark important responses for later reference
- [ ] Search past conversations
- [ ] Delete conversation history (privacy)
- [ ] Export conversation (for sharing with provider)

### 6.5 Proactive Suggestions (Opt-in)

- [ ] Analyze handoff patterns for concerning trends
- [ ] Suggest questions before upcoming appointments
- [ ] Remind about medication reconciliation
- [ ] Wellness check-ins for caregiver

---

## 7. Data Model

### 7.1 Conversations

```sql
CREATE TABLE IF NOT EXISTS coach_conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title text,  -- Auto-generated from first message
    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | ARCHIVED
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.2 Messages

```sql
CREATE TABLE IF NOT EXISTS coach_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES coach_conversations(id) ON DELETE CASCADE,
    role text NOT NULL,  -- USER | ASSISTANT
    content text NOT NULL,
    context_snapshot_json jsonb,  -- Context used for this response
    actions_json jsonb,  -- Suggested actions in response
    is_bookmarked boolean NOT NULL DEFAULT false,
    tokens_used int,
    latency_ms int,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_coach_messages_conversation ON coach_messages(conversation_id, created_at);
```

### 7.3 Proactive Suggestions

```sql
CREATE TABLE IF NOT EXISTS coach_suggestions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    user_id uuid NOT NULL,
    suggestion_type text NOT NULL,  -- TREND_ALERT | APPOINTMENT_PREP | WELLNESS_CHECK
    title text NOT NULL,
    content text NOT NULL,
    context_json jsonb,
    status text NOT NULL DEFAULT 'PENDING',  -- PENDING | VIEWED | DISMISSED | ACTIONED
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.4 User Preferences

```sql
-- Add to users table
ALTER TABLE users
ADD COLUMN IF NOT EXISTS coach_settings_json jsonb DEFAULT '{
    "enabled": true,
    "proactiveSuggestions": false,
    "suggestionFrequency": "WEEKLY",
    "wellnessCheckIns": false
}'::jsonb;
```

---

## 8. RLS & Security

- [ ] coach_conversations: Users can only access their own conversations
- [ ] coach_messages: Access through conversation ownership
- [ ] coach_suggestions: Users can only see their own suggestions
- [ ] Context retrieval respects existing RLS policies
- [ ] No PHI in analytics or logs
- [ ] Conversation data encrypted at rest

---

## 9. Edge Functions

### 9.1 coach-chat

```typescript
// POST /functions/v1/coach-chat
// Processes user message and generates response

interface CoachChatRequest {
  conversationId?: string; // Existing or new
  patientId?: string;
  message: string;
}

interface CoachChatResponse {
  conversationId: string;
  messageId: string;
  content: string;
  actions: CoachAction[];
  disclaimer: string;
  suggestedFollowUps: string[];
}

interface CoachAction {
  type: "CREATE_TASK" | "ADD_QUESTION" | "UPDATE_BINDER" | "CALL_CONTACT";
  label: string;
  prefillData: Record<string, any>;
}
```

### 9.2 coach-context

```typescript
// Internal function to gather context for prompts

interface PatientContext {
  patient: PatientSummary;
  recentHandoffs: HandoffSummary[];
  medications: MedicationSummary[];
  conditions: string[];
  upcomingTasks: TaskSummary[];
  circleMembers: MemberSummary[];
}

async function gatherContext(
  patientId: string,
  userId: string,
  timeRangeDays: number = 30,
): Promise<PatientContext>;
```

### 9.3 coach-suggestions (Cron)

```typescript
// Runs daily
// Analyzes patterns and generates proactive suggestions

interface SuggestionGenerator {
  analyzeTrends(patientId: string): Promise<TrendSuggestion[]>;
  prepareAppointment(appointmentId: string): Promise<PrepSuggestion>;
  checkCaregiverWellness(userId: string): Promise<WellnessSuggestion | null>;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Coach View

```swift
struct CoachView: View {
    @StateObject private var viewModel = CoachViewModel()
    @State private var messageText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Conversation list or current conversation
                if let conversation = viewModel.currentConversation {
                    ConversationView(conversation: conversation)
                } else {
                    ConversationListView(
                        conversations: viewModel.conversations,
                        onSelect: viewModel.selectConversation
                    )
                }

                // Input area
                MessageInputView(
                    text: $messageText,
                    onSend: { viewModel.sendMessage(messageText) }
                )
            }
            .navigationTitle("Care Coach")
        }
    }
}
```

### 10.2 Streaming Responses

```swift
class CoachViewModel: ObservableObject {
    @Published var isStreaming = false
    @Published var streamedContent = ""

    func sendMessage(_ content: String) async {
        isStreaming = true

        // Use streaming API for real-time response display
        let stream = try await coachService.chat(
            conversationId: currentConversation?.id,
            message: content
        )

        for try await chunk in stream {
            await MainActor.run {
                streamedContent += chunk
            }
        }

        isStreaming = false
    }
}
```

### 10.3 Action Handling

```swift
struct CoachActionButton: View {
    let action: CoachAction

    var body: some View {
        Button {
            handleAction(action)
        } label: {
            HStack {
                Image(systemName: action.icon)
                Text(action.label)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
    }

    func handleAction(_ action: CoachAction) {
        switch action.type {
        case .createTask:
            // Open task editor with prefilled data
        case .addQuestion:
            // Add to visit pack questions
        case .updateBinder:
            // Open binder editor
        case .callContact:
            // Initiate phone call
        }
    }
}
```

### 10.4 Disclaimer Component

```swift
struct CoachDisclaimer: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("This is not medical advice. Consult a healthcare provider for medical questions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}
```

---

## 11. System Prompt Design

```markdown
You are CuraKnot Care Coach, a supportive assistant for family caregivers. Your role is to provide practical, operational guidance for caregiving situations.

## Your Capabilities

- Help caregivers understand care situations and options
- Suggest questions to ask healthcare providers
- Provide emotional support and validation
- Help with care coordination and communication
- Suggest organizational strategies and tools

## Your Limitations

- You are NOT a doctor and cannot diagnose or prescribe
- You cannot provide emergency medical advice
- You should not make clinical recommendations
- You cannot replace professional healthcare providers

## Guidelines

1. Always acknowledge the emotional difficulty of caregiving
2. Provide practical, actionable suggestions when possible
3. Encourage consultation with healthcare providers for medical questions
4. Suggest creating tasks or updating the binder when appropriate
5. If uncertain, acknowledge it and suggest professional resources
6. For emergencies, immediately direct to 911

## Context

You have access to the patient's recent handoffs, medications, conditions, and care team. Use this context to provide personalized guidance, but always remind caregivers to verify with providers.

## Response Format

- Start with empathy or acknowledgment
- Provide clear, structured information
- Include relevant context from their care record
- Suggest concrete next steps
- End with appropriate disclaimer
```

---

## 12. Metrics

| Metric                 | Target                | Measurement                       |
| ---------------------- | --------------------- | --------------------------------- |
| Coach adoption         | 40% of active users   | Users with ≥1 conversation/month  |
| Conversations per user | 3+ per week           | Active coach users                |
| Action completion rate | 30%                   | Actions taken / actions suggested |
| User satisfaction      | 4.5+ stars            | In-app rating prompt              |
| Response quality       | <5% negative feedback | Thumbs down rate                  |
| Retention lift         | +20%                  | Compare coach users vs non-users  |

---

## 13. Risks & Mitigations

| Risk                      | Impact   | Mitigation                                              |
| ------------------------- | -------- | ------------------------------------------------------- |
| Medical advice liability  | Critical | Strong disclaimers; scope limitations; legal review     |
| Hallucinated information  | High     | Grounded in patient context; uncertainty acknowledgment |
| Privacy concerns          | High     | Clear data usage; local context; no external sharing    |
| Over-reliance on AI       | Medium   | Consistent professional referrals                       |
| Inappropriate suggestions | Medium   | Content filtering; human review sampling                |
| Cost (LLM API)            | Medium   | Rate limits; caching; efficient prompts                 |

---

## 14. Legal & Compliance

- [ ] Legal review of disclaimers and scope
- [ ] Terms of service update for AI features
- [ ] HIPAA considerations for AI processing
- [ ] User consent for context usage
- [ ] Clear documentation that this is not medical device

---

## 15. Dependencies

- LLM API (OpenAI GPT-4 or equivalent)
- Existing handoff, binder, task infrastructure
- Streaming API support
- Content moderation system

---

## 16. Testing Requirements

- [ ] Unit tests for context gathering
- [ ] Unit tests for action generation
- [ ] Integration tests for full conversation flow
- [ ] Safety testing with adversarial prompts
- [ ] Red team testing for medical advice boundaries
- [ ] User acceptance testing with real caregivers

---

## 17. Rollout Plan

1. **Alpha:** Internal team testing with synthetic patients
2. **Beta:** Opt-in for TestFlight users with feedback loop
3. **GA:** Gradual rollout with 10% → 50% → 100%
4. **Post-GA:** Proactive suggestions; advanced features

---

### Linkage

- Product: CuraKnot
- Stack: Supabase Edge Functions + LLM API + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Visit Pack (question suggestions), Operational Insights
