# CuraKnot — Supabase Schema

> Complete database schema with tables, columns, indexes, RLS policies, and storage buckets.

---

## Table: users

User profiles linked to Supabase Auth.

| Column        | Type        | Constraints                   | Description              |
| ------------- | ----------- | ----------------------------- | ------------------------ |
| id            | uuid        | PK, DEFAULT gen_random_uuid() | Matches auth.users.id    |
| email         | text        | UNIQUE, nullable              | Email from auth provider |
| apple_sub     | text        | UNIQUE, nullable              | Apple Sign In subject ID |
| display_name  | text        | NOT NULL                      | User's display name      |
| avatar_url    | text        | nullable                      | Profile image URL        |
| settings_json | jsonb       | DEFAULT '{}'                  | User preferences         |
| created_at    | timestamptz | DEFAULT now()                 |                          |
| updated_at    | timestamptz | DEFAULT now()                 |                          |

**Indexes:**

- `users_pkey` on (id)
- `users_email_key` on (email) WHERE email IS NOT NULL
- `users_apple_sub_key` on (apple_sub) WHERE apple_sub IS NOT NULL

**RLS Policies:**

- SELECT: Users can read their own row
- UPDATE: Users can update their own row
- INSERT: Handled by auth trigger

---

## Table: circles

Care circles - shared spaces for caregiving coordination.

| Column        | Type        | Constraints                   | Description              |
| ------------- | ----------- | ----------------------------- | ------------------------ |
| id            | uuid        | PK, DEFAULT gen_random_uuid() |                          |
| name          | text        | NOT NULL                      | Circle display name      |
| icon          | text        | nullable                      | Emoji or icon identifier |
| owner_user_id | uuid        | FK users(id), NOT NULL        | Circle owner             |
| plan          | text        | DEFAULT 'FREE'                | FREE, PLUS, FAMILY       |
| settings_json | jsonb       | DEFAULT '{}'                  | Circle-level settings    |
| created_at    | timestamptz | DEFAULT now()                 |                          |
| updated_at    | timestamptz | DEFAULT now()                 |                          |
| deleted_at    | timestamptz | nullable                      | Soft delete              |

**Indexes:**

- `circles_pkey` on (id)
- `circles_owner_user_id_idx` on (owner_user_id)

**RLS Policies:**

- SELECT: User is a member of the circle (via circle_members)
- INSERT: Any authenticated user
- UPDATE: OWNER or ADMIN role
- DELETE: OWNER only (soft delete)

---

## Table: circle_members

Membership junction table with roles.

| Column         | Type        | Constraints                   | Description                       |
| -------------- | ----------- | ----------------------------- | --------------------------------- |
| id             | uuid        | PK, DEFAULT gen_random_uuid() |                                   |
| circle_id      | uuid        | FK circles(id), NOT NULL      |                                   |
| user_id        | uuid        | FK users(id), NOT NULL        |                                   |
| role           | text        | NOT NULL                      | OWNER, ADMIN, CONTRIBUTOR, VIEWER |
| status         | text        | DEFAULT 'ACTIVE'              | INVITED, ACTIVE, REMOVED          |
| invited_by     | uuid        | FK users(id), nullable        | Who sent the invite               |
| invited_at     | timestamptz | DEFAULT now()                 |                                   |
| joined_at      | timestamptz | nullable                      | When user accepted                |
| last_active_at | timestamptz | nullable                      | Last activity timestamp           |
| created_at     | timestamptz | DEFAULT now()                 |                                   |
| updated_at     | timestamptz | DEFAULT now()                 |                                   |

**Indexes:**

- `circle_members_pkey` on (id)
- `circle_members_circle_user_unique` on (circle_id, user_id) UNIQUE
- `circle_members_user_id_idx` on (user_id)

**RLS Policies:**

- SELECT: User is a member of the same circle
- INSERT: OWNER or ADMIN of the circle
- UPDATE: OWNER or ADMIN (for role changes)
- DELETE: OWNER or ADMIN (remove member)

