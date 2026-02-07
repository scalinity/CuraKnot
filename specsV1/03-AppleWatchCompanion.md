# Feature Spec 03 — Apple Watch Companion App

> Date: 2026-02-05 | Priority: HIGH | Phase: 1 (Foundation)
> Differentiator: Apple ecosystem depth; no caregiving app has meaningful Watch presence

---

## 1. Problem Statement

Caregivers need instant access to critical information without fumbling for their phone. During hands-on care moments — helping with transfers, administering medication, responding to emergencies — pulling out a phone is impractical or impossible. The Apple Watch is always accessible but no caregiving app leverages it effectively.

A Watch companion enables glanceable information, quick capture, and emergency access at the exact moments when caregivers need it most.

---

## 2. Differentiation and Moat

- **No competitor has a Watch app** — unique in caregiving category
- **Apple ecosystem lock-in** — deepens platform differentiation
- **Glanceable design** — surface critical info without app launch
- **Quick capture** — voice handoffs from wrist
- **Emergency ready** — emergency card accessible instantly
- **Premium lever:** Advanced complications, haptic task reminders

---

## 3. Goals

- [ ] G1: Watch app with patient overview and recent handoffs
- [ ] G2: Voice capture for handoffs directly from Watch
- [ ] G3: Complications showing next task, last handoff, emergency card access
- [ ] G4: Haptic notifications for task reminders and new handoffs
- [ ] G5: Emergency card display with critical patient info
- [ ] G6: Offline support with local data cache

---

## 4. Non-Goals

- [ ] NG1: No full handoff reading/editing (screen too small)
- [ ] NG2: No binder management (complexity inappropriate for Watch)
- [ ] NG3: No circle management or settings
- [ ] NG4: No attachment viewing (photos, PDFs)
- [ ] NG5: No task creation (voice handoff can suggest tasks)

---

## 5. UX Flow

### 5.1 Watch App Home

```
┌─────────────────────┐
│   [Patient Avatar]  │
│      Mom            │
│   ─────────────────│
│   Next Task:        │
│   Give medication   │
│   Due in 2 hours    │
│   ─────────────────│
│   Last Handoff:     │
│   "Good appetite    │
│    today..."        │
│   3 hours ago       │
│   ─────────────────│
│  [Mic] New Handoff  │
└─────────────────────┘
```

### 5.2 Voice Capture

1. Tap microphone or "Hey Siri, log care update"
2. Watch displays recording indicator
3. Speak handoff (30-60 seconds)
4. Watch confirms: "Saved as draft"
5. Draft syncs to iPhone for review

### 5.3 Complications

| Complication Type | Content                | Tap Action          |
| ----------------- | ---------------------- | ------------------- |
| Circular          | Time until next task   | Open app            |
| Corner            | Patient initials       | Open emergency card |
| Rectangular       | Next task title + time | Open task detail    |
| Inline            | "Next: [task]"         | Open app            |

### 5.4 Emergency Card Access

1. Triple-tap side button OR complication tap
2. Immediate display of emergency info
3. Large, readable text
4. One-tap call to emergency contact
5. Works offline with cached data

---

## 6. Functional Requirements

### 6.1 Watch App Screens

| Screen         | Content                                   | Actions           |
| -------------- | ----------------------------------------- | ----------------- |
| Home           | Patient overview, next task, last handoff | Navigate, capture |
| Handoff List   | Recent 5 handoffs, summary only           | View details      |
| Handoff Detail | Title, summary, time, author              | None              |
| Task List      | Open tasks, due dates                     | Mark complete     |
| Task Detail    | Title, description, due date              | Mark complete     |
| Emergency Card | Critical patient info                     | Call contacts     |
| Voice Capture  | Recording UI                              | Start/stop/cancel |
| Settings       | Patient selector, sync status             | Select patient    |

### 6.2 Complications

```swift
struct CuraKnotComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.curaknot.complication",
            provider: ComplicationProvider()
        ) { entry in
            ComplicationView(entry: entry)
        }
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
```

### 6.3 Data Sync

- [ ] WatchConnectivity for iPhone ↔ Watch sync
- [ ] Local cache of recent handoffs (last 10)
- [ ] Local cache of open tasks (all)
- [ ] Local cache of emergency card data
- [ ] Background refresh every 30 minutes
- [ ] Manual "Sync Now" gesture

### 6.4 Voice Capture

- [ ] Use Watch's dictation API
- [ ] Store audio locally if transcription unavailable
- [ ] Create WATCH_DRAFT handoff with transcribed text
- [ ] Sync draft to iPhone for review
- [ ] Support Siri integration (shared App Intents)

### 6.5 Notifications

- [ ] Haptic for task due reminders
- [ ] Haptic + visual for new handoffs
- [ ] Haptic for shift start reminders
- [ ] Notification actions: "View" or "Dismiss"
- [ ] Mirror iPhone notifications with Watch-specific rendering

### 6.6 Offline Support

- [ ] All cached data accessible offline
- [ ] Voice captures queued for sync
- [ ] Task completions queued for sync
- [ ] Clear staleness indicator when offline
- [ ] Auto-sync when connectivity restored

---

## 7. Data Model

### 7.1 Watch Cache (Local SwiftData/CoreData)

