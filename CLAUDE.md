# CLAUDE.md — CuraKnot Repo Guide (for Claude Code / AI Coding Agents)

<!-- Last updated: 2026-02-05 | Version: 1.0 | Owner: @curaknot-team -->

This file defines the operating constraints, repo conventions, and "definition of done" for automated coding agents working on **CuraKnot**.

**Source of truth:** `CuraKnot-spec.md`
If a detail here conflicts with the spec, the spec wins. If the spec is ambiguous, choose the lowest-risk, most conservative interpretation, and record it in `docs/DECISIONS.md`.

---

## 0) Project Goal

Ship an MVP of **CuraKnot**: iOS (SwiftUI) + Supabase Backend (PostgreSQL + Edge Functions), matching the spec.

**CuraKnot is a handoff operating system for family caregiving:** turn every care interaction into a structured brief, shared timeline, and clear next actions for a care circle.

MVP includes:

- Sign in with Apple (primary) and email/password (secondary) auth via Supabase Auth
- Create Care Circles with invite-based membership and roles (Owner/Admin/Contributor/Viewer)
- Capture Handoffs via voice (and text fallback) → transcription → structured brief
- Maintain a shared Timeline of handoffs with filtering and search
- Create/assign Tasks from handoffs with reminders and due dates
- Provide a Care Binder (Meds, Contacts, Docs, Insurance, Facilities)
- Export Care Summary PDFs for clinician visits
- Offline-first with GRDB local persistence and Supabase sync
- Push notifications for handoffs, task assignments, and reminders

---

## 1) Operating Rules (Non-Negotiables)

### Spec fidelity

- Do **not** invent endpoints, fields, or business logic not defined in `CuraKnot-spec.md` unless:
  - required for internal implementation, **and**
  - optional/backward-compatible, **and**
  - documented in `docs/DECISIONS.md`.

### Safety and privacy

- Handoffs may contain sensitive health information. Treat all data as PHI-adjacent.
- AI calls (ASR, LLM structuring) must go through Supabase Edge Functions (not direct from iOS client).
- Do not hallucinate medication names/doses; if uncertain, place in 'questions' or 'needs verification'.
- Use Row Level Security (RLS) policies to enforce data access at the database level.
- No PHI in logs, crash reports, or analytics events.

### Shipping discipline

- Prioritize end-to-end "happy path" MVP: auth → create circle → add patient → capture handoff → review draft → publish → tasks → binder → export.
- Avoid "future enhancements" until MVP is feature-complete and tests are green.

### Change control

- Prefer small, reviewable diffs.
- If touching API contracts or data model, update:
  - Supabase migrations
  - Tests validating contract behavior

### Migration discipline

- **ALWAYS run `supabase db push` immediately after creating or modifying a migration file.**
- Never leave migrations unapplied — schema drift causes cascading errors when later migrations reference missing tables/columns.
- When creating migrations that reference other tables, verify those tables exist in the remote database first.
- Use `CREATE TABLE IF NOT EXISTS` and `ALTER TABLE ADD COLUMN IF NOT EXISTS` for idempotency.
- Wrap `CREATE POLICY` statements in conditional `DO $$ ... END $$` blocks checking `pg_policies` to avoid duplicate policy errors.

### Progress documentation

- **After completing any feature or bug fix**, log it in `docs/PROGRESS.md` using the standard entry format.
- Write new ideas, improvements, and strategic notes to `SCRATCHPAD.md`.
- Use `SCRATCHPAD.md` for brainstorming and "what if" explorations that don't belong in code or `DECISIONS.md`.

### Progress logging (REQUIRED)

After each feature implementation or bug fix session, create an entry in `docs/PROGRESS.md`:

```markdown
## [YYYY-MM-DD] Feature/Fix Name

**Type:** Feature | Bugfix | Refactor | Test | Docs
**Status:** Complete | In Progress | Blocked

### Summary

One-line description of what was done.

### Changes

- **File:** `path/to/file` — Description of change

### Testing

- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual verification done

### Notes

Any additional context, blockers, or follow-ups.
```

