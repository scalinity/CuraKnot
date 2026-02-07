# Feature Spec 08 — Care Inbox (Unified Capture + Triage + Routing)

> Date: 2026-01-29 | Differentiator: default capture surface for messy incoming care info

## 1. Problem Statement

Care info arrives everywhere (papers, photos, calls, notes). A timeline requires intentional entry. An Inbox allows quick capture now and structured routing later, preventing loss and increasing engagement.

## 2. Goals

- [ ] Quick capture items (photo/PDF/audio/text) into Inbox.
- [ ] Triage routes item to: Handoff draft, Task, Binder, or Archive.
- [ ] Assign items to a member for processing.
- [ ] Retention and privacy controls for captured artifacts.

## 3. Data Model

```sql

create table if not exists public.inbox_items (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete set null,
  created_by uuid not null,
  kind text not null,                  -- PHOTO|PDF|AUDIO|TEXT
  status text not null default 'NEW',   -- NEW|ASSIGNED|TRIAGED|ARCHIVED
  assigned_to uuid,
  title text,
  note text,
  attachment_id uuid references public.attachments(id) on delete set null,
  text_payload text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

## 4. Edge Functions

- [ ] triage_inbox_item routes to target entity; optional suggest_inbox_action later.

## 5. iOS Notes

- Global Quick Capture → Send to Inbox.
- Inbox list + triage screen; offline queueing and uploads.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
