# CuraKnot — Architecture Document

> iOS module boundaries, data flows, and Supabase responsibilities.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS App                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     AppShell                              │   │
│  │  (Auth State, Routing, Tab Container, Circle Switcher)   │   │
│  └──────────────────────────────────────────────────────────┘   │
│       │           │           │           │           │          │
│  ┌────▼───┐  ┌────▼───┐  ┌────▼────┐  ┌───▼───┐  ┌────▼────┐   │
│  │Timeline│  │Handoff │  │ Tasks   │  │Binder │  │ Circle  │   │
│  │Feature │  │Capture │  │ Feature │  │Feature│  │ Feature │   │
│  └────┬───┘  └────┬───┘  └────┬────┘  └───┬───┘  └────┬────┘   │
│       │           │           │           │           │          │
│  ┌────▼───────────▼───────────▼───────────▼───────────▼────┐   │
│  │                      SyncEngine                          │   │
│  │  (GRDB, Offline Queue, Conflict Resolution, Cursors)    │   │
│  └──────────────────────────┬───────────────────────────────┘   │
│                             │                                    │
│  ┌──────────────────────────▼───────────────────────────────┐   │
│  │                     SharedUI                              │   │
│  │  (Design System, Skeletons, Toasts, Common Components)   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Supabase Backend                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ Supabase     │  │   Postgres   │  │   Storage Buckets    │   │
│  │ Auth         │  │   + RLS      │  │   (attachments,      │   │
│  │              │  │              │  │    handoff-audio,    │   │
│  │              │  │              │  │    exports)          │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│                             │                                    │
│  ┌──────────────────────────▼───────────────────────────────┐   │
│  │                    Edge Functions                         │   │
│  │  validate-invite, transcribe-handoff, structure-handoff,│   │
│  │  publish-handoff, generate-care-summary                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                             │                                    │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              External Services (ASR, LLM)                │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## iOS Module Boundaries

### AppShell

**Responsibilities:**

- App entry point and lifecycle
- Authentication state management
- Root navigation (tab bar)
- Circle context and switching
- Deep link handling (invite links)
- Push notification registration

**Dependencies:** All feature modules, SyncEngine

**Key Types:**

- `CuraKnotApp` — SwiftUI App entry point
- `AppState` — ObservableObject for global state
- `DependencyContainer` — Service locator / DI container
- `AuthManager` — Sign in with Apple, session persistence
- `DeepLinkHandler` — URL scheme handling for invites

### TimelineFeature

**Responsibilities:**

- Handoff list display with filters
- Handoff detail view
- Read/unread state management
- Full-text search (local + server)

**Dependencies:** SyncEngine, SharedUI

**Key Types:**

- `TimelineView` — Main list view
- `TimelineViewModel` — Data loading, filtering, search
- `HandoffDetailView` — Single handoff display
- `HandoffCell` — List cell component

### HandoffCaptureFeature

**Responsibilities:**

- Audio recording with AVFoundation
- Text entry fallback
- Upload management
- Transcription/structuring job polling
- Draft review and editing
- Publish with confirmations

**Dependencies:** SyncEngine, SharedUI

**Key Types:**

- `NewHandoffView` — Entry point, mode selection
- `AudioRecorderView` — Recording UI
- `AudioRecorder` — AVFoundation wrapper
- `TextHandoffView` — Text entry mode
- `DraftReviewView` — Structured brief editing
- `UploadManager` — Resumable uploads
- `JobPoller` — Transcription job status

### TasksFeature

**Responsibilities:**

- Task list views (Mine, All, Overdue, Done)
- Task creation and editing
- Assignment to circle members
- Reminder scheduling (push + local)
- Completion with notes

**Dependencies:** SyncEngine, SharedUI

**Key Types:**

- `TaskListView` — Segmented task views
- `TaskEditorView` — Create/edit form
- `TaskCell` — List cell with swipe actions
- `ReminderScheduler` — Local notification scheduling

### BinderFeature

**Responsibilities:**

- Binder section navigation
- Medication list and editor
- Contact list with quick actions
- Facility list and editor
- Document import and viewing
- Revision history display

**Dependencies:** SyncEngine, SharedUI

**Key Types:**

- `BinderView` — Section list
- `MedicationListView` / `MedicationEditorView`
- `ContactListView` / `ContactEditorView`
- `FacilityListView` / `FacilityEditorView`
- `DocumentListView` / `DocumentImportView`
- `RevisionHistoryView`

### CircleFeature

**Responsibilities:**

- Circle settings and info
- Member list and role management
- Invite generation and management
- Patient management
- Export generation and sharing
- Privacy settings

**Dependencies:** SyncEngine, SharedUI

**Key Types:**

- `CircleSettingsView` — Main settings screen
- `MemberListView` — Members with roles
- `InviteManagementView` — Generate, revoke invites
- `PatientManagementView` — Add/edit/archive patients
- `ExportView` — Care summary generation
- `PDFPreviewView` — PDFKit-based preview

### SyncEngine

**Responsibilities:**