### Decision documentation

- Record all spec-adjacent or architectural decisions in `docs/DECISIONS.md`.
- Use `DECISIONS.md` when:
  - Implementing something not explicitly defined in the spec
  - Choosing between multiple valid approaches
  - Making trade-offs that affect future development
  - Deviating from common patterns for a specific reason

### API integration and documentation

- **ALWAYS use Context7 MCP** (`mcp__context7__query-docs`) when integrating third-party APIs or libraries.
- Never rely on assumptions or outdated knowledge about API parameters, models, or supported values.
- Workflow:
  1. Use `mcp__context7__resolve-library-id` to find the correct library ID
  2. Use `mcp__context7__query-docs` to get current API documentation
  3. Verify parameter names, allowed values, and constraints from docs
  4. Document any non-obvious API requirements in code comments

---

## 2) Architecture Overview

### Tech Stack

| Layer         | Technology                                                |
| ------------- | --------------------------------------------------------- |
| iOS Client    | SwiftUI, Swift 5.9+, iOS 17+                              |
| Auth          | Supabase Auth (Apple Sign In)                             |
| Database      | Supabase PostgreSQL with RLS                              |
| Backend Logic | Supabase Edge Functions (Deno/TypeScript)                 |
| Storage       | Supabase Storage (audio, attachments, exports)            |
| Local DB      | GRDB (offline-first persistence)                          |
| AI Services   | ASR (OpenAI `gpt-4o-mini-transcribe`) + LLM (structuring) |

### Why Supabase-Only (No Separate API Server)

- Single platform for auth, database, functions, storage
- Built-in Row Level Security eliminates most auth middleware
- Edge Functions handle complex logic (transcription, structuring, PDF generation)
- Simpler deployment and operations
- Native Swift SDK for iOS

### Why GRDB (Not Core Data)

- Explicit control over SQL queries for predictable sync logic
- Type-safe Swift record types align with domain models
- Migrations are straightforward SQL matching Supabase pattern
- Better testability with in-memory databases
- No CloudKit needed (Supabase handles sync)

---

## 3) Repository Layout

```
curaknot/
  ios/
    CuraKnot/                  # SwiftUI iOS app
      App/                     # App entry, DependencyContainer, AppState
      Core/
        Database/              # GRDB models and DatabaseManager
        Networking/            # SupabaseClient, AuthManager
        SyncEngine/            # SyncCoordinator, OfflineQueue, ConflictResolver
        Notifications/         # NotificationManager
      Features/
        Auth/                  # Sign in with Apple
        Timeline/              # Handoff list and detail
        HandoffCapture/        # Audio recording, draft review, publish
        Tasks/                 # Task list, editor, reminders
        Binder/                # Medications, contacts, facilities, docs
        Circle/                # Members, roles, settings, exports
        VisitPack/             # Clinician visit preparation
        EmergencyCard/         # Emergency info card
        MedReconciliation/     # Medication reconciliation
        Shifts/                # Shift handoff mode
        HelperPortal/          # Professional helper features
        Delegation/            # Task delegation intelligence
        Billing/               # Claims and financial tracking
        Inbox/                 # Care inbox and triage
        Insights/              # Operational insights
        Benefits/              # Employer benefit codes
      SharedUI/                # Design system, empty states, network status
      Resources/               # Assets, Localizable strings
    CuraKnot.xcodeproj
  supabase/
    functions/                 # Edge Functions (Deno)
      transcribe-handoff/      # ASR integration
      structure-handoff/       # LLM extraction
      publish-handoff/         # Validation and notification
      generate-care-summary/   # PDF export
      validate-invite/         # Invite token validation
      create-invite/           # Invite generation
      generate-emergency-card/ # Emergency card generation
      ocr-med-scan/            # Medication scan OCR
      compute-shift-changes/   # Shift delta computation
      helper-submit/           # Helper portal submissions
      triage-inbox-item/       # Inbox triage AI
      generate-financial-export/ # Billing export
      generate-appointment-pack/ # Visit pack generation
      resolve-share-link/      # Share link resolution
      redeem-benefit-code/     # Employer benefit redemption
    migrations/                # SQL migrations
    config.toml                # Supabase project config
    seed.sql                   # Development seed data
  docs/
    ARCHITECTURE.md            # System architecture
    DECISIONS.md               # Architectural decisions log
    PROGRESS.md                # Development progress log
    PLAN.md                    # Project planning
    TEST_PLAN.md               # Testing strategy
    SUPABASE_SCHEMA.md         # Database schema docs
    API_CONTRACT.md            # API endpoint contracts
  CuraKnot-spec.md             # Product spec (source of truth)
  CuraKnot-Differentiator-FeatureSpecs/  # Detailed feature specs
  .env.example
```

