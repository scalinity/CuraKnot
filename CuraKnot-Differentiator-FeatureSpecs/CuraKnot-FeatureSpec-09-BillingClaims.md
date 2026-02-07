# Feature Spec 09 — Billing & Claims Organizer (Bills, EOBs, Authorizations)

> Date: 2026-01-29 | Differentiator: high-WTP caregiver surface without becoming a finance app

## 1. Problem Statement

Caregiving includes financial operations (bills, claims, EOBs). Families lose time and money due to missed deadlines and missing documents. A focused organizer increases willingness-to-pay and expands CuraKnot’s perceived value.

## 2. Goals

- [ ] Track bills/claims with due dates, statuses, and attachments.
- [ ] Link to tasks and handoffs; reminder workflows.
- [ ] Export summary (PDF/CSV) for date range (premium).
- [ ] Conservative privacy handling for reference IDs.

## 3. Data Model

```sql

create table if not exists public.financial_items (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete set null,
  created_by uuid not null,
  kind text not null,                  -- BILL|CLAIM|EOB|AUTH|RECEIPT
  vendor text,
  amount_cents int,
  currency text default 'USD',
  due_at timestamptz,
  status text not null default 'OPEN',  -- OPEN|SUBMITTED|PAID|DENIED|CLOSED
  reference_id text,
  notes text,
  attachment_ids uuid[] default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

## 4. Edge Functions

- [ ] generate_financial_export (PDF/CSV); scan_eob later.

## 5. iOS Notes

- Binder subsection Billing & Claims with templates and due reminders.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