- Local database (GRDB) management
- Incremental sync with server
- Offline draft queue
- Conflict detection and resolution
- Cursor-based pagination
- Attachment upload/download queue

**Dependencies:** Networking layer

**Key Types:**

- `SyncCoordinator` — Orchestrates sync operations
- `DatabaseManager` — GRDB connection, migrations
- `OfflineQueue` — Pending operations queue
- `ConflictResolver` — Merge strategies, UI triggers
- `SyncCursor` — Per-entity sync state
- `AttachmentCache` — Local file management

### SharedUI

**Responsibilities:**

- Design tokens (colors, typography, spacing)
- Common components (buttons, inputs, cards)
- Loading states (skeletons, spinners)
- Toasts and alerts
- Empty states
- Accessibility helpers

**Key Types:**

- `DesignTokens` — Color, font, spacing constants
- `PrimaryButton`, `SecondaryButton`
- `FormField`, `TextArea`
- `SkeletonView`, `LoadingOverlay`
- `ToastView`, `ToastManager`
- `EmptyStateView`

---

## Data Flow Diagrams

### Authentication Flow

```
┌─────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────┐
│  User   │───▶│ Sign in with │───▶│ Supabase Auth   │───▶│ Session  │
│         │    │ Apple Button │    │ Token Exchange  │    │ Stored   │
└─────────┘    └──────────────┘    └─────────────────┘    └──────────┘
                                            │
                                            ▼
                                   ┌─────────────────┐
                                   │ Fetch/Create    │
                                   │ User Profile    │
                                   └─────────────────┘
                                            │
                                            ▼
                                   ┌─────────────────┐
                                   │ Fetch User's    │
                                   │ Circles         │
                                   └─────────────────┘
```

### Handoff Creation Flow (Audio)

```
┌──────────┐    ┌───────────┐    ┌──────────────┐    ┌──────────────┐
│  Record  │───▶│  Upload   │───▶│  Transcribe  │───▶│  Structure   │
│  Audio   │    │  Audio    │    │  (ASR)       │    │  (LLM)       │
└──────────┘    └───────────┘    └──────────────┘    └──────────────┘
     │               │                  │                   │
     │               │                  │                   ▼
     │               │                  │          ┌──────────────┐
     │               │                  │          │ Draft Review │
     │               │                  │          │ (Edit/Confirm)│
     │               │                  │          └──────────────┘
     │               │                  │                   │
     │               │                  │                   ▼
     │               │                  │          ┌──────────────┐
     │               │                  │          │   Publish    │
     │               │                  │          └──────────────┘
     │               │                  │                   │
     ▼               ▼                  ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Local GRDB                               │
│  (Draft state persisted at each step for offline resilience)    │
└─────────────────────────────────────────────────────────────────┘
```

### Sync Flow

```
┌─────────────────┐
│  App Foreground │
│  or Trigger     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│  Check Pending  │───▶│  Upload Queue   │
│  Uploads        │    │  (if any)       │
└────────┬────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│  For each entity│
│  type:          │
│  - circles      │
│  - patients     │
│  - handoffs     │
│  - tasks        │
│  - binder_items │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│  GET /entity    │───▶│  Merge into     │
│  ?updated_at>   │    │  local GRDB     │
│  {cursor}       │    │                 │
└─────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│  Update cursor  │
│  for next sync  │
└─────────────────┘
```

---

## Supabase Responsibilities

### Supabase Auth

- Sign in with Apple token validation
- JWT session tokens with refresh
- User profile storage (display_name, settings)
- Session revocation on logout

### Postgres + RLS

- All application data storage
- Row-level security enforcing circle membership
- Role-based access (OWNER, ADMIN, CONTRIBUTOR, VIEWER)
- Full-text search indexes
- Trigger-based `updated_at` maintenance

### Storage

- **attachments** — User documents, photos (retained until deleted)
- **handoff-audio** — Audio recordings (30-day retention)
- **exports** — Generated PDFs (7-day retention)
- All access via short-lived signed URLs

### Edge Functions

| Function                | Purpose                             | Trigger             |
| ----------------------- | ----------------------------------- | ------------------- |
| `validate-invite`       | Verify invite token, assign role    | POST from iOS       |
| `transcribe-handoff`    | Send audio to ASR, store transcript | POST from iOS       |
| `structure-handoff`     | LLM extraction to structured brief  | After transcription |
| `publish-handoff`       | Validate, create revision, notify   | POST from iOS       |
| `generate-care-summary` | Aggregate data, generate PDF        | POST from iOS       |

---

## Security Boundaries

### Client-Side

- No raw transcript displayed without explicit user action
- Sensitive data cleared from memory after use
- Keychain for session tokens
- No PHI in logs or crash reports

### Server-Side

- RLS enforces all data access rules
- No bypassing RLS from Edge Functions
- Signed URLs expire in 1 hour
- Audit logging for sensitive operations
- No PHI in server logs

### Network

- TLS for all connections
- Certificate pinning (optional, Phase 2)
- Idempotency keys for write operations