**Note:** iOS uses Swift Package Manager exclusively. Open `ios/CuraKnot.xcodeproj` directly.

---

## 4) Local Development

### Prerequisites

- Xcode 15+ (or latest stable)
- Supabase CLI (`brew install supabase/tap/supabase`)
- Deno (`brew install deno` or `curl -fsSL https://deno.land/install.sh | sh`)
- Apple Developer account for Sign in with Apple

### 4.1 Supabase Local Development

```bash
# Start local Supabase stack
supabase start

# Apply migrations
supabase db push

# View local dashboard
open http://localhost:54323
```

Local endpoints:

- API: `http://localhost:54321`
- Auth: `http://localhost:54321/auth/v1`
- Database: `postgresql://postgres:postgres@localhost:54322/postgres`
- Dashboard: `http://localhost:54323`

### 4.2 iOS App

```bash
cd ios
open CuraKnot.xcodeproj
```

- Select iPhone Simulator, Run
- Debug builds connect to `http://localhost:54321`
- Use dev shortcuts for quick testing where available

### 4.2.1 Dev Login (DEBUG builds only)

Since Apple Sign In requires configuration, DEBUG builds include a dev login option:

1. **Create a test user** in Supabase Dashboard:
   - Go to: https://supabase.com/dashboard/project/<your-project-ref>/auth/users
   - Click "Add user" → "Create new user"
   - Email: `dev@curaknot.test`
   - Password: (your choice)
   - Check "Auto Confirm User"

2. **Use dev login in the app:**
   - On the sign-in screen, tap "Dev Login" (orange text)
   - Enter your test email and password
   - Tap "Sign In with Email"

**Note:** Dev login is only available in DEBUG builds and will not appear in release builds.

### 4.3 Edge Functions

```bash
# Serve functions locally
supabase functions serve

# Test a function
curl -X POST http://localhost:54321/functions/v1/transcribe-handoff \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"handoffId": "..."}'
```

### 4.4 Running Tests

**iOS:**

```bash
cd ios
xcodebuild test \
  -scheme CuraKnot \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath TestResults
```

---

## 5) Environment Configuration

### Supabase Project Settings

Required environment variables for Edge Functions (set in Supabase Dashboard):

| Variable           | Purpose                                                   |
| ------------------ | --------------------------------------------------------- |
| `OPENAI_API_KEY`   | OpenAI API key for transcription (gpt-4o-mini-transcribe) |
| `LLM_API_KEY`      | LLM for structuring (e.g., OpenAI)                        |
| `APNS_KEY_ID`      | Push notifications                                        |
| `APNS_TEAM_ID`     | Push notifications                                        |
| `APNS_PRIVATE_KEY` | Push notifications (base64)                               |

### iOS Configuration

The iOS app reads Supabase credentials from:

- `SupabaseConfig.swift` — Contains `supabaseURL` and `supabaseAnonKey`
- Debug builds: Local Supabase (`localhost:54321`)
- Release builds: Production Supabase URL

Keychain storage:

