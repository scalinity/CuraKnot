# Feature Spec 07 — Emergency Card (Offline, QR Share, Wallet Pass)

> Date: 2026-01-29 | Differentiator: ultra-practical safety artifact + viral sharing vector

## 1. Problem Statement

In emergencies, caregivers and responders need critical info fast, often offline. CuraKnot can generate a controlled emergency summary with conservative defaults and optional tokenized QR sharing.

## 2. Goals

- [ ] Offline emergency card view in iOS.
- [ ] Configurable included fields with conservative defaults.
- [ ] Optional QR share link (token + TTL, revocable, access-audited).
- [ ] Optional Apple Wallet pass (Phase 2) with minimal fields.

## 3. Data Model

```sql

create table if not exists public.emergency_cards (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  created_by uuid not null,
  config_json jsonb not null,
  snapshot_json jsonb not null,
  updated_at timestamptz not null default now()
);
```

## 4. Edge Functions

- [ ] generate_emergency_card, create_emergency_share (reuse share_links), resolve_emergency_share, wallet_pass (Phase 2).

## 5. iOS Notes

- Patient menu → Emergency Card; cache snapshot offline.
- QR code display gated by explicit toggle + explanation.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