---

## Table: circle_invites

Pending invitations with tokens.

| Column     | Type        | Constraints                   | Description            |
| ---------- | ----------- | ----------------------------- | ---------------------- |
| id         | uuid        | PK, DEFAULT gen_random_uuid() |                        |
| circle_id  | uuid        | FK circles(id), NOT NULL      |                        |
| token      | text        | UNIQUE, NOT NULL              | Invite token for URL   |
| role       | text        | DEFAULT 'CONTRIBUTOR'         | Role to assign on join |
| created_by | uuid        | FK users(id), NOT NULL        |                        |
| expires_at | timestamptz | NOT NULL                      | Expiration timestamp   |
| used_at    | timestamptz | nullable                      | When invite was used   |
| used_by    | uuid        | FK users(id), nullable        | Who used the invite    |
| revoked_at | timestamptz | nullable                      | If revoked             |
| created_at | timestamptz | DEFAULT now()                 |                        |

**Indexes:**

- `circle_invites_pkey` on (id)
- `circle_invites_token_key` on (token) UNIQUE
- `circle_invites_circle_id_idx` on (circle_id)

**RLS Policies:**

- SELECT: OWNER or ADMIN of the circle
- INSERT: OWNER or ADMIN of the circle
- UPDATE: OWNER or ADMIN (for revocation)

---

## Table: patients

Care recipients within a circle.

| Column       | Type        | Constraints                   | Description         |
| ------------ | ----------- | ----------------------------- | ------------------- |
| id           | uuid        | PK, DEFAULT gen_random_uuid() |                     |
| circle_id    | uuid        | FK circles(id), NOT NULL      |                     |
| display_name | text        | NOT NULL                      | Patient name        |
| initials     | text        | nullable                      | 2-3 letter initials |
| dob          | date        | nullable                      | Date of birth       |
| pronouns     | text        | nullable                      | Preferred pronouns  |
| notes        | text        | nullable                      | General notes       |
| archived_at  | timestamptz | nullable                      | Soft archive        |
| created_at   | timestamptz | DEFAULT now()                 |                     |
| updated_at   | timestamptz | DEFAULT now()                 |                     |

**Indexes:**

- `patients_pkey` on (id)
- `patients_circle_id_idx` on (circle_id)

**RLS Policies:**

- SELECT: User is a member of the circle
- INSERT: OWNER, ADMIN, or CONTRIBUTOR
- UPDATE: OWNER, ADMIN, or CONTRIBUTOR
- DELETE: OWNER or ADMIN (soft delete via archive)

---

## Table: handoffs

Handoff records (structured briefs).

| Column            | Type        | Constraints                   | Description                                      |
| ----------------- | ----------- | ----------------------------- | ------------------------------------------------ |
| id                | uuid        | PK, DEFAULT gen_random_uuid() |                                                  |
| circle_id         | uuid        | FK circles(id), NOT NULL      |                                                  |
| patient_id        | uuid        | FK patients(id), NOT NULL     |                                                  |
| created_by        | uuid        | FK users(id), NOT NULL        |                                                  |
| type              | text        | NOT NULL                      | VISIT, CALL, APPOINTMENT, FACILITY_UPDATE, OTHER |
| title             | text        | NOT NULL                      | <= 80 chars                                      |
| summary           | text        | nullable                      | <= 600 chars                                     |
| keywords          | text[]      | DEFAULT '{}'                  | Extracted keywords                               |
| status            | text        | DEFAULT 'DRAFT'               | DRAFT, PUBLISHED                                 |
| published_at      | timestamptz | nullable                      |                                                  |
| current_revision  | int         | DEFAULT 1                     |                                                  |
| raw_transcript    | text        | nullable                      | Protected field                                  |
| audio_storage_key | text        | nullable                      | Reference to audio file                          |
| confidence_json   | jsonb       | nullable                      | Per-field confidence                             |
| created_at        | timestamptz | DEFAULT now()                 |                                                  |
| updated_at        | timestamptz | DEFAULT now()                 |                                                  |