- Supabase session tokens managed by `supabase-swift` SDK
- GRDB database file in app sandbox

### .env.example Template

The `.env.example` file should contain placeholders for all required environment variables:

```bash
# Supabase (required)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# AI Services (required for handoff processing)
ASR_API_KEY=your-speech-to-text-api-key
LLM_API_KEY=your-openai-or-anthropic-key

# Push Notifications (required for production)
APNS_KEY_ID=your-key-id
APNS_TEAM_ID=your-team-id
APNS_PRIVATE_KEY=base64-encoded-private-key

# Optional
SENTRY_DSN=your-sentry-dsn
```

---

## 6) Database Schema & Conventions

### Tables

| Table                       | Purpose                                 |
| --------------------------- | --------------------------------------- |
| `users`                     | User profiles (extends auth.users)      |
| `circles`                   | Care circles                            |
| `circle_members`            | Circle membership with roles            |
| `circle_invites`            | Pending invitations                     |
| `patients`                  | Care recipients                         |
| `handoffs`                  | Handoff metadata and current state      |
| `handoff_revisions`         | Append-only revision history            |
| `tasks`                     | Actionable items with assignments       |
| `binder_items`              | Medications, contacts, facilities, etc. |
| `attachments`               | Photos, PDFs, audio files               |
| `read_receipts`             | Handoff read tracking                   |
| `audit_events`              | Security audit log                      |
| `inbox_items`               | Quick capture items for triage          |
| `inbox_triage_log`          | Audit log for triage decisions          |
| `financial_items`           | Bills, claims, EOBs, receipts           |
| `financial_item_tasks`      | Links financial items to tasks          |
| `emergency_cards`           | Emergency info cards per patient        |
| `emergency_card_fields`     | Custom fields for emergency cards       |
| `care_shifts`               | Care coverage shifts                    |
| `shift_checklist_templates` | Reusable shift checklists               |
| `med_scan_sessions`         | OCR medication scan sessions            |
| `med_proposals`             | Proposed medication changes from scans  |
| `member_stats`              | Aggregated stats for delegation         |
| `task_tags`                 | Tags for task categorization            |
| `organizations`             | B2B employer/insurer organizations      |
| `organization_admins`       | Admin users for organizations           |
| `benefit_codes`             | Employer benefit redemption codes       |
| `subscriptions`             | User subscription status and plan       |
| `usage_metrics`             | Metered feature usage tracking          |
| `subscription_events`       | Subscription change audit log           |
| `plan_limits`               | Feature limits per plan (config)        |

### Naming Conventions

| Layer             | Convention   | Example      |
| ----------------- | ------------ | ------------ |
| Database columns  | `snake_case` | `created_at` |
| Swift models      | `camelCase`  | `createdAt`  |
| JSON API payloads | `camelCase`  | `createdAt`  |

### Row Level Security (RLS)

All tables have RLS enabled. Policies enforce:

- Users can only access data for circles they belong to
- Role-based permissions (Owner > Admin > Contributor > Viewer)
- Audit events logged for sensitive operations

Example policy:

```sql
CREATE POLICY "Members can read circle handoffs"
  ON handoffs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM circle_members
      WHERE circle_members.circle_id = handoffs.circle_id
        AND circle_members.user_id = auth.uid()
        AND circle_members.status = 'ACTIVE'
    )
  );
```

### Migrations

```bash
# Create new migration
supabase migration new <migration_name>

# Apply migrations
supabase db push

# Reset database (destructive)
supabase db reset
```

---

## 7) iOS Architecture Conventions

### Feature Module Structure

