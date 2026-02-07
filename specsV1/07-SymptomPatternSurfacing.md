# Feature Spec 07 — Non-Clinical Symptom Pattern Surfacing

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 2 (AI Differentiation)
> Differentiator: Proactive insights from unstructured data — most apps are passive databases

---

## 1. Problem Statement

Caregivers document daily observations but rarely have time to review patterns across weeks or months. Important trends hide in plain sight: "Mom has been tired every day this week" or "appetite dropped after the medication change." These patterns, once visible, prompt earlier conversations with providers and better care decisions.

AI can analyze handoff text to surface recurring themes without making clinical claims. This transforms CuraKnot from a passive record into an active awareness tool.

---

## 2. Differentiation and Moat

- **Proactive vs passive** — surfaces insights users didn't ask for
- **Pattern detection at scale** — analyzes all handoffs automatically
- **Non-clinical framing** — operational awareness, not diagnosis
- **Longitudinal value** — data compounds over time
- **Reduces cognitive load** — AI remembers patterns humans forget
- **Premium lever:** Advanced analytics, trend reports, alerting

---

## 3. Goals

- [ ] G1: Automatically scan handoffs for recurring themes and concerns
- [ ] G2: Surface patterns with clear, non-clinical language
- [ ] G3: Show correlation with events (medication changes, facility transitions)
- [ ] G4: Integrate patterns into Visit Pack and Coach conversations
- [ ] G5: Allow users to track specific concerns manually
- [ ] G6: Respect user preferences for notification frequency

---

## 4. Non-Goals

- [ ] NG1: No clinical diagnosis or medical interpretation
- [ ] NG2: No symptom severity scoring
- [ ] NG3: No predictive health outcomes
- [ ] NG4: No automated provider alerts (liability)
- [ ] NG5: No replacement for medical monitoring

---

## 5. UX Flow

### 5.1 Pattern Discovery

```
┌─────────────────────────────────┐
│ Insights for Mom                │
│ ═══════════════════════════════│
│                                 │
│ 📊 Patterns Detected            │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 😴 "Tired/Fatigue"          │ │
│ │ Mentioned 5 times in 7 days │ │
│ │                             │ │
│ │ [Timeline visualization]    │ │
│ │ ● ● ● ○ ● ○ ●              │ │
│ │ M T W T F S S              │ │
│ │                             │ │
│ │ First mention: Jan 28       │ │
│ │ Related: Lisinopril started │ │
│ │          Jan 25             │ │
│ │                             │ │
│ │ [View Handoffs] [Track]     │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🍽️ "Appetite Changes"       │ │
│ │ Mentioned 3 times in 14 days│ │
│ │                             │ │
│ │ Trend: Decreasing           │ │
│ │                             │ │
│ │ [View Handoffs] [Dismiss]   │ │
│ └─────────────────────────────┘ │
│                                 │
│ ⚠️ These are observations, not │
│ medical assessments. Discuss   │
│ concerns with providers.       │
└─────────────────────────────────┘
```

### 5.2 Pattern Detail View

```
┌─────────────────────────────────┐
│ ← Pattern: Tiredness            │
│ ═══════════════════════════════│
│                                 │
│ 📈 Frequency Over Time          │
│ [Chart showing mentions/week]   │
│                                 │
│ 📝 Recent Mentions              │
│ ┌─────────────────────────────┐ │
│ │ Feb 3: "Mom seemed very     │ │
│ │ tired today, slept most of  │ │
│ │ the afternoon"              │ │
│ │ — Jane                      │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ Feb 1: "Low energy, didn't  │ │
│ │ want to do PT exercises"    │ │
│ │ — Mike                      │ │
│ └─────────────────────────────┘ │
│                                 │
│ 🔗 Possibly Related Events      │
│ • Lisinopril started (Jan 25)  │
│ • Facility visit (Jan 27)      │
│                                 │
│ 💡 Suggested Actions            │
│ [Add to Visit Pack Questions]   │
│ [Ask Care Coach]                │
│ [Start Tracking]                │
└─────────────────────────────────┘
```

### 5.3 Manual Tracking

- User can "Track" any concern
- Shows daily prompt: "How was [concern] today?"
- Builds structured tracking data over time

---

## 6. Functional Requirements

### 6.1 Pattern Detection Engine

**Text Analysis:**

- [ ] Extract symptom/concern mentions from handoff text
- [ ] Normalize variations (tired, fatigue, exhausted → TIREDNESS)
- [ ] Identify sentiment and severity words (very, slight, worse)
- [ ] Detect temporal markers (today, this week, since Tuesday)

**Pattern Recognition:**

- [ ] Count mentions per time period (day, week, month)
- [ ] Detect increasing/decreasing trends
- [ ] Identify new patterns (first mention in 30 days)
- [ ] Flag sudden changes (spike in mentions)

