# Feature Spec 03 — Shift Handoff Mode (Coverage + Checklist + Summary)

> Date: 2026-01-29 | Differentiator: professional-grade care operations ritual

## 1. Problem Statement

Multi-person caregiving fails at shift changes. Families need a structured ritual: what to check at the start, what changed since last shift, and what must be handed off at the end.

## 2. Goals

- [ ] Create informal coverage shifts (who is responsible when).
- [ ] Start-of-shift checklist and delta view since last shift.
- [ ] End-of-shift summary auto-generated into a draft handoff.
- [ ] Optional notifications for shift boundaries.

## 3. Data Model

```sql

create table if not exists public.care_shifts (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  owner_user_id uuid not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'SCHEDULED',
  checklist_json jsonb not null default '[]',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

## 4. Edge Functions

- [ ] compute_shift_changes: compute delta payload since prior shift.
- [ ] finalize_shift: generate draft structured brief from activity + checklist.
- [ ] Cron reminders for upcoming shifts (optional).

## 5. iOS Notes

- Shift Mode screen; large tap targets; offline-first checklist.
- Draft generation uses local cache + server pull to avoid missing remote changes.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