**Indexes:**

- `handoffs_pkey` on (id)
- `handoffs_circle_id_idx` on (circle_id)
- `handoffs_patient_id_idx` on (patient_id)
- `handoffs_created_by_idx` on (created_by)
- `handoffs_published_at_idx` on (published_at) WHERE published_at IS NOT NULL
- `handoffs_fts_idx` GIN on to_tsvector('english', title || ' ' || COALESCE(summary, ''))

**RLS Policies:**

- SELECT: User is a member of the circle (raw_transcript filtered for VIEWER)
- INSERT: OWNER, ADMIN, or CONTRIBUTOR
- UPDATE: Creator within 15 min of publish, or OWNER/ADMIN
- DELETE: OWNER or ADMIN (soft delete)

---

## Table: handoff_revisions

Immutable revision history for handoffs.

| Column          | Type        | Constraints                   | Description            |
| --------------- | ----------- | ----------------------------- | ---------------------- |
| id              | uuid        | PK, DEFAULT gen_random_uuid() |                        |
| handoff_id      | uuid        | FK handoffs(id), NOT NULL     |                        |
| revision        | int         | NOT NULL                      | Revision number        |
| structured_json | jsonb       | NOT NULL                      | Full structured brief  |
| edited_by       | uuid        | FK users(id), NOT NULL        |                        |
| edited_at       | timestamptz | DEFAULT now()                 |                        |
| change_note     | text        | nullable                      | Description of changes |

**Indexes:**

- `handoff_revisions_pkey` on (id)
- `handoff_revisions_handoff_revision_unique` on (handoff_id, revision) UNIQUE

**RLS Policies:**

- SELECT: User is a member of the circle
- INSERT: Via publish/revise flow only

---

## Table: read_receipts

Track which users have read which handoffs.

| Column     | Type        | Constraints                   | Description |
| ---------- | ----------- | ----------------------------- | ----------- |
| id         | uuid        | PK, DEFAULT gen_random_uuid() |             |
| circle_id  | uuid        | FK circles(id), NOT NULL      |             |
| handoff_id | uuid        | FK handoffs(id), NOT NULL     |             |
| user_id    | uuid        | FK users(id), NOT NULL        |             |
| read_at    | timestamptz | DEFAULT now()                 |             |

**Indexes:**

- `read_receipts_pkey` on (id)
- `read_receipts_handoff_user_unique` on (handoff_id, user_id) UNIQUE
- `read_receipts_user_id_idx` on (user_id)

**RLS Policies:**

- SELECT: User's own read receipts
- INSERT: User can mark their own
- UPDATE: User can update their own
- DELETE: User can delete their own

---

## Table: tasks

Actionable items with assignments.

| Column          | Type        | Constraints                   | Description          |
| --------------- | ----------- | ----------------------------- | -------------------- |
| id              | uuid        | PK, DEFAULT gen_random_uuid() |                      |
| circle_id       | uuid        | FK circles(id), NOT NULL      |                      |
| patient_id      | uuid        | FK patients(id), nullable     |                      |
| handoff_id      | uuid        | FK handoffs(id), nullable     | Source handoff       |
| created_by      | uuid        | FK users(id), NOT NULL        |                      |
| owner_user_id   | uuid        | FK users(id), NOT NULL        | Assigned to          |
| title           | text        | NOT NULL                      |                      |
| description     | text        | nullable                      |                      |
| due_at          | timestamptz | nullable                      |                      |
| priority        | text        | DEFAULT 'MED'                 | LOW, MED, HIGH       |
| status          | text        | DEFAULT 'OPEN'                | OPEN, DONE, CANCELED |
| completed_at    | timestamptz | nullable                      |                      |
| completed_by    | uuid        | FK users(id), nullable        |                      |
| completion_note | text        | nullable                      |                      |
| reminder_json   | jsonb       | DEFAULT '{}'                  | Reminder settings    |
| created_at      | timestamptz | DEFAULT now()                 |                      |
| updated_at      | timestamptz | DEFAULT now()                 |                      |

