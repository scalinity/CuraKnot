# CuraKnot — API Contract

> Edge Functions, RPC endpoints, expected inputs/outputs, and error codes.

---

## Authentication

All API requests require a valid Supabase JWT in the Authorization header:

```
Authorization: Bearer <jwt_token>
```

The JWT is obtained via Sign in with Apple through Supabase Auth.

---

## Edge Functions

### POST /functions/v1/validate-invite

Validate an invite token and add user to circle.

**Request:**

```json
{
  "token": "abc123..."
}
```

**Response (Success - 200):**

```json
{
  "success": true,
  "circle_id": "uuid",
  "circle_name": "Grandma Care",
  "role": "CONTRIBUTOR"
}
```

**Response (Error - 400/404):**

```json
{
  "error": {
    "code": "CIRCLE_INVITE_EXPIRED",
    "message": "This invite link has expired"
  }
}
```

**Error Codes:**

- `CIRCLE_INVITE_EXPIRED` — Token past expiry date
- `CIRCLE_INVITE_REVOKED` — Token was revoked
- `CIRCLE_INVITE_USED` — Token already used
- `CIRCLE_INVITE_NOT_FOUND` — Invalid token

---

### POST /functions/v1/transcribe-handoff

Upload audio and trigger transcription.

**Request (multipart/form-data):**

- `handoff_id`: UUID of the handoff
- `audio`: Audio file (AAC/M4A)

**Response (Success - 202):**

```json
{
  "job_id": "uuid",
  "status": "PENDING",
  "estimated_seconds": 30
}
```

**Error Codes:**

- `UPLOAD_TOO_LARGE` — File exceeds size limit
- `UPLOAD_UNSUPPORTED_MIME` — Invalid audio format
- `AUTH_NOT_MEMBER` — User not in circle
- `ASR_RATE_LIMIT` — Too many concurrent jobs

---

### GET /functions/v1/transcribe-handoff/{job_id}

Poll transcription job status.

**Response (Pending - 200):**

```json
{
  "job_id": "uuid",
  "status": "RUNNING",
  "progress": 0.45
}
```

**Response (Complete - 200):**

```json
{
  "job_id": "uuid",
  "status": "COMPLETED",
  "transcript": "The doctor said...",
  "duration_ms": 45000,
  "language": "en"
}
```

**Response (Failed - 200):**

```json
{
  "job_id": "uuid",
  "status": "FAILED",
  "error": {
    "code": "ASR_AUDIO_CORRUPT",
    "message": "Could not process audio file"
  }
}
```

**Error Codes:**

- `ASR_JOB_TIMEOUT` — Job took too long
- `ASR_JOB_FAILED` — Processing error
- `ASR_AUDIO_CORRUPT` — Invalid audio data
- `ASR_LANG_UNSUPPORTED` — Language not supported

---

### POST /functions/v1/structure-handoff

Generate structured brief from transcript.

**Request:**

```json
{
  "handoff_id": "uuid",
  "transcript": "The doctor said...",
  "handoff_type": "VISIT",
  "patient_id": "uuid"
}
```

**Response (Success - 200):**

```json
{
  "structured_brief": {
    "title": "Visit with Dr. Smith",
    "summary": "Discussed medication adjustments...",
    "status": {
      "mood_energy": "Good spirits, some fatigue",
      "pain": 3,
      "appetite": "Normal",
      "sleep": "7 hours",
      "mobility": "Walking with cane",
      "safety_flags": []
    },
    "changes": {
      "med_changes": [
        {
          "name": "Metformin",
          "change": "DOSE",
          "details": "Increased from 500mg to 750mg",
          "effective": "2026-01-30"
        }
      ],
      "symptom_changes": [],
      "care_plan_changes": []
    },
    "questions_for_clinician": [],
    "next_steps": [
      {
        "action": "Pick up new prescription",
        "suggested_owner": null,
        "due": "2026-01-31T17:00:00Z",
        "priority": "HIGH"
      }
    ],
    "keywords": ["metformin", "dosage", "diabetes"]
  },
  "confidence": {
    "overall": 0.85,
    "fields": {
      "summary": 0.92,
      "med_changes": 0.78,
      "next_steps": 0.88
    }
  }
}
```

