# CuraKnot — Implementation Plan

> Phase-by-phase execution plan with explicit mapping from spec sections to implementation slices.

---

## Overview

CuraKnot is a **handoff operating system** for family caregiving. This plan implements the MVP in 7 vertical slices, each delivering a testable, working feature set.

**Core Loop:** Record voice note → Transcription → Structured brief → Timeline + Tasks + Notifications

---

## Phase 0: Documentation and Structure Lock

**Goal:** Lock architecture and structure before any implementation.

### Deliverables

| File                      | Purpose                       | Spec Sections |
| ------------------------- | ----------------------------- | ------------- |
| `docs/PLAN.md`            | This file                     | —             |
| `docs/ARCHITECTURE.md`    | Module boundaries, data flows | §14           |
| `docs/SUPABASE_SCHEMA.md` | Tables, RLS, storage          | §11, §12      |
| `docs/API_CONTRACT.md`    | Edge Functions, endpoints     | §12.3, §36    |
| `docs/TEST_PLAN.md`       | Test strategy and fixtures    | §24           |
| `docs/DECISIONS.md`       | Architectural decisions       | —             |

### Supabase Migrations

| Migration           | Tables                                                   | Spec Sections |
| ------------------- | -------------------------------------------------------- | ------------- |
| `0001_initial.sql`  | users, circles, circle_members, circle_invites, patients | §11.2         |
| `0002_handoffs.sql` | handoffs, handoff_revisions, read_receipts               | §11.2, §8     |
| `0003_tasks.sql`    | tasks                                                    | §11.2         |
| `0004_binder.sql`   | binder_items, attachments                                | §11.2         |
| `0005_audit.sql`    | audit_events, notification_outbox                        | §11.2         |
| `0006_rls.sql`      | All RLS policies                                         | §6.2          |

### iOS Project Skeleton

Module structure aligned to spec §14.2:

- AppShell (auth, routing, tab container)
- TimelineFeature
- HandoffCaptureFeature
- TasksFeature
- BinderFeature
- CircleFeature
- SyncEngine
- SharedUI

---

## Slice A: Foundations

**Spec Sections:** §7.1 (Onboarding), §6 (Permissions), §11.2 (users, circles, members, patients)

**Checkpoint:** Two real users join the same circle and see the same patient list.

### Backend Tasks

1. Configure Supabase Auth for Sign in with Apple (§12.1)
2. Apply migrations 0001 (core tables) and 0006 (RLS)
3. Create `validate-invite` Edge Function
4. Seed development data

### iOS Tasks

1. Sign in with Apple flow (§7.1, FR-ONB-001)
2. Tab shell with 4 tabs (§4)
3. Circle creation wizard (FR-ONB-002)
4. Patient creation form (FR-ONB-003)
5. Invite link handling (FR-ONB-004, FR-ONB-005)
6. Circle switcher (FR-ONB-006)

### Acceptance Criteria

- [ ] User can sign in with Apple
- [ ] User can create a circle with name and icon
- [ ] User can add a patient to the circle
- [ ] User can generate an invite link
- [ ] Second user can join via invite link
- [ ] Both users see the same patient list

---

## Slice B: Text Handoffs + Timeline

**Spec Sections:** §7.2 (Handoff Capture), §7.3 (Timeline), §8 (Structured Brief Schema)

**Checkpoint:** User A publishes a handoff → User B sees it unread → marks read.

### Backend Tasks

1. Apply migration 0002 (handoffs, revisions, read_receipts)
2. Create `publish_handoff` RPC
3. Add full-text search index

### iOS Tasks

1. New Handoff button (FR-HND-001)
2. Text entry mode (FR-HND-003)
3. Draft review UI (FR-HND-004, UX-DRF-\*)
4. Publish flow (FR-HND-008)
5. Timeline list with filters (FR-TIM-001 through FR-TIM-004)
6. Handoff detail view (FR-TIM-004, UX-DET-\*)
7. Read/unread state (FR-TIM-005)

### Acceptance Criteria

- [ ] User can create a text handoff
- [ ] Draft shows editable structured fields
- [ ] Published handoff appears in timeline
- [ ] Other circle members see handoff as unread
- [ ] Marking read updates state across devices

---

## Slice C: Audio → Structured Brief → Publish

**Spec Sections:** §9 (Extraction Pipeline), §15 (Audio Capture)

**Checkpoint:** Record 30s audio → structured draft → edit → confirm → publish.

### Backend Tasks