**Indexes:**

- `tasks_pkey` on (id)
- `tasks_circle_id_idx` on (circle_id)
- `tasks_owner_user_id_idx` on (owner_user_id)
- `tasks_status_idx` on (status)
- `tasks_due_at_idx` on (due_at) WHERE due_at IS NOT NULL

**RLS Policies:**

- SELECT: User is a member of the circle
- INSERT: OWNER, ADMIN, or CONTRIBUTOR
- UPDATE: Creator, assignee, OWNER, or ADMIN
- DELETE: Creator, OWNER, or ADMIN

---

## Table: binder_items

Reference items (meds, contacts, docs, etc).

| Column       | Type        | Constraints                   | Description                                  |
| ------------ | ----------- | ----------------------------- | -------------------------------------------- |
| id           | uuid        | PK, DEFAULT gen_random_uuid() |                                              |
| circle_id    | uuid        | FK circles(id), NOT NULL      |                                              |
| patient_id   | uuid        | FK patients(id), nullable     |                                              |
| type         | text        | NOT NULL                      | MED, CONTACT, FACILITY, INSURANCE, DOC, NOTE |
| title        | text        | NOT NULL                      |                                              |
| content_json | jsonb       | NOT NULL                      | Type-specific content                        |
| is_active    | boolean     | DEFAULT true                  |                                              |
| created_by   | uuid        | FK users(id), NOT NULL        |                                              |
| updated_by   | uuid        | FK users(id), NOT NULL        |                                              |
| created_at   | timestamptz | DEFAULT now()                 |                                              |
| updated_at   | timestamptz | DEFAULT now()                 |                                              |

**Indexes:**

- `binder_items_pkey` on (id)
- `binder_items_circle_id_idx` on (circle_id)
- `binder_items_type_idx` on (type)
- `binder_items_patient_id_idx` on (patient_id)

**RLS Policies:**

- SELECT: User is a member of the circle
- INSERT: OWNER, ADMIN, or CONTRIBUTOR
- UPDATE: OWNER, ADMIN, or CONTRIBUTOR
- DELETE: OWNER or ADMIN

---

## Table: attachments

File attachments linked to handoffs or binder items.

| Column           | Type        | Constraints                   | Description            |
| ---------------- | ----------- | ----------------------------- | ---------------------- |
| id               | uuid        | PK, DEFAULT gen_random_uuid() |                        |
| circle_id        | uuid        | FK circles(id), NOT NULL      |                        |
| uploader_user_id | uuid        | FK users(id), NOT NULL        |                        |
| handoff_id       | uuid        | FK handoffs(id), nullable     |                        |
| binder_item_id   | uuid        | FK binder_items(id), nullable |                        |
| kind             | text        | NOT NULL                      | PHOTO, PDF, AUDIO      |
| mime_type        | text        | NOT NULL                      |                        |
| byte_size        | int         | NOT NULL                      |                        |
| sha256           | text        | NOT NULL                      | Content hash           |
| storage_key      | text        | NOT NULL                      | Path in storage bucket |
| filename         | text        | nullable                      | Original filename      |
| created_at       | timestamptz | DEFAULT now()                 |                        |

**Indexes:**

- `attachments_pkey` on (id)
- `attachments_circle_id_idx` on (circle_id)
- `attachments_handoff_id_idx` on (handoff_id)
- `attachments_storage_key_key` on (storage_key) UNIQUE

**RLS Policies:**

- SELECT: User is a member of the circle
- INSERT: OWNER, ADMIN, or CONTRIBUTOR
- DELETE: Uploader, OWNER, or ADMIN

---

## Table: audit_events

Immutable audit log for sensitive actions.

