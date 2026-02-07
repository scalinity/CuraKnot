# CuraKnot — Test Plan

> Unit tests, integration tests, UI tests, and golden fixtures for the MVP.

---

## Testing Philosophy

1. **Test the contract, not the implementation** — Focus on behavior
2. **RLS is critical** — Every policy must have explicit tests
3. **Offline-first** — Test sync edge cases thoroughly
4. **No PHI leaks** — Verify logging and analytics are clean
5. **Golden tests for extraction** — Deterministic validation of LLM outputs

---

## Test Layers

### Layer 1: Unit Tests

Fast, isolated tests for pure logic. No network, no database.

**iOS Targets:**

- `CuraKnotTests/` — Xcode unit test target

**Coverage Areas:**

- GRDB model encoding/decoding
- JSON schema validation
- Date/time conversions and formatting
- Permission checks (role-based logic)
- Structured brief parsing
- Confidence threshold logic
- Offline queue operations
- Sync cursor management

### Layer 2: Integration Tests

Test component interactions with real (local) database.

**Backend:**

- Supabase CLI local instance
- RLS policy verification
- Edge Function contracts
- Storage signed URL generation

**iOS:**

- GRDB migrations
- SyncEngine with mock server
- Supabase client with local instance

### Layer 3: UI Tests

End-to-end user flows in iOS simulator.

**Target:** `CuraKnotUITests/`

**Coverage:**

- Onboarding flow
- Handoff capture and publish
- Task creation and completion
- Binder editing
- Export generation

### Layer 4: Golden Tests

Deterministic tests for extraction pipeline.

**Fixtures:**

- Transcript → StructuredBrief pairs
- Edge cases (low confidence, ambiguous meds)
- Multi-language samples (Phase 2)

---

## Backend Tests

### RLS Policy Tests

Each policy must be tested for all four roles.

```
test_rls/
  circles/
    test_owner_can_read_own_circles.sql
    test_member_can_read_joined_circles.sql
    test_non_member_cannot_read.sql
    test_owner_can_update.sql
    test_admin_can_update.sql
    test_contributor_cannot_update.sql
    test_viewer_cannot_update.sql

  handoffs/
    test_member_can_read_published.sql
    test_viewer_cannot_read_raw_transcript.sql
    test_creator_can_edit_within_15_min.sql
    test_owner_can_edit_anytime.sql

  tasks/
    test_assignee_can_complete.sql
    test_viewer_can_complete_if_assigned.sql
    test_viewer_cannot_create.sql

  # ... similar for all tables
```

**Test Pattern:**

```sql
-- Setup: Create users with different roles
-- Act: Attempt operation as each role
-- Assert: Verify success/failure matches expected
```

### Edge Function Tests

```
test_functions/
  validate-invite/
    test_valid_token_joins_circle.ts
    test_expired_token_returns_error.ts
    test_revoked_token_returns_error.ts
    test_used_token_returns_error.ts
    test_assigns_correct_role.ts

  transcribe-handoff/
    test_accepts_valid_audio.ts
    test_rejects_oversized_file.ts
    test_rejects_invalid_mime.ts
    test_returns_job_id.ts
    test_rate_limits_per_circle.ts

  structure-handoff/
    test_returns_valid_schema.ts
    test_includes_confidence_scores.ts
    test_handles_empty_transcript.ts
    test_truncates_long_fields.ts

  publish-handoff/
    test_requires_confirmations.ts
    test_creates_revision.ts
    test_queues_notifications.ts
    test_rejects_invalid_schema.ts

  generate-care-summary/
    test_generates_valid_pdf.ts
    test_includes_all_sections.ts
    test_handles_empty_range.ts
    test_respects_permissions.ts
```

---

## iOS Unit Tests

### Database Tests

```swift
// CuraKnotTests/Database/

class CircleModelTests: XCTestCase {
    func testEncodeDecode() { }
    func testRelationships() { }
}

class HandoffModelTests: XCTestCase {
    func testStructuredBriefParsing() { }
    func testConfidenceThresholds() { }
    func testKeywordExtraction() { }
}

class GRDBMigrationTests: XCTestCase {
    func testMigrationsApplyCleanly() { }
    func testMigrationOrder() { }
}
```

### Sync Engine Tests

```swift
// CuraKnotTests/SyncEngine/

class SyncCursorTests: XCTestCase {
    func testCursorPersistence() { }
    func testCursorPerEntity() { }
}

class OfflineQueueTests: XCTestCase {
    func testEnqueueOperation() { }
    func testDequeueInOrder() { }
    func testPersistenceAcrossRestart() { }
    func testRetryWithBackoff() { }
}

class ConflictResolverTests: XCTestCase {
    func testServerWinsForAuthoritative() { }
    func testClientDraftPreserved() { }
    func testMergeStrategy() { }
}
```

### Permission Tests

```swift
// CuraKnotTests/Permissions/

class RolePermissionTests: XCTestCase {
    func testOwnerPermissions() { }
    func testAdminPermissions() { }
    func testContributorPermissions() { }
    func testViewerPermissions() { }
}

class HandoffEditWindowTests: XCTestCase {
    func testCreatorCanEditWithin15Min() { }
    func testCreatorCannotEditAfter15Min() { }
    func testOwnerCanEditAnytime() { }
}
```

### Validation Tests

```swift
// CuraKnotTests/Validation/

class StructuredBriefValidationTests: XCTestCase {
    func testRequiredFields() { }
    func testTitleMaxLength() { }
    func testSummaryMaxLength() { }
    func testValidHandoffTypes() { }
    func testMedChangeSchema() { }
}

class TaskValidationTests: XCTestCase {
    func testDueDateInFuture() { }
    func testPriorityValues() { }
    func testStatusTransitions() { }
}
```

