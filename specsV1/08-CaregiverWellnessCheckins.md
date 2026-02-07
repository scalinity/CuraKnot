# Feature Spec 08 — Caregiver Wellness & Burnout Detection

> Date: 2026-02-05 | Priority: HIGH | Phase: 2 (AI Differentiation)
> Differentiator: First caregiving app that actively cares for the caregiver

---

## 1. Problem Statement

Caregiving is exhausting. 40% of caregivers report symptoms of depression. 53% report declining health. Yet every caregiving app focuses exclusively on the patient. Caregivers burn out in silence, feeling guilty for having their own needs.

CuraKnot has unique signals about caregiver wellbeing: handoff frequency, late-night entries, sentiment, task completion rates. Combined with optional check-ins, AI can surface burnout risks and prompt self-care actions — showing caregivers they matter too.

---

## 2. Differentiation and Moat

- **First to care for the caregiver** — unique market position
- **Reduces caregiver burnout** — measurable health outcome
- **Creates emotional loyalty** — users feel seen and supported
- **PR and marketing story** — "the app that cares about you"
- **Passive signals** — works without extra input burden
- **Premium lever:** Advanced wellness tracking, professional resources, respite suggestions

---

## 3. Goals

- [ ] G1: Optional weekly wellness check-ins measuring stress, sleep, capacity
- [ ] G2: Passive signal analysis from app usage patterns
- [ ] G3: Surface burnout risks with empathetic, actionable prompts
- [ ] G4: Integrate wellness insights into delegation suggestions
- [ ] G5: Connect to resources (articles, hotlines, respite options)
- [ ] G6: Private by default — wellness data not shared with circle

---

## 4. Non-Goals

- [ ] NG1: No therapy or mental health treatment
- [ ] NG2: No clinical depression screening or diagnosis
- [ ] NG3: No mandatory check-ins (always optional)
- [ ] NG4: No shaming or guilt-inducing language
- [ ] NG5: No data sharing without explicit consent

---

## 5. UX Flow

### 5.1 Onboarding Prompt

```
┌─────────────────────────────────┐
│                                 │
│  Caregiving is hard work.       │
│  We want to support YOU too.    │
│                                 │
│  Would you like occasional      │
│  wellness check-ins? They're    │
│  private and take 30 seconds.   │
│                                 │
│  [Yes, I'd like that]           │
│                                 │
│  [Maybe later]                  │
│                                 │
└─────────────────────────────────┘
```

### 5.2 Weekly Check-In

```
┌─────────────────────────────────┐
│ How are you doing this week?    │
│ ═══════════════════════════════│
│                                 │
│ Your stress level:              │
│ 😌    😐    😟    😰    😫     │
│ Low        Medium        High   │
│                                 │
│ Your sleep quality:             │
│ 😴    🥱    😶    😵    💀     │
│ Great      Ok           Poor    │
│                                 │
│ Your capacity this week:        │
│ 💪    ✋    🤏    🫠           │
│ Full   Some  Low   Running on E │
│                                 │
│ Anything else on your mind?     │
│ ┌─────────────────────────────┐ │
│ │ [Optional note...]          │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Submit]                        │
│                                 │
│ This is private. Only you can   │
│ see your wellness data.         │
└─────────────────────────────────┘
```

### 5.3 Wellness Insight (Proactive)

```
┌─────────────────────────────────┐
│ 💙 Caring for You               │
│ ═══════════════════════════════│
│                                 │
│ We noticed you've logged 14     │
│ handoffs this week, including   │
│ several late at night.          │
│                                 │
│ You're doing so much. Could     │
│ someone else cover tomorrow?    │
│                                 │
│ [Ask Jane to help]              │
│                                 │
│ [I'm okay, thanks]              │
│                                 │
│ [Take me to resources]          │
│                                 │
└─────────────────────────────────┘
```

### 5.4 Wellness Dashboard