| Column          | Type        | Constraints                   | Description                        |
| --------------- | ----------- | ----------------------------- | ---------------------------------- |
| id              | uuid        | PK, DEFAULT gen_random_uuid() |                                    |
| circle_id       | uuid        | FK circles(id), NOT NULL      |                                    |
| actor_user_id   | uuid        | FK users(id), NOT NULL        |                                    |
| event_type      | text        | NOT NULL                      | e.g., MEMBER_INVITED, ROLE_CHANGED |
| object_type     | text        | NOT NULL                      | e.g., circle_member, handoff       |
| object_id       | uuid        | nullable                      |                                    |
| ip_hash         | text        | nullable                      | Hashed IP for privacy              |
| user_agent_hash | text        | nullable                      |                                    |
| metadata_json   | jsonb       | DEFAULT '{}'                  | Additional context                 |
| created_at      | timestamptz | DEFAULT now()                 |                                    |

**Indexes:**

- `audit_events_pkey` on (id)
- `audit_events_circle_id_idx` on (circle_id)
- `audit_events_created_at_idx` on (created_at)
- `audit_events_event_type_idx` on (event_type)

**RLS Policies:**

- SELECT: OWNER or ADMIN of the circle
- INSERT: System/Edge Functions only

---

## Table: notification_outbox

Queue for push notifications.

| Column            | Type        | Constraints                   | Description                           |
| ----------------- | ----------- | ----------------------------- | ------------------------------------- |
| id                | uuid        | PK, DEFAULT gen_random_uuid() |                                       |
| user_id           | uuid        | FK users(id), NOT NULL        | Recipient                             |
| circle_id         | uuid        | FK circles(id), NOT NULL      |                                       |
| notification_type | text        | NOT NULL                      | HANDOFF_PUBLISHED, TASK_ASSIGNED, etc |
| title             | text        | NOT NULL                      | Notification title                    |
| body              | text        | NOT NULL                      | Notification body (no PHI)            |
| data_json         | jsonb       | DEFAULT '{}'                  | Deep link data                        |
| status            | text        | DEFAULT 'PENDING'             | PENDING, SENT, FAILED                 |
| attempts          | int         | DEFAULT 0                     |                                       |
| sent_at           | timestamptz | nullable                      |                                       |
| created_at        | timestamptz | DEFAULT now()                 |                                       |

**Indexes:**

- `notification_outbox_pkey` on (id)
- `notification_outbox_status_idx` on (status) WHERE status = 'PENDING'
- `notification_outbox_user_id_idx` on (user_id)

**RLS Policies:**

- SELECT: User's own notifications
- INSERT: System/Edge Functions only
- UPDATE: System only

---

## Storage Buckets

### attachments

- **Purpose:** User-uploaded documents and photos
- **Access:** Signed URLs only (1 hour expiry)
- **Retention:** Until user deletes
- **RLS:** Authenticated users who are members of the associated circle

### handoff-audio

- **Purpose:** Audio recordings for handoffs
- **Access:** Signed URLs only (1 hour expiry)
- **Retention:** 30 days default (configurable per circle)
- **RLS:** Authenticated users who are members of the associated circle

### exports

- **Purpose:** Generated PDF care summaries
- **Access:** Signed URLs only (1 hour expiry)
- **Retention:** 7 days (regenerate on demand)
- **RLS:** Authenticated users who are members of the associated circle

---

## Database Functions

### update_updated_at()

Trigger function to maintain `updated_at` timestamps.

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### is_circle_member(circle_uuid, user_uuid)

Helper function for RLS policies.

```sql
CREATE OR REPLACE FUNCTION is_circle_member(circle_uuid uuid, user_uuid uuid)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM circle_members
        WHERE circle_id = circle_uuid
        AND user_id = user_uuid
        AND status = 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### get_circle_role(circle_uuid, user_uuid)

Get user's role in a circle.

```sql
CREATE OR REPLACE FUNCTION get_circle_role(circle_uuid uuid, user_uuid uuid)
RETURNS text AS $$
BEGIN
    RETURN (
        SELECT role FROM circle_members
        WHERE circle_id = circle_uuid
        AND user_id = user_uuid
        AND status = 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```