---

## iOS UI Tests

### Onboarding Flow

```swift
// CuraKnotUITests/Onboarding/

class OnboardingUITests: XCTestCase {
    func testSignInWithAppleFlow() { }
    func testCreateFirstCircle() { }
    func testAddFirstPatient() { }
    func testGenerateInviteLink() { }
    func testJoinViaInviteLink() { }
}
```

### Handoff Flow

```swift
// CuraKnotUITests/Handoff/

class HandoffCaptureUITests: XCTestCase {
    func testRecordAudio() { }
    func testTextFallback() { }
    func testDraftReviewEditing() { }
    func testConfirmMedChanges() { }
    func testPublish() { }
}

class TimelineUITests: XCTestCase {
    func testHandoffListLoads() { }
    func testFilterByPatient() { }
    func testMarkAsRead() { }
    func testOpenDetail() { }
}
```

### Task Flow

```swift
// CuraKnotUITests/Tasks/

class TaskUITests: XCTestCase {
    func testCreateTaskFromHandoff() { }
    func testCreateStandaloneTask() { }
    func testAssignToMember() { }
    func testCompleteTask() { }
    func testFilterViews() { }
}
```

### Binder Flow

```swift
// CuraKnotUITests/Binder/

class BinderUITests: XCTestCase {
    func testAddMedication() { }
    func testEditContact() { }
    func testImportDocument() { }
    func testViewRevisionHistory() { }
}
```

### Export Flow

```swift
// CuraKnotUITests/Export/

class ExportUITests: XCTestCase {
    func testSelectDateRange() { }
    func testPreviewPDF() { }
    func testShareSheet() { }
}
```

---

## Golden Fixtures

### Transcript to Structured Brief

Location: `supabase/tests/fixtures/extraction/`

```
fixtures/
  extraction/
    01_simple_visit.json
    02_med_change_single.json
    03_med_change_multiple.json
    04_low_confidence_fields.json
    05_ambiguous_medication.json
    06_no_actionable_items.json
    07_urgent_safety_flag.json
    08_long_transcript.json
    09_minimal_transcript.json
    10_non_english_terms.json
```

**Fixture Format:**

```json
{
  "id": "01_simple_visit",
  "description": "Simple doctor visit with clear summary",
  "input": {
    "transcript": "Just got back from seeing Dr. Smith. Mom is doing well...",
    "handoff_type": "VISIT",
    "patient_context": {
      "display_name": "Mom",
      "known_medications": ["Metformin", "Lisinopril"]
    }
  },
  "expected_output": {
    "title": "Visit with Dr. Smith",
    "summary": "Mom is doing well. No changes to medications...",
    "status": {
      "mood_energy": "Good spirits"
    },
    "changes": {
      "med_changes": []
    },
    "next_steps": []
  },
  "expected_confidence": {
    "overall": { "min": 0.8 },
    "summary": { "min": 0.85 }
  }
}
```

---

## End-to-End Test Script

Manual/automated flow for full integration testing:

```markdown
## E2E Test: Two Users, One Circle

### Setup

1. Create User A (Sign in with Apple)
2. User A creates circle "Test Circle"
3. User A adds patient "Test Patient"

### Invite Flow

4. User A generates invite link
5. Create User B (Sign in with Apple)
6. User B joins via invite link
7. Verify: Both users see "Test Patient"

### Handoff Flow

8. User A creates text handoff
9. User A publishes handoff
10. Verify: User B sees handoff as unread
11. User B opens handoff
12. Verify: Handoff marked as read

### Task Flow

13. User A creates task from handoff
14. User A assigns task to User B
15. Verify: User B receives notification
16. User B completes task
17. Verify: Task shows as done for both users

### Export Flow

18. User A generates care summary
19. Verify: PDF contains handoff and task
20. User A shares via share sheet
```

---

## Test Data Management

### Seed Data

Location: `supabase/seed.sql`

```sql
-- Test users
INSERT INTO users (id, email, display_name) VALUES
  ('user-a-uuid', 'testa@example.com', 'Test User A'),
  ('user-b-uuid', 'testb@example.com', 'Test User B');

-- Test circle
INSERT INTO circles (id, name, owner_user_id) VALUES
  ('circle-uuid', 'Test Circle', 'user-a-uuid');

-- Memberships
INSERT INTO circle_members (circle_id, user_id, role, status) VALUES
  ('circle-uuid', 'user-a-uuid', 'OWNER', 'ACTIVE'),
  ('circle-uuid', 'user-b-uuid', 'CONTRIBUTOR', 'ACTIVE');

-- Test patient
INSERT INTO patients (id, circle_id, display_name, initials) VALUES
  ('patient-uuid', 'circle-uuid', 'Test Patient', 'TP');
```

### Test Database Reset

```bash
# Reset local Supabase
supabase db reset

# Apply migrations
supabase db push

# Apply seed
psql -f supabase/seed.sql
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Test

on: [push, pull_request]

jobs:
  backend-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - run: supabase start
      - run: supabase db reset
      - run: npm test --prefix supabase

  ios-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild test -project ios/CuraKnot.xcodeproj -scheme CuraKnot -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Coverage Requirements

| Area             | Minimum Coverage |
| ---------------- | ---------------- |
| GRDB Models      | 90%              |
| Sync Engine      | 85%              |
| Permission Logic | 100%             |
| Edge Functions   | 80%              |
| RLS Policies     | 100%             |
| UI Flows         | Happy paths      |
