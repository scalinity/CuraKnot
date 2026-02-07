# Feature Spec 05 — Operational Insights & Alerts (Non-Clinical)

> Date: 2026-01-29 | Differentiator: proactive operational value, high retention

## 1. Problem Statement

Caregiving problems are often operational: overdue tasks, unconfirmed med changes, staleness, and coordination breakdowns. Insights and digests add proactive value and create recurring engagement.

## 2. Goals

- [ ] Weekly digest per patient/circle: highlights, deltas, overdue tasks, open questions.
- [ ] Opt-in alert rules: overdue tasks threshold, unconfirmed meds, staleness, repeated edits.
- [ ] Actionable CTAs (create/assign tasks, confirm meds, schedule shift).
- [ ] Strict non-clinical labeling; use confirmed structured data only.

## 3. Data Model

```sql

create table if not exists public.insight_digests (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  digest_json jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.alert_rules (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete cascade,
  rule_key text not null,
  params_json jsonb not null,
  enabled boolean not null default true,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

create table if not exists public.alert_events (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null,
  patient_id uuid,
  rule_key text not null,
  fired_at timestamptz not null default now(),
  payload_json jsonb not null,
  status text not null default 'OPEN'
);
```

## 4. Jobs / Functions

- [ ] Cron weekly digest generator; hourly alert evaluator.
- [ ] Edge: get_latest_digest, ack_alert, dismiss_alert.

## 5. iOS Notes

- Digest card on Timeline; alerts inbox in Circle Settings.
- User controls for notification frequency + quiet hours.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