**Error Codes:**

- `STRUCT_SCHEMA_INVALID` — Output failed validation
- `STRUCT_LOW_CONFIDENCE` — Extraction confidence too low
- `STRUCT_MODEL_UNAVAILABLE` — LLM service unavailable

---

### POST /functions/v1/publish-handoff

Publish a handoff after user confirmation.

**Request:**

```json
{
  "handoff_id": "uuid",
  "structured_json": {
    /* StructuredBrief */
  },
  "confirmations": {
    "med_changes_confirmed": true,
    "due_dates_confirmed": true
  }
}
```

**Response (Success - 200):**

```json
{
  "handoff_id": "uuid",
  "revision": 1,
  "published_at": "2026-01-29T15:30:00Z",
  "notifications_queued": 3
}
```

**Error Codes:**

- `STRUCT_REQUIRES_CONFIRMATION` — Med changes not confirmed
- `STRUCT_VALIDATION_FAILED` — Invalid structured brief
- `AUTH_ROLE_FORBIDDEN` — User cannot publish

---

### POST /functions/v1/generate-care-summary

Generate PDF care summary for export.

**Request:**

```json
{
  "circle_id": "uuid",
  "patient_ids": ["uuid", "uuid"],
  "start_date": "2026-01-01",
  "end_date": "2026-01-29",
  "include_sections": {
    "handoffs": true,
    "med_changes": true,
    "open_questions": true,
    "tasks": true,
    "contacts": true
  }
}
```

**Response (Success - 200):**

```json
{
  "export_id": "uuid",
  "download_url": "https://...signed-url...",
  "expires_at": "2026-01-29T16:30:00Z",
  "page_count": 3,
  "generated_at": "2026-01-29T15:30:00Z"
}
```

**Error Codes:**

- `EXPORT_NO_DATA` — No content in date range
- `EXPORT_PDF_FAILED` — PDF generation error
- `EXPORT_RATE_LIMIT` — Too many exports
- `EXPORT_PERMISSION_DENIED` — User cannot export

---

## Supabase RPC Functions

### rpc/complete_task

Mark a task as completed with immutable log.

**Request:**

```json
{
  "task_id": "uuid",
  "completion_note": "Called pharmacy, prescription ready"
}
```

**Response:**

```json
{
  "task_id": "uuid",
  "status": "DONE",
  "completed_at": "2026-01-29T15:30:00Z",
  "completed_by": "uuid"
}
```

---

## REST Endpoints (via Supabase PostgREST)

All standard CRUD operations use PostgREST conventions with RLS enforcement.

### Circles

```
GET    /rest/v1/circles                    # List user's circles
POST   /rest/v1/circles                    # Create circle
GET    /rest/v1/circles?id=eq.{id}         # Get circle
PATCH  /rest/v1/circles?id=eq.{id}         # Update circle
```

### Patients

```
GET    /rest/v1/patients?circle_id=eq.{id} # List patients in circle
POST   /rest/v1/patients                   # Create patient
PATCH  /rest/v1/patients?id=eq.{id}        # Update patient
```

### Handoffs

```
GET    /rest/v1/handoffs?circle_id=eq.{id}&order=published_at.desc
POST   /rest/v1/handoffs                   # Create draft
PATCH  /rest/v1/handoffs?id=eq.{id}        # Update draft
```

### Tasks

```
GET    /rest/v1/tasks?circle_id=eq.{id}&status=eq.OPEN
GET    /rest/v1/tasks?owner_user_id=eq.{id}&status=eq.OPEN
POST   /rest/v1/tasks                      # Create task
PATCH  /rest/v1/tasks?id=eq.{id}           # Update task
```

### Binder Items

```
GET    /rest/v1/binder_items?circle_id=eq.{id}&type=eq.MED
POST   /rest/v1/binder_items               # Create item
PATCH  /rest/v1/binder_items?id=eq.{id}    # Update item
```

---

## Sync Endpoints

### GET /rest/v1/{entity}?updated_at=gt.{cursor}&order=updated_at.asc&limit=100