1. Create `handoff-audio` storage bucket
2. Create `transcribe-handoff` Edge Function (§9.1 Stage C)
3. Create `structure-handoff` Edge Function (§9.1 Stage D)
4. Create `publish-handoff` Edge Function (§9.1 Stage E, F)

### iOS Tasks

1. AVFoundation recording (AUD-001 through AUD-005)
2. Waveform visualization (UX-HND-001, UX-HND-002)
3. Resumable upload (§9.1 Stage B)
4. Job polling UI
5. Low-confidence highlighting (PIPE-CFX-001)
6. Med change confirmations (PIPE-DET-004, UX-DRF-003)

### Acceptance Criteria

- [ ] Audio records in AAC format
- [ ] Upload shows progress
- [ ] Transcription job completes
- [ ] Structured draft shows confidence indicators
- [ ] Med changes require explicit confirmation
- [ ] Published handoff includes audio reference

---

## Slice D: Tasks + Reminders

**Spec Sections:** §7.4 (Tasks), §16 (Notifications)

**Checkpoint:** Assign task → assignee notified → completes → syncs everywhere.

### Backend Tasks

1. Apply migration 0003 (tasks)
2. Apply migration 0005 (notification_outbox)
3. Create `complete_task` RPC

### iOS Tasks

1. Task creation from handoff (FR-TSK-001)
2. Task list views (FR-TSK-004, UX-TSK-001)
3. Assignment UI (FR-TSK-002)
4. Push notification registration
5. Local notifications for reminders (FR-TSK-003)
6. Quiet hours (NOT-002)
7. Completion flow (FR-TSK-006)

### Acceptance Criteria

- [ ] Tasks can be created from handoff next_steps
- [ ] Standalone tasks can be created
- [ ] Task assignment sends push notification
- [ ] Reminders trigger at scheduled time
- [ ] Completion syncs to all devices

---

## Slice E: Binder + Attachments

**Spec Sections:** §7.5 (Binder)

**Checkpoint:** Upload doc → view on another device → revision history preserved.

### Backend Tasks

1. Apply migration 0004 (binder_items, attachments)
2. Create `attachments` storage bucket
3. Signed URL generation for downloads

### iOS Tasks

1. Binder sections UI (FR-BND-001)
2. Medication editor (FR-BND-002)
3. Contact editor with quick actions (FR-BND-003, UX-BND-003)
4. Facility editor (FR-BND-004)
5. Document import (FR-BND-005)
6. Revision history (FR-BND-006)

### Acceptance Criteria

- [ ] Medications can be added with full details
- [ ] Contacts have call/text/email actions
- [ ] Documents can be imported from Photos or Files
- [ ] Edits create revision entries
- [ ] Content syncs across devices

---

## Slice F: Care Summary Export

**Spec Sections:** §7.6 (Export), §18 (PDF Specification)

**Checkpoint:** PDF contains required sections and shares successfully.

### Backend Tasks

1. Create `exports` storage bucket
2. Create `generate-care-summary` Edge Function
3. PDF generation with all required sections (PDF-001 through PDF-007)

### iOS Tasks

1. Export configuration UI (FR-EXP-001)
2. Date range and patient selection
3. PDF preview (FR-EXP-003)
4. Share sheet integration

### Acceptance Criteria

- [ ] Export UI allows date range selection
- [ ] PDF includes handoff summaries
- [ ] PDF includes medication changes
- [ ] PDF includes open questions
- [ ] PDF includes outstanding tasks
- [ ] Share sheet works correctly

---

## Slice G: Offline + Sync Hardening

**Spec Sections:** §13 (Sync, Offline, Conflict Resolution)

**Checkpoint:** Offline → create draft → reconnect → publish with no data loss.

### Backend Tasks

1. Incremental sync endpoints with cursor support
2. Cron jobs for cleanup (CRON-001 through CRON-005)

### iOS Tasks

1. Incremental sync with cursors (SYNC-001, SYNC-002)
2. Offline draft queue (SYNC-004)
3. Conflict resolution UI (SYNC-003)
4. Background sync
5. Staleness indicators

### Acceptance Criteria

- [ ] Drafts persist through app restart
- [ ] Offline changes queue for upload
- [ ] Conflicts show resolution UI
- [ ] Sync resumes on connectivity

---

## Definition of Done (Every PR)

- [ ] App builds and runs
- [ ] Supabase migrations apply cleanly
- [ ] RLS verified
- [ ] No PHI in logs or analytics
- [ ] Drafts never lost
- [ ] `docs/DECISIONS.md` updated for any new decisions