```
Features/
  Timeline/
    TimelineView.swift
    TimelineViewModel.swift
    HandoffDetailView.swift
    HandoffCell.swift
  HandoffCapture/
    NewHandoffView.swift
    AudioRecorder.swift
    AudioRecorderView.swift
    DraftReviewView.swift
    UploadManager.swift
  Tasks/
    TaskListView.swift
    TaskEditorView.swift
    TaskCell.swift
    TaskService.swift
  Binder/
    BinderView.swift
    BinderService.swift
    MedicationListView.swift
    ContactListView.swift
    DocumentImportView.swift
  Circle/
    CircleSettingsView.swift
    MemberListView.swift
    PatientManagementView.swift
    PDFPreviewView.swift
```

### Dependency Injection

`DependencyContainer` provides all services:

```swift
@MainActor
final class DependencyContainer: ObservableObject {
    // Core services
    lazy var databaseManager: DatabaseManager
    lazy var syncCoordinator: SyncCoordinator
    lazy var authManager: AuthManager
    lazy var supabaseClient: SupabaseClient
    lazy var notificationManager: NotificationManager

    // Feature services
    lazy var binderService: BinderService
    lazy var taskService: TaskService
}
```

### Supabase Swift SDK Usage

```swift
// Auth
let session = try await supabase.auth.signInWithIdToken(...)

// Database queries
let handoffs: [Handoff] = try await supabase
    .from("handoffs")
    .select()
    .eq("circle_id", circleId)
    .order("created_at", ascending: false)
    .execute()
    .value

// Edge Function calls
let response = try await supabase.functions.invoke(
    "transcribe-handoff",
    options: .init(body: ["handoffId": id])
)

// Storage uploads
let url = try await supabase.storage
    .from("handoff-audio")
    .upload(path: "\(handoffId).m4a", file: audioData)
```

### GRDB Local Persistence

```swift
// Define record type
struct Handoff: Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var circleId: UUID
    var patientId: UUID
    var title: String
    var summary: String
    var createdAt: Date
    var updatedAt: Date
}

// Query local database
let handoffs = try await databaseManager.read { db in
    try Handoff
        .filter(Column("circle_id") == circleId)
        .order(Column("created_at").desc)
        .fetchAll(db)
}
```

### Offline Behavior

- All entities cached in GRDB for offline access
- Handoff capture works fully offline (audio stored locally)
- Offline drafts queued in `OfflineQueue` for sync when online
- Clear staleness indicators when viewing cached data

### Accessibility

- Support Dynamic Type including accessibility sizes
- VoiceOver labels on all interactive elements
- Minimum touch target: 44×44 pt

---

## 7.1) Adding Files to Xcode Project (CRITICAL)

When creating new Swift files, you MUST add them to the Xcode project (`project.pbxproj`). Files on disk that aren't in the project won't compile.

### Why This Matters

- Xcode doesn't auto-discover files — the project file (`project.pbxproj`) is the source of truth
- Files must be in both the filesystem AND the project file to compile
- The GUI "Add Files..." option may be unavailable in some contexts

### Method: Use Ruby xcodeproj Gem

**Never manually edit `project.pbxproj`** — it's a complex OpenStep format that's easy to corrupt. Use the xcodeproj gem instead.

#### Install (one-time)

```bash
gem install xcodeproj
```

#### Add Files Script

Create and run this Ruby script from `ios/`:

```ruby
#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('CuraKnot.xcodeproj')
app_target = project.targets.find { |t| t.name == 'CuraKnot' }
test_target = project.targets.find { |t| t.name == 'CuraKnotTests' }

# Helper to find/create group hierarchy matching filesystem
def find_or_create_group(project, file_path)
  components = Pathname.new(file_path).each_filename.to_a
  filename = components.pop

  current_group = project.main_group
  components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }
    current_group = child || current_group.new_group(component, component)
  end

  [current_group, filename]
end

# Add a file to the project
file_path = "CuraKnot/Features/NewFeature/MyView.swift"  # EDIT THIS
is_test = file_path.include?("Tests")
target = is_test ? test_target : app_target

group, filename = find_or_create_group(project, file_path)
file_ref = group.new_reference(filename)
file_ref.source_tree = '<group>'
file_ref.last_known_file_type = 'sourcecode.swift'
target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Added: #{file_path}"
```

