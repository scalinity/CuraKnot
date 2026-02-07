# Feature Spec 01 — Siri Shortcuts & Voice-First Capture

> Date: 2026-02-05 | Priority: HIGH | Phase: 1 (Foundation)
> Differentiator: Hands-free capture for time-poor caregivers

---

## 1. Problem Statement

Caregivers are constantly multitasking: driving to appointments, carrying groceries, helping with mobility, or managing multiple responsibilities simultaneously. The current capture flow requires unlocking the phone, opening the app, navigating to new handoff, and tapping record. This friction means valuable observations are lost because caregivers can't capture in the moment.

Voice assistants are ubiquitous but underutilized in caregiving apps. Siri integration enables truly hands-free capture, dramatically reducing friction and increasing handoff frequency without increasing perceived burden.

---

## 2. Differentiation and Moat

- **First caregiving app with deep Siri integration** — competitors require app interaction
- **Reduces capture friction by 80%** — voice command vs 5+ taps
- **Enables capture in previously impossible moments** — driving, hands full, bedside
- **Creates habit loop** — easier capture = more frequent use = stickier product
- **Apple ecosystem depth** — differentiates on iOS where CuraKnot is native
- **Premium lever:** Advanced Siri phrases, custom vocabulary, multi-patient disambiguation

---

## 3. Goals

- [ ] G1: Enable voice-initiated handoff capture via Siri: "Hey Siri, tell CuraKnot [message]"
- [ ] G2: Support patient selection for multi-patient circles: "Hey Siri, tell CuraKnot about Mom: [message]"
- [ ] G3: Enable read-back queries: "Hey Siri, ask CuraKnot what's Mom's next medication?"
- [ ] G4: Create draft handoffs from Siri input that can be reviewed/published in-app
- [ ] G5: Support Shortcuts app integration for custom automations
- [ ] G6: Maintain offline capability — queue Siri-initiated captures for sync

---

## 4. Non-Goals

- [ ] NG1: No full handoff editing via Siri (review happens in-app)
- [ ] NG2: No task creation via Siri in v1 (future enhancement)
- [ ] NG3: No binder editing via Siri (too complex for voice)
- [ ] NG4: No real-time transcription display during Siri capture
- [ ] NG5: No Siri Suggestions or proactive Siri (Phase 2)

---

## 5. UX Flow

### 5.1 Capture Flow

1. **Trigger:** User says "Hey Siri, tell CuraKnot [message]"
2. **Siri Response:** "Got it. I'll add that to CuraKnot."
3. **Background:** App Intents framework receives dictated text
4. **Processing:**
   - If single patient in circle → auto-assign
   - If multiple patients → use mentioned name or default patient
   - If ambiguous → create draft with "Patient: Unknown" flag
5. **Result:** Draft handoff created with status SIRI_DRAFT
6. **Notification:** Local notification: "Siri handoff saved. Tap to review."

### 5.2 Query Flow

1. **Trigger:** User says "Hey Siri, ask CuraKnot what's [patient]'s next medication?"
2. **Processing:** App Intent queries local GRDB cache
3. **Response:** Siri speaks: "[Patient] takes [med name] [dose] at [time]"

### 5.3 Review Flow

1. User opens app (via notification or manually)
2. Banner: "1 Siri handoff pending review"
3. Tap → Review screen with Siri text pre-filled
4. User can edit, add type, add attachments
5. Publish or save as draft

---

## 6. Functional Requirements

### 6.1 App Intents (iOS 16+)

```swift
// CaptureHandoffIntent.swift
struct CaptureHandoffIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Care Update"
    static var description = IntentDescription("Capture a care handoff via voice")

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Patient Name", default: nil)
    var patientName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log '\(\.$message)' for \(\.$patientName)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Create draft handoff
        // Return confirmation
    }
}
```

### 6.2 Supported Phrases

| Phrase Pattern                                    | Intent           | Parameters           |
| ------------------------------------------------- | ---------------- | -------------------- |
| "Tell CuraKnot [message]"                         | CaptureHandoff   | message              |
| "Tell CuraKnot about [patient]: [message]"        | CaptureHandoff   | message, patientName |
| "Log care update: [message]"                      | CaptureHandoff   | message              |
| "Ask CuraKnot what's [patient]'s next medication" | QueryMedication  | patientName          |
| "Ask CuraKnot for [patient]'s emergency contacts" | QueryContacts    | patientName          |
| "Ask CuraKnot when was the last handoff"          | QueryLastHandoff | -                    |

### 6.3 Draft Handoff Handling

- [ ] Siri-created drafts have `source: 'SIRI'` and `status: 'SIRI_DRAFT'`
- [ ] Siri drafts expire after 7 days if not reviewed (configurable)
- [ ] Siri drafts appear in Timeline with distinct visual treatment
- [ ] Badge count includes pending Siri drafts
- [ ] Push notification option for Siri draft reminders

### 6.4 Patient Disambiguation

- [ ] If message contains patient name → match against circle patients
- [ ] If no name and single patient → auto-assign
- [ ] If no name and multiple patients → use default patient setting
- [ ] If ambiguous → flag for manual assignment during review
- [ ] Support nicknames/aliases (Mom, Dad, Grandma) via patient settings

### 6.5 Offline Support

