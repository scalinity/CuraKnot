# Feature Spec 04 — Facility Helper Portal (Secure External Updates)

> Date: 2026-01-29 | Differentiator: external network channel + workload reduction

## 1. Problem Statement

Facility/home-care staff often communicate via phone and paper, causing gaps and repeated calls. A lightweight external submission portal lets helpers provide structured updates that caregivers can approve and publish.

## 2. Goals

- [ ] Admin creates helper link (token + TTL, patient-scoped).
- [ ] Helper submits structured update + optional attachments without account.
- [ ] Submissions are pending until approved; approved becomes Timeline handoff.
- [ ] Audit + revocation + rate limits.

## 3. Data Model

```sql

create table if not exists public.helper_links (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  token text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

create table if not exists public.helper_submissions (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null,
  patient_id uuid not null,
  helper_link_id uuid not null references public.helper_links(id) on delete cascade,
  submitted_at timestamptz not null default now(),
  status text not null default 'PENDING',
  payload_json jsonb not null,
  attachments uuid[] default '{}',
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text
);
```

## 4. Edge Functions

- [ ] helper_get_form: validate token, return safe patient label + schema.
- [ ] helper_submit_update: store PENDING submission; upload attachments; rate limit.
- [ ] review_helper_submission: approve/reject; on approve generate handoff + audit.
- [ ] revoke_helper_link.

## 5. iOS Notes

- Helpers admin screen: create/revoke links; review submissions inbox.
- Approved updates appear in Timeline with External helper badge.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