---

## 8) Edge Functions

### Pinned Dependencies (CRITICAL)

**ALWAYS use pinned versions for Edge Function imports.** Unpinned versions can break without warning.

| Package                 | Pinned Version | Import URL                                     |
| ----------------------- | -------------- | ---------------------------------------------- |
| `@supabase/supabase-js` | **2.49.1**     | `https://esm.sh/@supabase/supabase-js@2.49.1`  |
| `deno std`              | **0.168.0**    | `https://deno.land/std@0.168.0/http/server.ts` |

**Never use unpinned versions like `@supabase/supabase-js@2` or `@latest`.**

### Function Inventory

| Function                    | Trigger   | Purpose                             |
| --------------------------- | --------- | ----------------------------------- |
| `transcribe-handoff`        | HTTP POST | Send audio to ASR, store transcript |
| `structure-handoff`         | HTTP POST | LLM extraction to structured brief  |
| `publish-handoff`           | HTTP POST | Validate, create revision, notify   |
| `generate-care-summary`     | HTTP POST | Aggregate data, generate PDF        |
| `validate-invite`           | HTTP POST | Verify invite token, assign role    |
| `create-invite`             | HTTP POST | Generate invite link                |
| `generate-emergency-card`   | HTTP POST | Create emergency info card          |
| `ocr-med-scan`              | HTTP POST | OCR medication images               |
| `compute-shift-changes`     | HTTP POST | Calculate shift deltas              |
| `helper-submit`             | HTTP POST | Professional helper submissions     |
| `triage-inbox-item`         | HTTP POST | AI inbox triage                     |
| `generate-appointment-pack` | HTTP POST | Clinician visit preparation         |
| `generate-financial-export` | HTTP POST | Billing/claims export               |
| `resolve-share-link`        | HTTP POST | Resolve share links                 |
| `redeem-benefit-code`       | HTTP POST | Employer benefit redemption         |

### Edge Function Structure

```typescript
// supabase/functions/transcribe-handoff/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get user from JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response("Missing Authorization header", { status: 401 });
  }

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (error || !user) {
    return new Response("Unauthorized", { status: 401 });
  }

  // Business logic...

  return new Response(JSON.stringify(result), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    },
  });
});
```

### Deployment

```bash
# Deploy all functions
supabase functions deploy

# Deploy specific function
supabase functions deploy transcribe-handoff

# View function logs
supabase functions logs transcribe-handoff
```

---

## 8.1) Subscription Infrastructure

### Plan Tiers

| Plan   | Price     | Key Limits                          |
| ------ | --------- | ----------------------------------- |
| FREE   | $0        | 1 circle, 3 members, 10 audio/mo    |
| PLUS   | $9.99/mo  | 2 circles, 8 members, unlimited     |
| FAMILY | $19.99/mo | 5 circles, 20 members, all features |

### Feature Gating

Check feature access in iOS:

```swift
// Check if user has access to a feature
let hasAccess = await subscriptionManager.hasFeature("discharge_wizard")

// Check usage limit
let usage = await subscriptionManager.checkUsage(.audioHandoff)
if !usage.allowed {
    showUpgradePrompt(for: .audioHandoff, current: usage.current, limit: usage.limit)
}
```

Check in Edge Functions:

```typescript
// Check feature access
const hasFeature = await supabase.rpc("has_feature_access", {
  p_user_id: user.id,
  p_feature: "discharge_wizard",
});

// Check and increment usage
const usage = await supabase.rpc("check_usage_limit", {
  p_user_id: user.id,
  p_circle_id: circleId,
  p_metric_type: "AUDIO_HANDOFF",
});

if (!usage.allowed) {
  return new Response("Limit reached", { status: 402 });
}

await supabase.rpc("increment_usage", {
  p_user_id: user.id,
  p_circle_id: circleId,
  p_metric_type: "AUDIO_HANDOFF",
});
```

### Hard-Gated Features (require Plus or Family)

