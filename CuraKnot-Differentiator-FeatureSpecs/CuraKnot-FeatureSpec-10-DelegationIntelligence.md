# Feature Spec 10 — Delegation Intelligence (Suggested Owners, Load Balancing)

> Date: 2026-01-29 | Differentiator: operational personalization that reduces burnout

## 1. Problem Statement

Caregiving collapses when one person carries all tasks. Assigning work effectively is hard. Operational suggestions based on task metadata can improve delegation without practicing medicine or therapy.

## 2. Goals

- [ ] Suggest task owner and reminder defaults using explainable scoring.
- [ ] Admin-only workload dashboard; personal stats for members.
- [ ] Never auto-reassign; always require confirmation.
- [ ] Transparency and opt-out.

## 3. Data Model

```sql

create table if not exists public.member_stats (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null,
  stats_json jsonb not null,
  computed_at timestamptz not null default now(),
  unique(circle_id, user_id)
);

create table if not exists public.task_tags (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  tag text not null
);
```

## 4. Jobs / Edge Functions

- [ ] Nightly stats aggregator; suggest_task_owner; get_workload_dashboard.

## 5. iOS Notes

- Task creation UI shows suggestions + Why; dashboard in Circle Settings for admins.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