```
┌─────────────────────────────────┐
│ Your Wellness                   │
│ ═══════════════════════════════│
│                                 │
│ 📊 Recent Check-ins             │
│ ┌─────────────────────────────┐ │
│ │ Stress:  ▓▓▓▓░░░░░░ 4/10   │ │
│ │ Sleep:   ▓▓▓░░░░░░░ 3/10   │ │
│ │ Capacity:▓▓▓▓▓░░░░░ 5/10   │ │
│ └─────────────────────────────┘ │
│                                 │
│ 📈 4-Week Trend                 │
│ [Sparkline charts]              │
│                                 │
│ 💡 Suggestions                  │
│ • Your sleep has declined.      │
│   Consider a bedtime routine.   │
│ • You haven't had a break in    │
│   3 weeks. Respite matters.     │
│                                 │
│ 📚 Resources                    │
│ [Caregiver Support Hotline]     │
│ [Self-Care Articles]            │
│ [Find Respite Care]             │
│                                 │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Check-In System

**Check-In Frequency:**

- [ ] Default: Weekly (configurable: daily, bi-weekly)
- [ ] Notification at user-preferred time
- [ ] Skip/snooze option without guilt
- [ ] Streak tracking (optional, non-gamified)

**Check-In Questions:**
| Dimension | Scale | Description |
|-----------|-------|-------------|
| Stress | 1-5 emoji | Current stress level |
| Sleep | 1-5 emoji | Sleep quality last few nights |
| Capacity | 1-4 emoji | Available bandwidth |
| Notes | Free text | Optional open-ended |

### 6.2 Passive Signal Analysis

**App Usage Signals:**

- [ ] Handoff frequency (sudden increase = more burden)
- [ ] Late-night activity (entries after 10pm)
- [ ] Handoff sentiment (negative word patterns)
- [ ] Task completion rate (declining = overwhelmed)
- [ ] Time between handoffs (erratic = crisis mode)

**Pattern Detection:**

```typescript
interface WellnessSignals {
  handoffCountLast7Days: number;
  handoffCountPrior7Days: number;
  lateNightEntries: number; // After 10pm
  averageSentiment: number; // -1 to 1
  taskCompletionRate: number;
  daysWithoutBreak: number;
}

function assessBurnoutRisk(signals: WellnessSignals): RiskLevel {
  let score = 0;

  if (signals.handoffCountLast7Days > signals.handoffCountPrior7Days * 1.5)
    score += 2;
  if (signals.lateNightEntries > 3) score += 2;
  if (signals.averageSentiment < -0.3) score += 1;
  if (signals.taskCompletionRate < 0.5) score += 1;
  if (signals.daysWithoutBreak > 14) score += 2;

  return score >= 5 ? "HIGH" : score >= 3 ? "MODERATE" : "LOW";
}
```

### 6.3 Intervention Prompts

**Trigger Conditions:**
| Trigger | Prompt |
|---------|--------|
| High handoff week | "You've logged X handoffs this week. That's a lot! Could someone else cover tomorrow?" |
| Late night activity | "We noticed late-night entries. Are you getting enough rest?" |
| Declining check-in scores | "Your stress has been rising. What would help right now?" |
| Long time since break | "It's been 3 weeks since you had a day off. Respite matters." |
| Negative sentiment spike | "It sounds like a tough week. We're here for you." |

### 6.4 Resource Integration

- [ ] Curated self-care articles
- [ ] Caregiver support hotlines
- [ ] Respite care finder (links to Feature 13)
- [ ] Local caregiver support groups
- [ ] Mental health resources with crisis lines

### 6.5 Delegation Integration

- [ ] Surface wellness in delegation suggestions
- [ ] "Jane has more capacity this week" (with consent)
- [ ] Workload rebalancing prompts
- [ ] Shift coverage suggestions

### 6.6 Privacy Controls

- [ ] Wellness data private by default
- [ ] Explicit opt-in to share capacity with circle
- [ ] Delete wellness history anytime
- [ ] Export personal wellness data

---

## 7. Data Model

### 7.1 Wellness Check-Ins

```sql
CREATE TABLE IF NOT EXISTS wellness_checkins (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Responses (1-5 scale)
    stress_level int CHECK (stress_level BETWEEN 1 AND 5),
    sleep_quality int CHECK (sleep_quality BETWEEN 1 AND 5),
    capacity_level int CHECK (capacity_level BETWEEN 1 AND 4),
    notes text,

    -- Metadata
    prompted_at timestamptz,  -- When we asked
    completed_at timestamptz NOT NULL DEFAULT now(),
    skipped boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now()
);