- `watch_app` — Apple Watch companion
- `discharge_wizard` — Hospital Discharge Wizard
- `med_reconciliation` — Medication scan/reconciliation
- `shift_mode` — Shift Handoff Mode (Family only)
- `helper_portal` — Facility Helper Portal (Family only)
- `operational_insights` — Insights dashboard (Family only)
- `legal_vault` — Legal Document Vault (Family only)

### Soft-Gated Features (metered)

| Metric Type   | FREE  | PLUS  | FAMILY |
| ------------- | ----- | ----- | ------ |
| AUDIO_HANDOFF | 10/mo | ∞     | ∞      |
| AI_MESSAGE    | 5/mo  | 50/mo | ∞      |
| EXPORT        | 2/mo  | ∞     | ∞      |
| STORAGE_BYTES | 500MB | 10GB  | 50GB   |

---

## 9) Core Data Types

### Handoff Types

| Type              | Description                   |
| ----------------- | ----------------------------- |
| `VISIT`           | In-person visit report        |
| `CALL`            | Phone call summary            |
| `APPOINTMENT`     | Scheduled appointment outcome |
| `FACILITY_UPDATE` | Update from care facility     |
| `OTHER`           | General update                |

### Binder Item Types

| Type        | Description                        |
| ----------- | ---------------------------------- |
| `MED`       | Medication with dose/schedule      |
| `CONTACT`   | Doctor, nurse, social worker, etc. |
| `FACILITY`  | Care facility with contact info    |
| `INSURANCE` | Insurance policy details           |
| `DOC`       | Uploaded document/photo            |
| `NOTE`      | General reference note             |

### Member Roles

| Role          | Description                              |
| ------------- | ---------------------------------------- |
| `OWNER`       | Full control, billing, can delete circle |
| `ADMIN`       | Manage members, settings                 |
| `CONTRIBUTOR` | Create handoffs, tasks, edit binder      |
| `VIEWER`      | Read-only, can complete assigned tasks   |

### Handoff Comments (Optional)

Comments on handoffs are supported but **disabled by default** to keep the product focused on structured briefs rather than chat threads.

- Comments can be enabled per-circle in Circle Settings
- When enabled, members can add inline notes on handoffs
- Comments are minimal by design (not a messaging feature)
- Phase 2 consideration: threading and @mentions

---

## 10) Testing Strategy

### iOS Tests Required

| Test Case                    | File                          |
| ---------------------------- | ----------------------------- |
| Supabase auth flow           | `AuthManagerTests.swift`      |
| Handoff capture and publish  | `HandoffCaptureTests.swift`   |
| Task creation and completion | `TaskServiceTests.swift`      |
| Binder CRUD operations       | `BinderServiceTests.swift`    |
| Offline queue persistence    | `OfflineQueueTests.swift`     |
| Sync conflict resolution     | `ConflictResolverTests.swift` |

### Edge Function Tests

```bash
# Run function tests
deno test supabase/functions/*/test.ts
```

### Golden Tests

Structured brief extraction uses golden fixtures (transcript → expected JSON) to validate LLM extraction consistency.

---

## 11) Security

### Row Level Security

All tables must have RLS enabled with appropriate policies:

```sql
-- Members can only see handoffs from their circles
CREATE POLICY "Members read circle handoffs" ON handoffs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM circle_members
      WHERE circle_members.circle_id = handoffs.circle_id
        AND circle_members.user_id = auth.uid()
        AND circle_members.status = 'ACTIVE'
    )
  );
```

### Edge Function Auth

All Edge Functions must validate the JWT:

```typescript
const {
  data: { user },
  error,
} = await supabase.auth.getUser(token);
if (error || !user) {
  return new Response("Unauthorized", { status: 401 });
}
```

### PHI Handling

- No PHI in logs, crash reports, or analytics
- Transcripts stored with access controls
- Audio retention configurable (default 30 days)
- Audit logging for exports and transcript access