Incremental sync pattern for all entity types.

**Headers:**

```
Prefer: count=exact
```

**Response Headers:**

```
Content-Range: 0-99/250
```

---

## Error Code Reference

### Authentication Errors (AUTH\_\*)

| Code                  | HTTP | Description                        |
| --------------------- | ---- | ---------------------------------- |
| AUTH_INVALID_TOKEN    | 401  | JWT is invalid or malformed        |
| AUTH_TOKEN_EXPIRED    | 401  | JWT has expired                    |
| AUTH_NOT_MEMBER       | 403  | User is not a member of the circle |
| AUTH_ROLE_FORBIDDEN   | 403  | User's role cannot perform action  |
| AUTH_ACCOUNT_DISABLED | 403  | User account is disabled           |

### Circle Errors (CIRCLE\_\*)

| Code                  | HTTP | Description             |
| --------------------- | ---- | ----------------------- |
| CIRCLE_NOT_FOUND      | 404  | Circle does not exist   |
| CIRCLE_INVITE_EXPIRED | 400  | Invite link has expired |
| CIRCLE_INVITE_REVOKED | 400  | Invite was revoked      |
| CIRCLE_PLAN_LIMIT     | 402  | Plan limit exceeded     |
| CIRCLE_DELETED        | 410  | Circle was deleted      |

### Upload Errors (UPLOAD\_\*)

| Code                     | HTTP | Description                 |
| ------------------------ | ---- | --------------------------- |
| UPLOAD_URL_EXPIRED       | 400  | Signed upload URL expired   |
| UPLOAD_TOO_LARGE         | 413  | File exceeds size limit     |
| UPLOAD_UNSUPPORTED_MIME  | 415  | File type not allowed       |
| UPLOAD_CHECKSUM_MISMATCH | 400  | File integrity check failed |
| UPLOAD_NETWORK_ERROR     | 500  | Upload failed               |

### ASR Errors (ASR\_\*)

| Code                 | HTTP | Description                    |
| -------------------- | ---- | ------------------------------ |
| ASR_JOB_TIMEOUT      | 504  | Transcription took too long    |
| ASR_JOB_FAILED       | 500  | Transcription processing error |
| ASR_LANG_UNSUPPORTED | 400  | Language not supported         |
| ASR_AUDIO_CORRUPT    | 400  | Audio file is corrupt          |
| ASR_RATE_LIMIT       | 429  | Too many concurrent jobs       |

### Structure Errors (STRUCT\_\*)

| Code                         | HTTP | Description                |
| ---------------------------- | ---- | -------------------------- |
| STRUCT_SCHEMA_INVALID        | 400  | Output failed JSON schema  |
| STRUCT_LOW_CONFIDENCE        | 400  | Confidence below threshold |
| STRUCT_VALIDATION_FAILED     | 400  | Brief validation failed    |
| STRUCT_REQUIRES_CONFIRMATION | 400  | Confirmations missing      |
| STRUCT_MODEL_UNAVAILABLE     | 503  | LLM service unavailable    |

### Sync Errors (SYNC\_\*)

| Code                      | HTTP | Description                     |
| ------------------------- | ---- | ------------------------------- |
| SYNC_VERSION_MISMATCH     | 409  | Optimistic concurrency conflict |
| SYNC_PARTIAL_FAILURE      | 207  | Some operations failed          |
| SYNC_SERVER_ERROR         | 500  | Server-side sync error          |
| SYNC_CLIENT_CORRUPT_CACHE | 400  | Client cache corrupted          |
| SYNC_RETRY_LATER          | 503  | Temporary unavailable           |

### Export Errors (EXPORT\_\*)

| Code                     | HTTP | Description           |
| ------------------------ | ---- | --------------------- |
| EXPORT_PDF_FAILED        | 500  | PDF generation failed |
| EXPORT_NO_DATA           | 404  | No data in date range |
| EXPORT_PERMISSION_DENIED | 403  | Cannot export         |
| EXPORT_STORAGE_ERROR     | 500  | Storage write failed  |
| EXPORT_RATE_LIMIT        | 429  | Too many exports      |