-- User can only see their own check-ins
CREATE POLICY "Users own checkins" ON wellness_checkins
    FOR ALL USING (user_id = auth.uid());
```

### 7.2 Wellness Signals (Computed)

```sql
CREATE TABLE IF NOT EXISTS wellness_signals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    computed_at timestamptz NOT NULL DEFAULT now(),

    -- Computed metrics
    handoff_count_7d int NOT NULL DEFAULT 0,
    late_night_entries_7d int NOT NULL DEFAULT 0,
    average_sentiment float,
    task_completion_rate float,
    days_since_break int,

    -- Risk assessment
    burnout_risk text NOT NULL DEFAULT 'LOW',  -- LOW | MODERATE | HIGH
    risk_factors text[],

    UNIQUE(user_id, computed_at::date)
);
```

### 7.3 Wellness Interventions

```sql
CREATE TABLE IF NOT EXISTS wellness_interventions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    intervention_type text NOT NULL,  -- PROMPT | NOTIFICATION | RESOURCE
    trigger_reason text NOT NULL,
    content_json jsonb NOT NULL,

    -- Response tracking
    shown_at timestamptz NOT NULL DEFAULT now(),
    response text,  -- ACCEPTED | DISMISSED | IGNORED
    responded_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.4 User Preferences

```sql
-- Add to users table
ALTER TABLE users
ADD COLUMN IF NOT EXISTS wellness_settings_json jsonb DEFAULT '{
    "enabled": false,
    "checkInFrequency": "WEEKLY",
    "checkInDay": "SUNDAY",
    "checkInTime": "20:00",
    "passiveAnalysis": true,
    "proactivePrompts": true,
    "shareCapacityWithCircle": false
}'::jsonb;
```

---

## 8. RLS & Security

- [ ] All wellness data accessible only by the user who created it
- [ ] No circle-level access unless explicitly shared
- [ ] No admin/support access to wellness data
- [ ] Encrypted at rest
- [ ] GDPR-compliant data export and deletion

---

## 9. Edge Functions

### 9.1 compute-wellness-signals (Cron)

```typescript
// Runs daily for each active user
// Computes passive signals from app usage

interface ComputeSignalsJob {
  userId: string;
}

async function computeSignals(userId: string): Promise<WellnessSignals> {
  // Query handoffs, tasks, etc.
  // Compute metrics
  // Assess risk level
  // Store in wellness_signals
}
```

### 9.2 trigger-wellness-intervention

```typescript
// Called when risk thresholds exceeded
// Creates intervention record and sends notification

interface TriggerInterventionRequest {
  userId: string;
  triggerReason: string;
  interventionType: "PROMPT" | "NOTIFICATION";
}
```

### 9.3 wellness-resources

```typescript
// Returns curated resources based on user situation

interface ResourcesRequest {
  userId: string;
  category?: "SELF_CARE" | "SUPPORT_GROUPS" | "RESPITE" | "CRISIS";
  location?: string; // For local resources
}

interface ResourcesResponse {
  resources: Resource[];
  hotlines: Hotline[];
}
```

---

## 10. iOS Implementation Notes

### 10.1 Check-In Flow

```swift
struct WellnessCheckInView: View {
    @StateObject private var viewModel = WellnessCheckInViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("How are you doing this week?")
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Stress
                    EmojiScaleQuestion(
                        title: "Your stress level:",
                        options: ["😌", "😐", "😟", "😰", "😫"],
                        selection: $viewModel.stressLevel
                    )

                    // Sleep
                    EmojiScaleQuestion(
                        title: "Your sleep quality:",
                        options: ["😴", "🥱", "😶", "😵", "💀"],
                        selection: $viewModel.sleepQuality
                    )

                    // Capacity
                    EmojiScaleQuestion(
                        title: "Your capacity this week:",
                        options: ["💪", "✋", "🤏", "🫠"],
                        selection: $viewModel.capacityLevel
                    )

                    // Notes
                    VStack(alignment: .leading) {
                        Text("Anything else on your mind?")
                            .font(.subheadline)
                        TextEditor(text: $viewModel.notes)
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    }

                    // Privacy note
                    Label("This is private. Only you can see your wellness data.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Submit") {
                        viewModel.submit()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Wellness Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        viewModel.skip()
                        dismiss()
                    }
                }
            }
        }
    }
}
```