---

## 12) "Definition of Done" Checklist

You are done when:

1. ✅ `supabase start` runs local stack
2. ✅ All migrations applied successfully
3. ✅ iOS app runs in simulator and can:
   - Sign in with Apple
   - Create a care circle and invite members
   - Add a patient
   - Capture a voice handoff → see draft → publish
   - View timeline with filtering
   - Create and complete tasks
   - Add binder items (meds, contacts, facilities)
   - Generate and share care summary PDF
4. ✅ iOS tests pass
5. ✅ Edge Function tests pass
6. ✅ RLS policies verified for all tables
7. ✅ `docs/DECISIONS.md` documents all spec-adjacent choices
8. ✅ Progress logged in `docs/PROGRESS.md`

---

## 13) Engineering Decision Log

All spec-adjacent decisions must be written to `docs/DECISIONS.md`:

```markdown
## YYYY-MM-DD: [Decision Title]

**Decision:** What was decided.

**Rationale:** Why this choice was made.

**Alternatives considered:**

- Option A: Why rejected
- Option B: Why rejected

**Implications:** What this affects going forward.
```

---

## 14) Guardrails Against Scope Creep

Do not implement in MVP:

- EHR/EMR integration
- E-prescribing or pharmacy automation
- Clinical decision support or diagnosis
- Real-time video/telehealth
- Public communities or social features
- HealthKit / wearable sync
- Complex notification scheduling beyond simple reminders
- A/B testing infrastructure

If you believe something beyond MVP is required for correctness, document it in `DECISIONS.md` and keep implementation minimal.

---

## 15) When Stuck

| Situation                          | Action                                                                    |
| ---------------------------------- | ------------------------------------------------------------------------- |
| Spec is ambiguous                  | Choose conservative interpretation → Document in `DECISIONS.md` → Proceed |
| Blocked by external dependency     | Stub with `// TODO: [reason]` → Continue with other work                  |
| Test fails unexpectedly            | **Do NOT delete or skip.** Investigate root cause → Fix code or fix test  |
| Unsure if feature is in scope      | Re-read Section 14 → If still unsure, ask human                           |
| Implementation conflicts with spec | Spec wins → Document conflict in `DECISIONS.md`                           |
| Security/privacy concern           | **Stop.** Document concern → Ask human before proceeding                  |
| Medication data involved           | Require explicit confirmation → Never hallucinate med names/doses         |

---

## Appendix: Quick Reference

### Common Commands

```bash
# Start local Supabase
supabase start

# Apply migrations
supabase db push

# Deploy Edge Functions
supabase functions deploy

# View logs
supabase functions logs <function-name>

# Open local dashboard
open http://localhost:54323

# Run iOS tests
cd ios && xcodebuild test -scheme CuraKnot -destination 'platform=iOS Simulator,name=iPhone 17'

# Generate types from schema
supabase gen types typescript --local > types/supabase.ts
```

### Key File Locations

| Purpose              | Path                                         |
| -------------------- | -------------------------------------------- |
| **Product spec**     | `CuraKnot-spec.md`                           |
| **Progress log**     | `docs/PROGRESS.md`                           |
| **Decision log**     | `docs/DECISIONS.md`                          |
| **Architecture**     | `docs/ARCHITECTURE.md`                       |
| iOS app entry        | `ios/CuraKnot/App/CuraKnotApp.swift`         |
| Dependency container | `ios/CuraKnot/App/DependencyContainer.swift` |
| App state            | `ios/CuraKnot/App/AppState.swift`            |
| Database models      | `ios/CuraKnot/Core/Database/Models/`         |
| Sync engine          | `ios/CuraKnot/Core/SyncEngine/`              |
| Supabase config      | `supabase/config.toml`                       |
| Migrations           | `supabase/migrations/`                       |
| Edge Functions       | `supabase/functions/`                        |
| Feature specs        | `CuraKnot-Differentiator-FeatureSpecs/`      |

---