**Correlation Detection:**

- [ ] Match pattern start dates with medication changes
- [ ] Match with facility transitions
- [ ] Match with care plan changes
- [ ] Match with other pattern onsets

### 6.2 Concern Categories

| Category       | Example Terms                         | Icon |
| -------------- | ------------------------------------- | ---- |
| Energy/Fatigue | tired, exhausted, no energy, sluggish | 😴   |
| Appetite       | not eating, no appetite, eating well  | 🍽️   |
| Sleep          | insomnia, sleeping a lot, restless    | 🌙   |
| Pain           | hurting, aches, discomfort, pain      | 😣   |
| Mood           | sad, anxious, irritable, happy        | 😊   |
| Mobility       | walking, balance, fell, unsteady      | 🚶   |
| Cognition      | confused, forgetful, alert, sharp     | 🧠   |
| Digestion      | nausea, constipation, upset stomach   | 🫄   |
| Breathing      | short of breath, coughing, wheezing   | 💨   |
| Skin           | rash, bruise, swelling, wound         | 🩹   |

### 6.3 Non-Clinical Framing

**Language Guidelines:**

- ✅ "You mentioned tiredness 5 times this week"
- ❌ "Patient shows signs of fatigue syndrome"
- ✅ "This pattern started around when Lisinopril was added"
- ❌ "Lisinopril may be causing fatigue"
- ✅ "Consider discussing this pattern with the doctor"
- ❌ "You should stop taking this medication"

### 6.4 Notification and Surfacing

- [ ] Patterns surfaced in Insights section (not intrusive)
- [ ] Weekly digest includes notable patterns
- [ ] Visit Pack generation highlights relevant patterns
- [ ] Care Coach references patterns in conversations
- [ ] Optional push notification for significant new patterns

### 6.5 User Controls

