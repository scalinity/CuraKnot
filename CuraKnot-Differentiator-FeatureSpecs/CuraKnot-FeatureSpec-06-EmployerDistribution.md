# Feature Spec 06 — Employer/Insurer Distribution Pack (B2B2C Readiness)

> Date: 2026-01-29 | Differentiator: scalable acquisition channel + premium sponsorship

## 1. Problem Statement

DTC caregiver apps face high CAC; employers/insurers can sponsor caregiving benefits. CuraKnot needs entitlement codes, minimal admin console, and privacy-safe aggregated metrics.

## 2. Goals

- [ ] Benefit codes that unlock premium entitlements for a circle or user.
- [ ] Admin console for orgs (no PHI): code creation/revocation, redemption counts, aggregate WAU.
- [ ] k-anonymity thresholds for metrics.
- [ ] Audit events for all entitlement actions.

## 3. Data Model

```sql

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.benefit_codes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null unique,
  plan text not null,
  max_redemptions int not null,
  redeemed_count int not null default 0,
  expires_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists public.benefit_redemptions (
  id uuid primary key default gen_random_uuid(),
  benefit_code_id uuid not null references public.benefit_codes(id) on delete cascade,
  circle_id uuid references public.circles(id) on delete set null,
  user_id uuid not null,
  redeemed_at timestamptz not null default now()
);
```

## 4. Edge Functions

- [ ] create_benefit_code (org admin), redeem_benefit_code (user), org_metrics (aggregated).

## 5. iOS Notes

- Circle Settings → Plan → Redeem code flow.
- Post-redemption receipt UI + feature unlock gating.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