```swift
// WatchHandoff.swift
@Model
class WatchHandoff {
    var id: String
    var circleId: String
    var patientId: String
    var title: String
    var summary: String?
    var type: String
    var publishedAt: Date?
    var createdBy: String
    var createdByName: String
    var syncedAt: Date
}

// WatchTask.swift
@Model
class WatchTask {
    var id: String
    var circleId: String
    var patientId: String
    var title: String
    var dueAt: Date?
    var priority: String
    var status: String
    var syncedAt: Date
}

// WatchEmergencyCard.swift
@Model
class WatchEmergencyCard {
    var patientId: String
    var patientName: String
    var dateOfBirth: Date?
    var bloodType: String?
    var allergies: [String]
    var conditions: [String]
    var medications: [String]
    var emergencyContacts: [WatchContact]
    var syncedAt: Date
}
```

### 7.2 Draft Handoffs (Watch-originated)

```sql
-- Handled by existing handoffs table with source = 'WATCH'
-- status = 'WATCH_DRAFT' until reviewed on iPhone
```

---

## 8. RLS & Security

- [ ] Watch app authenticated via iPhone session delegation
- [ ] Data sync uses same Supabase auth tokens
- [ ] Emergency card viewable without unlock (configurable)
- [ ] No PHI stored in complication data (just counts/times)
- [ ] Wrist detection required for sensitive data display

---

## 9. Edge Functions

No new Edge Functions required — Watch syncs via iPhone using existing endpoints.

---

## 10. iOS/watchOS Implementation Notes

### 10.1 Project Structure

```
CuraKnot/
├── CuraKnot/                    # iOS app
├── CuraKnotWatch/               # watchOS app
│   ├── CuraKnotWatchApp.swift
│   ├── Views/
│   │   ├── HomeView.swift
│   │   ├── HandoffListView.swift
│   │   ├── TaskListView.swift
│   │   ├── EmergencyCardView.swift
│   │   └── VoiceCaptureView.swift
│   ├── Complications/
│   │   └── ComplicationProvider.swift
│   └── Models/
│       └── WatchDataModels.swift
├── CuraKnotWatchExtension/      # Complication extension
└── Shared/                      # Shared code
    ├── WatchConnectivityManager.swift
    └── SharedAppIntents.swift
```

### 10.2 WatchConnectivity

```swift
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    func sendHandoffsToWatch(_ handoffs: [Handoff]) {
        guard WCSession.default.isReachable else {
            // Queue for later
            return
        }

        let data = try? JSONEncoder().encode(handoffs.map { WatchHandoff(from: $0) })
        WCSession.default.sendMessageData(data!, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        // Handle voice capture draft from Watch
        if let draft = try? JSONDecoder().decode(WatchDraft.self, from: messageData) {
            handleWatchDraft(draft)
        }
    }
}
```

### 10.3 Complications with WidgetKit

```swift
struct ComplicationProvider: TimelineProvider {
    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let entry = ComplicationEntry(
            date: Date(),
            nextTask: WatchDataStore.shared.nextTask,
            lastHandoffTime: WatchDataStore.shared.lastHandoffTime
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // Update every 15 minutes
        let entries = generateEntries()
        let timeline = Timeline(entries: entries, policy: .after(Date().addingTimeInterval(15 * 60)))
        completion(timeline)
    }
}
```

### 10.4 Voice Capture

```swift
struct VoiceCaptureView: View {
    @State private var isRecording = false
    @State private var transcribedText = ""

    var body: some View {
        VStack {
            if isRecording {
                // Recording animation
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor)
                Text("Listening...")
            } else {
                Button(action: startRecording) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 60))
                }
            }
        }
    }

    func startRecording() {
        // Use SFSpeechRecognizer or dictation
    }
}
```

---

## 11. Metrics

| Metric                    | Target                  | Measurement                         |
| ------------------------- | ----------------------- | ----------------------------------- |
| Watch app installs        | 50% of iOS users        | Watch app paired / iOS active users |
| Daily active Watch users  | 25% of Watch installers | Sessions per day                    |
| Complication usage        | 40% of Watch users      | Users with active complication      |
| Voice captures from Watch | 10% of all captures     | Watch drafts / total drafts         |
| Emergency card views      | Track usage             | Emergency card opens per month      |

---

## 12. Risks & Mitigations

| Risk                          | Impact | Mitigation                              |
| ----------------------------- | ------ | --------------------------------------- |
| Small screen limitations      | Medium | Focus on glanceable info only           |
| Battery drain                 | High   | Efficient sync; minimal background work |
| Sync failures                 | Medium | Clear offline indicators; auto-retry    |
| Voice transcription quality   | Medium | Queue drafts for iPhone review          |
| watchOS version fragmentation | Low    | Support watchOS 9+ (iPhone 8+)          |

---

## 13. Dependencies

- watchOS 9.0+
- WatchConnectivity framework
- WidgetKit for complications
- SFSpeechRecognizer for voice
- Shared App Intents with Siri feature

---

## 14. Testing Requirements

- [ ] Unit tests for data sync logic
- [ ] Unit tests for complication rendering
- [ ] Integration tests for WatchConnectivity
- [ ] UI tests on Watch simulator
- [ ] Manual testing on physical devices
- [ ] Battery impact testing

---

## 15. Rollout Plan

1. **Alpha:** Basic Watch app with view-only handoffs/tasks
2. **Beta:** Voice capture and complications
3. **GA:** Emergency card and full feature set
4. **Post-GA:** Advanced complications, workout integration

---

### Linkage

- Product: CuraKnot
- Stack: watchOS + WatchConnectivity + WidgetKit
- Baseline: `./CuraKnot-spec.md`
- Related: Siri Shortcuts (shared App Intents), Emergency Card