### 10.2 Intervention Prompt

```swift
struct WellnessInterventionView: View {
    let intervention: WellnessIntervention
    let onResponse: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("💙")
                    .font(.title)
                Text("Caring for You")
                    .font(.headline)
                Spacer()
            }

            Text(intervention.message)
                .font(.body)

            ForEach(intervention.actions, id: \.id) { action in
                Button(action.label) {
                    onResponse(action.id)
                }
                .buttonStyle(.bordered)
            }

            Button("I'm okay, thanks") {
                onResponse("DISMISSED")
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
}
```

### 10.3 Wellness Dashboard

```swift
struct WellnessDashboardView: View {
    @StateObject private var viewModel = WellnessDashboardViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Recent Check-Ins") {
                    WellnessScoreCard(
                        title: "Stress",
                        value: viewModel.latestStress,
                        trend: viewModel.stressTrend
                    )
                    WellnessScoreCard(
                        title: "Sleep",
                        value: viewModel.latestSleep,
                        trend: viewModel.sleepTrend
                    )
                    WellnessScoreCard(
                        title: "Capacity",
                        value: viewModel.latestCapacity,
                        trend: viewModel.capacityTrend
                    )
                }

                Section("Suggestions") {
                    ForEach(viewModel.suggestions) { suggestion in
                        SuggestionRow(suggestion: suggestion)
                    }
                }

                Section("Resources") {
                    NavigationLink("Caregiver Support Hotline") {
                        ResourceDetailView(resource: .hotline)
                    }
                    NavigationLink("Self-Care Articles") {
                        ResourceListView(category: .selfCare)
                    }
                    NavigationLink("Find Respite Care") {
                        RespiteCareFinderView()
                    }
                }
            }
            .navigationTitle("Your Wellness")
        }
    }
}
```

---

## 11. Metrics

| Metric                   | Target          | Measurement                            |
| ------------------------ | --------------- | -------------------------------------- |
| Wellness opt-in rate     | 40% of users    | Users enabling wellness features       |
| Check-in completion      | 60% weekly      | Completed / prompted                   |
| Intervention engagement  | 30%             | Accepted / shown                       |
| Burnout risk reduction   | Track over time | Users moving from HIGH to MODERATE/LOW |
| Resource clicks          | Track usage     | Clicks on resources                    |
| NPS for wellness feature | 50+             | Feature-specific NPS                   |

---

## 12. Risks & Mitigations

| Risk                 | Impact | Mitigation                                       |
| -------------------- | ------ | ------------------------------------------------ |
| Feels intrusive      | High   | Opt-in only; easy disable; respectful tone       |
| Clinical liability   | Medium | Not therapy; clear disclaimers; crisis referrals |
| Data sensitivity     | High   | Private by default; encryption; deletion         |
| Guilt/shame triggers | High   | Careful language; no negative framing            |
| Notification fatigue | Medium | Configurable frequency; smart timing             |

---

## 13. Dependencies

- User activity data (handoffs, tasks)
- Notification infrastructure
- Sentiment analysis (can use simple keyword approach)
- Resource database (curated content)

---

## 14. Testing Requirements

- [ ] Unit tests for signal computation
- [ ] Unit tests for risk assessment
- [ ] Integration tests for check-in flow
- [ ] UI tests for dashboard
- [ ] Sensitivity review for all copy
- [ ] User testing with real caregivers

---

## 15. Rollout Plan

1. **Alpha:** Check-ins only, no passive analysis
2. **Beta:** Add passive signals and interventions
3. **GA:** Full feature with resources
4. **Post-GA:** Delegation integration; advanced analytics

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI + Push Notifications
- Baseline: `./CuraKnot-spec.md`
- Related: Delegation Intelligence, Respite Care Finder, AI Care Coach