- [ ] Siri intents work offline via App Intents framework
- [ ] Drafts stored in local GRDB immediately
- [ ] Sync to Supabase when connectivity restored
- [ ] Query intents use local cache (may be stale — include freshness indicator)

---

## 7. Data Model

### 7.1 Handoff Extensions

```sql
-- Add source tracking to handoffs
ALTER TABLE handoffs
ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'APP';
-- APP | SIRI | WATCH | SHORTCUT | HELPER_PORTAL

ALTER TABLE handoffs
ADD COLUMN IF NOT EXISTS siri_raw_text text;
-- Original Siri dictation before any processing

-- Add Siri draft status
-- Existing status enum: DRAFT | PUBLISHED
-- Add: SIRI_DRAFT (pending user review)
```

### 7.2 Patient Aliases

```sql
CREATE TABLE IF NOT EXISTS patient_aliases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    alias text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(patient_id, alias)
);

-- Index for fast lookup
CREATE INDEX idx_patient_aliases_alias ON patient_aliases(lower(alias));
```

### 7.3 User Preferences

```sql
-- Add to users table or user_preferences
ALTER TABLE users
ADD COLUMN IF NOT EXISTS siri_settings_json jsonb DEFAULT '{
    "enabled": true,
    "defaultPatientId": null,
    "confirmBeforeCapture": false,
    "notifyOnCapture": true,
    "draftExpirationDays": 7
}'::jsonb;
```

---

## 8. RLS & Security

- [ ] Siri intents run in app extension context with same auth
- [ ] Patient aliases readable by circle members; writable by contributors+
- [ ] Siri drafts follow same RLS as regular handoffs
- [ ] Query intents only return data user has access to
- [ ] No PHI in Siri response text (use initials/codes if needed)

---

## 9. Edge Functions

No new Edge Functions required — Siri integration is entirely client-side using local GRDB cache and existing sync infrastructure.

---

## 10. iOS Implementation Notes

### 10.1 App Intents Framework

```swift
// AppShortcuts.swift
struct CuraKnotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureHandoffIntent(),
            phrases: [
                "Tell \(.applicationName) \(\.$message)",
                "Tell \(.applicationName) about \(\.$patientName) \(\.$message)",
                "Log care update in \(.applicationName)",
            ],
            shortTitle: "Log Care Update",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: QueryMedicationIntent(),
            phrases: [
                "Ask \(.applicationName) what's \(\.$patientName)'s next medication",
                "Ask \(.applicationName) about medications",
            ],
            shortTitle: "Check Medications",
            systemImageName: "pill"
        )
    }
}
```

### 10.2 Shortcuts App Integration

- [ ] Expose all intents to Shortcuts app
- [ ] Support parameterized shortcuts for power users
- [ ] Example: "Morning check-in" shortcut that captures with template text

### 10.3 Background Processing

- [ ] Use BGAppRefreshTask for Siri draft sync
- [ ] Handle app launch from Siri intent gracefully
- [ ] Preserve draft if app crashes during processing

### 10.4 Voice Feedback

- [ ] Siri confirms capture: "Got it. I'll add that to CuraKnot."
- [ ] Siri confirms query: Speaks answer naturally
- [ ] Error handling: "I couldn't reach CuraKnot. Try again later."

---

## 11. Metrics

| Metric                   | Target               | Measurement                      |
| ------------------------ | -------------------- | -------------------------------- |
| Siri capture adoption    | 30% of active users  | Users with ≥1 Siri handoff/month |
| Capture frequency lift   | +25% handoffs/week   | Compare Siri users vs non-Siri   |
| Siri draft review rate   | 80% within 24h       | Drafts reviewed / drafts created |
| Query usage              | 2+ queries/user/week | Active Siri query users          |
| Siri phrase success rate | 95%                  | Successful intent matches        |

---

## 12. Risks & Mitigations

| Risk                              | Impact | Mitigation                                        |
| --------------------------------- | ------ | ------------------------------------------------- |
| Siri transcription errors         | Medium | Show draft for review; don't auto-publish         |
| Patient name misrecognition       | High   | Support aliases; always confirm in review         |
| Privacy concerns (Siri listening) | Medium | Clear onboarding; local processing where possible |
| iOS version fragmentation         | Low    | Require iOS 16+ for Siri features                 |
| Siri availability (Siri disabled) | Low    | Graceful fallback; in-app voice still works       |

---

## 13. Dependencies

- iOS 16+ App Intents framework
- Existing GRDB local database
- Existing sync infrastructure
- Patient model with aliases support

---

## 14. Testing Requirements

- [ ] Unit tests for intent parameter parsing
- [ ] Unit tests for patient name matching/disambiguation
- [ ] Integration tests for draft creation flow
- [ ] Integration tests for query responses
- [ ] UI tests for draft review flow
- [ ] Manual testing with actual Siri (simulator limitations)

---

## 15. Rollout Plan

1. **Alpha:** Internal testing with team circles
2. **Beta:** TestFlight users with explicit opt-in
3. **GA:** Ship with iOS app update; feature flag for gradual rollout
4. **Marketing:** "Hey Siri" demo videos; App Store feature request

---

### Linkage

- Product: CuraKnot
- Stack: iOS App Intents + GRDB + Supabase sync
- Baseline: `./CuraKnot-spec.md`
- Related: Watch App (shares App Intents infrastructure)