- [ ] Dismiss patterns (won't show again)
- [ ] Track patterns (explicit monitoring)
- [ ] Adjust sensitivity (more/fewer notifications)
- [ ] Disable pattern detection entirely

---

## 7. Data Model

### 7.1 Detected Patterns

```sql
CREATE TABLE IF NOT EXISTS detected_patterns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,

    -- Pattern identification
    concern_category text NOT NULL,  -- TIREDNESS, APPETITE, etc.
    concern_keywords text[] NOT NULL,  -- Matched terms
    pattern_hash text NOT NULL,  -- For deduplication

    -- Metrics
    mention_count int NOT NULL,
    first_mention_at timestamptz NOT NULL,
    last_mention_at timestamptz NOT NULL,
    trend text,  -- INCREASING | DECREASING | STABLE | NEW

    -- Correlations
    correlated_events_json jsonb,  -- Medication changes, etc.

    -- Status
    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | DISMISSED | TRACKING
    dismissed_by uuid,
    dismissed_at timestamptz,

    -- Handoff references
    source_handoff_ids uuid[] NOT NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(circle_id, patient_id, pattern_hash)
);

CREATE INDEX idx_detected_patterns_patient ON detected_patterns(patient_id, status, updated_at DESC);
```

### 7.2 Pattern Mentions

```sql
CREATE TABLE IF NOT EXISTS pattern_mentions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id uuid NOT NULL REFERENCES detected_patterns(id) ON DELETE CASCADE,
    handoff_id uuid NOT NULL REFERENCES handoffs(id) ON DELETE CASCADE,
    matched_text text NOT NULL,  -- The actual text that matched
    severity_indicator text,  -- MILD | MODERATE | SEVERE | NONE
    mentioned_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_pattern_mentions_pattern ON pattern_mentions(pattern_id, mentioned_at DESC);
```

### 7.3 Manual Tracking

```sql
CREATE TABLE IF NOT EXISTS tracked_concerns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    concern_name text NOT NULL,
    concern_category text,
    tracking_prompt text,  -- "How was [concern] today?"

    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | PAUSED | RESOLVED
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tracking_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tracked_concern_id uuid NOT NULL REFERENCES tracked_concerns(id) ON DELETE CASCADE,
    recorded_by uuid NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),

    rating int,  -- 1-5 scale if applicable
    notes text,
    handoff_id uuid REFERENCES handoffs(id)
);
```

---

## 8. RLS & Security

- [ ] detected_patterns: Readable by circle members
- [ ] pattern_mentions: Access through pattern
- [ ] tracked_concerns: Readable by circle members; writable by contributors+
- [ ] No patterns shared outside circle
- [ ] Audit logging for pattern generation

---

## 9. Edge Functions

### 9.1 analyze-handoff-patterns (Cron)

```typescript
// Runs daily or on handoff publish
// Scans handoffs and updates patterns

interface PatternAnalysisJob {
  patientId: string;
  timeRangeDays: number; // Default 30
}

interface PatternResult {
  concernCategory: string;
  keywords: string[];
  mentions: {
    handoffId: string;
    text: string;
    date: Date;
  }[];
  trend: "INCREASING" | "DECREASING" | "STABLE" | "NEW";
  correlatedEvents: CorrelatedEvent[];
}
```

### 9.2 extract-concerns

```typescript
// Internal function for NLP extraction

interface ConcernExtraction {
  text: string;
  category: string;
  normalizedTerm: string;
  severityIndicator?: string;
  temporalContext?: string;
}

async function extractConcerns(
  handoffText: string,
): Promise<ConcernExtraction[]>;
```

### 9.3 correlate-events

```typescript
// Find related timeline events

interface CorrelatedEvent {
  eventType:
    | "MEDICATION_CHANGE"
    | "FACILITY_TRANSITION"
    | "CARE_PLAN_CHANGE"
    | "OTHER_PATTERN";
  eventId: string;
  eventDescription: string;
  eventDate: Date;
  correlationStrength: "STRONG" | "POSSIBLE"; // Based on timing
}
```

---

## 10. iOS Implementation Notes

### 10.1 Insights View

```swift
struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                if viewModel.patterns.isEmpty {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No Patterns Yet",
                        message: "Patterns will appear as you log more handoffs."
                    )
                } else {
                    Section("Detected Patterns") {
                        ForEach(viewModel.patterns) { pattern in
                            PatternCard(pattern: pattern)
                        }
                    }

                    if !viewModel.trackedConcerns.isEmpty {
                        Section("Tracking") {
                            ForEach(viewModel.trackedConcerns) { concern in
                                TrackedConcernRow(concern: concern)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Insights")
        }
    }
}
```

### 10.2 Pattern Card

```swift
struct PatternCard: View {
    let pattern: DetectedPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(pattern.icon)
                    .font(.title2)
                Text(pattern.displayName)
                    .font(.headline)
                Spacer()
                TrendBadge(trend: pattern.trend)
            }

            Text("Mentioned \(pattern.mentionCount) times in \(pattern.timeRangeDescription)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Mini timeline
            MentionTimeline(mentions: pattern.recentMentions)

            if let correlation = pattern.primaryCorrelation {
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(.orange)
                    Text("Possibly related: \(correlation.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("View Details") {
                    // Navigate to detail
                }
                .buttonStyle(.bordered)

                Spacer()

                Menu {
                    Button("Track This", systemImage: "pin") {}
                    Button("Dismiss", systemImage: "xmark") {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
```

### 10.3 Disclaimer Banner

```swift
struct InsightsDisclaimer: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text("Patterns are observations from your handoffs, not medical assessments. Discuss concerns with healthcare providers.")
                .font(.caption)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}
```

---

## 11. Metrics

| Metric             | Target                      | Measurement                    |
| ------------------ | --------------------------- | ------------------------------ |
| Patterns surfaced  | 2+ per active patient/month | Patterns generated             |
| Pattern engagement | 30%                         | Patterns viewed in detail      |
| Pattern to action  | 20%                         | Patterns → Visit Pack or Coach |
| Tracking adoption  | 15% of users                | Users with active tracking     |
| Dismiss rate       | <30%                        | Dismissed / surfaced           |
| User satisfaction  | 4.0+                        | In-feature rating              |

---

## 12. Risks & Mitigations

| Risk                    | Impact   | Mitigation                                |
| ----------------------- | -------- | ----------------------------------------- |
| False positives         | Medium   | Show evidence; allow dismiss              |
| Clinical interpretation | Critical | Strict non-clinical language; disclaimers |
| Information overload    | Medium   | Prioritization; digest format             |
| Privacy concerns        | Medium   | Patient-specific; circle only             |
| Missed patterns         | Low      | Supplement with user tracking             |

---

## 13. Dependencies

- Handoff text data (existing)
- Medication change tracking (binder)
- NLP/LLM for text analysis
- Shared infrastructure with Care Coach

---

## 14. Testing Requirements

- [ ] Unit tests for concern extraction
- [ ] Unit tests for pattern aggregation
- [ ] Unit tests for correlation detection
- [ ] Integration tests for full pipeline
- [ ] Safety testing for clinical language
- [ ] User testing for relevance

---

## 15. Rollout Plan

1. **Alpha:** Basic pattern detection for 3 categories
2. **Beta:** Full category support; correlation detection
3. **GA:** Manual tracking; Visit Pack integration
4. **Post-GA:** Advanced analytics; alerting

---

### Linkage

- Product: CuraKnot
- Stack: Supabase Edge Functions + NLP/LLM + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: AI Care Coach, Smart Appointment Questions, Operational Insights
