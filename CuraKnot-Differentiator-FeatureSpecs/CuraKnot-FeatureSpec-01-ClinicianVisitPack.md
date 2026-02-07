# Feature Spec 01 — Clinician Visit Pack (Appointment Brief + Share Link)

> Date: 2026-01-29 | Differentiator: clinician-facing artifact + ritualized workflow

## 1. Problem Statement

Caregivers repeatedly lose context during clinician appointments: key symptoms, medication deltas, and open questions get scattered across memory, texts, papers, and multiple family members. Generic exports help, but visits need a **structured, time-bounded brief** optimized for rapid clinical intake and follow-through.

## 2. Differentiation and Moat

- Transforms CuraKnot from passive record → appointment-performance tool with measurable value.
- Creates a repeatable ritual: Pre-visit pack → After-visit decisions handoff.
- Secure share-link view reduces friction for clinicians without requiring an account.
- Premium lever: advanced templates, longitudinal trends, multi-visit packs.

## 3. Goals

- [ ] Generate Appointment Brief for selected patient and date range (default last 14 days).
- [ ] Output both PDF and secure web view (token + TTL).
- [ ] Include med deltas, key events, open questions, pending decisions, and tasks.
- [ ] After-visit capture that converts decisions into tasks + binder updates.
- [ ] Full audit trail; no transcripts/audio in pack.

## 4. Non-Goals

- [ ] No clinical decision support/diagnosis.
- [ ] No EHR writeback.
- [ ] No permanent public links.

## 5. UX Flow

- Entry: Patient header → Visit Pack OR Circle → Exports → Visit Pack.
- Select: patient, date range, template.
- Preview: section outline + counts.
- Generate: progress → Open web view / Share PDF / Copy link.
- After visit: CTA Create After-Visit Handoff (special template).

## 6. Functional Requirements

- [ ] Compose from confirmed structured data only (handoff summaries, med changes, tasks, binder).
- [ ] Compute medication deltas: START/STOP/DOSE/SCHEDULE changes within range; exclude unconfirmed.
- [ ] Allow collaborative Questions to ask list with authorship and timestamps.
- [ ] Share link TTL default 24h; revocable; read-only; access audit logged.
- [ ] PDF stored in Storage exports with signed URL only.

## 7. Data Model (Supabase)

```sql

create table if not exists public.appointment_packs (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  created_by uuid not null,
  range_start timestamptz not null,
  range_end timestamptz not null,
  template text not null default 'general',
  content_json jsonb not null,
  pdf_object_key text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.share_links (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  object_type text not null,  -- 'appointment_pack'
  object_id uuid not null,
  token text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now()
);
```

## 8. RLS & Security

- appointment_packs: readable by circle members; writable by contributors+.
- share_links: create/revoke by circle members; token-resolve via Edge Function enforcing TTL/revocation.
- Clinician web view returns sanitized payload: no internal IDs; no transcripts/audio.

## 9. Edge Functions / Jobs

- [ ] generate_appointment_pack: compose content_json + render PDF + store to exports + insert row.
- [ ] create_share_link / resolve_share_link: token lifecycle + access auditing.
- [ ] Cron cleanup: expire tokens; enforce retention on exports per circle settings.

## 10. iOS Implementation Notes

- SwiftUI Visit Pack screen with template selector and preview outline.
- Share sheet supports link + PDF file (download via signed URL).
- After-visit template pre-populates: decisions, med changes, follow-ups, questions.

## 11. Metrics

- Activation: % circles generating pack within 14 days.
- Engagement: packs/month/circle; collaborators adding questions.
- Retention lift for pack users; post-visit task creation rate.

## 12. Risks / Mitigations

- Doc too long → force 1-page summary + collapsible sections.
- Privacy leakage → short TTL, revocation, access audit, minimal payload.
- Incorrect med deltas → only confirmed changes; explicit labeling.

---

### Linkage
- Product: CuraKnot
- Stack: Supabase (Postgres/RLS/Storage/Edge Functions) + iOS (SwiftUI)
- Baseline: `./CuraKnot-spec.md`
