# Feature Spec 02 — Medication Reconciliation (Scan Labels + OCR + Verification)

> Date: 2026-01-29 | Differentiator: high-trust med list accuracy with provenance

## 1. Problem Statement

Medication lists are frequently wrong or stale. Families receive updates via discharge paperwork, verbal instructions, or pill bottle labels. Manual entry is error-prone. CuraKnot needs a camera-first workflow that creates **verified** structured meds with provenance and deltas.

## 2. Differentiation and Moat

- Binder meds become reconciled source-of-truth, not a manual list.
- Camera-first decreases friction and creates a repeatable habit.
- Provenance + verification trail is defensible and trust-building.
- Premium lever: advanced OCR, multi-source compare, history, alerts.

## 3. Goals

- [ ] Scan labels and printed med lists to propose structured entries.
- [ ] Require explicit confirmation before activation.
- [ ] Track provenance (source docs/images) and accepted-by/accepted-at.
- [ ] Detect deltas vs existing meds; generate follow-up tasks for ambiguity.
- [ ] Optionally publish a med reconciliation handoff summarizing changes.

## 4. Non-Goals

- [ ] No medical recommendations.
- [ ] No pharmacy integrations in this phase.
- [ ] No auto-activation.

## 5. UX Flow

- Binder → Medications → Scan.
- Capture: multi-photo or PDF import.
- Process: OCR + parse + diff → Proposed meds list with confidence.
- Review: confirm key fields (name, dose, schedule) → accept/reject.
- Apply: update binder meds; optionally create handoff + tasks.

## 6. Functional Requirements

- [ ] Store OCR text as protected field; never log.
- [ ] Never overwrite existing meds directly; stage proposals.
- [ ] Field-level confidence and unknown allowed.
- [ ] Compute duplicates/conflicts heuristics; show warnings.
- [ ] Audit events for accept/reject and activation changes.

## 7. Data Model

```sql

create table if not exists public.med_scan_sessions (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  created_by uuid not null,
  status text not null default 'PENDING',     -- PENDING|PROCESSING|READY|FAILED
  source_object_keys text[] not null,         -- Storage keys in attachments bucket
  ocr_text text,                              -- protected
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.med_proposals (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.med_scan_sessions(id) on delete cascade,
  circle_id uuid not null,
  patient_id uuid not null,
  proposed_json jsonb not null,               -- parsed med fields + per-field confidence
  diff_json jsonb,
  status text not null default 'PROPOSED',     -- PROPOSED|ACCEPTED|REJECTED
  accepted_by uuid,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
```

## 8. RLS & Privacy

- Only circle members can read sessions/proposals; optionally restrict ocr_text to contributors+.
- All scan images via signed URLs; short TTL; retention controls.
- Accepted proposals become binder med items with provenance fields.

## 9. Edge Functions / Jobs

- [ ] ocr_med_scan: OCR images/PDF; store ocr_text; create proposals.
- [ ] parse_meds: normalize to structured meds; compute diffs.
- [ ] accept_med_proposal: create/update binder meds, log audit, optionally generate handoff.
- [ ] Cleanup cron: enforce retention on scans/ocr_text.

## 10. iOS Notes

- Camera capture with overlay and batch capture; background upload retries.
- Proposal review UI: confirm toggles for required fields; edit fields inline.
- Offline: store scans + proposals locally; sync when online.

## 11. Metrics

- Reconciliation sessions per circle per month.
- Completion time; acceptance rate of proposals.
- Retention lift vs non-reconcilers; premium conversion proxy.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
