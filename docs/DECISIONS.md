# CuraKnot — Architectural Decisions Log

> All decisions affecting architecture, technology choices, or deviations from spec are logged here with timestamps and rationale.

---

## 2026-02-05: Condition Photo DI — Extension with Associated Objects

**Decision:** Use a `DependencyContainer+ConditionPhotos.swift` extension file with Objective-C associated objects for `photoStorageManager` and `conditionPhotoService` properties, instead of adding `lazy var` properties to `DependencyContainer.swift`.

**Rationale:** Xcode (running with the project open) kept overwriting modifications to `DependencyContainer.swift` with its in-memory buffer. An extension file is not subject to this problem since Xcode doesn't have it cached.

**Alternatives considered:**

- Direct `lazy var` in DependencyContainer.swift: Reverted by Xcode file watcher repeatedly
- File-private globals with computed properties: Not instance-scoped (shared across DependencyContainer instances)
- Factory pattern: Would require changing all view call sites

**Implications:** The associated objects pattern provides instance-scoped caching equivalent to `lazy var`. Uses `do/catch/fatalError` matching existing DependencyContainer init pattern. When DependencyContainer.swift can be safely edited (Xcode closed), the properties could be moved inline.

---

## 2026-02-05: Condition Photo Storage — Private Supabase Bucket with Signed URLs

**Decision:** Use a private Supabase Storage bucket (`condition-photos`) with 15-minute signed URLs for photo access, rather than public URLs or client-side encryption.

**Rationale:** Signed URLs provide time-limited access controlled by RLS policies. The bucket is private (no public access), and RLS policies validate circle membership and role before allowing upload/read/delete operations. Storage path format `{circle_id}/{condition_id}/{photo_id}.jpg` enables path-based access validation.

**Alternatives considered:**

- Public bucket with obscurity: No access control, violates PHI-adjacent requirements
- Client-side encryption: Adds complexity, breaks server-side image processing

**Implications:** 15-minute TTL means photo URLs expire and must be regenerated. This is acceptable for a medical photo feature where data should not persist in browser caches.

---

## 2026-01-29: Local Persistence — GRDB

**Decision:** Use GRDB instead of Core Data for iOS local persistence.

**Alternatives Considered:**

1. **Core Data** — Apple's native solution, deep SwiftUI integration, CloudKit-ready
2. **GRDB** — Type-safe Swift API, explicit SQL control, simpler migrations

**Rationale:**

- GRDB provides explicit control over SQL queries, making sync logic more predictable
- Type-safe record types align with our domain models
- Migrations are straightforward SQL files matching our Supabase migration pattern
- Better testability with in-memory databases
- No CloudKit sync needed (we use Supabase exclusively)

**Trade-offs:**

- Requires manual relationship management (acceptable for our schema complexity)
- Less automatic SwiftUI integration than Core Data with @FetchRequest

---

## 2026-01-29: Invite System — circle_invites Table

**Decision:** Use a dedicated `circle_invites` table with Edge Function validation instead of Supabase Auth magic-link metadata.

**Alternatives Considered:**

1. **circle_invites table** — Explicit invite records with revocation, expiry, role assignment
2. **Magic-link metadata** — Store invite data in Supabase Auth link metadata

**Rationale:**

- Supports invite revocation before use
- Explicit expiry timestamps with query-based cleanup
- Role assignment at invite creation time
- Audit trail of who invited whom and when
- Can limit invites per circle based on plan

**Trade-offs:**

- Requires Edge Function for validation (acceptable complexity)
- Extra table and RLS policies

---

## 2026-01-29: Development Environment — Local Supabase CLI First

**Decision:** Start with local Supabase CLI development before deploying to hosted project.

**Rationale:**

- Fast iteration without network latency
- Safe to experiment with migrations
- No costs during initial development
- Easy to reset and reseed
- CI-friendly for testing

---

## 2026-01-29: Storage Bucket Strategy

**Decision:** Three separate storage buckets with different retention policies.

**Buckets:**

1. `attachments` — User-uploaded documents, photos (retained until deleted)
2. `handoff-audio` — Audio recordings (30-day default retention, configurable)
3. `exports` — Generated PDFs (7-day retention, regenerate on demand)

**Rationale:**

- Different retention policies per content type
- Easier storage usage tracking per category
- Cleaner RLS policies per bucket

---

## 2026-01-29: Structured Brief Confidence Threshold

**Decision:** Fields with confidence < 0.7 are marked as "needs confirmation" in the UI.

**Rationale:**

- Balance between requiring too many confirmations (UX friction) and missing errors
- 0.7 threshold based on typical ASR/LLM extraction confidence distributions
- All medication changes require explicit confirmation regardless of confidence

---

## 2026-01-29: Sync Strategy — Incremental with Cursors

**Decision:** Use `updated_at` cursors per entity type for incremental sync.

**Implementation:**

- Each entity table has `updated_at` timestamptz with trigger-based updates
- Client stores last sync cursor per entity type
- Sync fetches records WHERE updated_at > cursor ORDER BY updated_at LIMIT 100
- Tombstones for soft deletes (deleted_at field) included in sync

**Rationale:**

- Simple to implement and debug
- Works well with RLS (client only syncs what they can see)
- Handles clock skew with server-authoritative timestamps

---

## 2026-01-29: Audio Format — AAC/M4A

**Decision:** Record audio in AAC format (.m4a) at 16-48kHz sample rate.

**Rationale:**

- Native iOS support without transcoding
- Good compression (~1MB/minute at quality settings)
- Widely supported by ASR providers
- Background-safe recording with AVAudioSession

---

## Template for Future Decisions

```markdown
## YYYY-MM-DD: [Decision Title]

**Decision:** [One-line summary]

**Alternatives Considered:**

1. [Option A] — [Brief description]
2. [Option B] — [Brief description]

**Rationale:**

- [Reason 1]
- [Reason 2]

**Trade-offs:**

- [Trade-off 1]
```

---

## 2026-02-06: LLM Meeting Summary — Display Names Sent to Third-Party API

**Decision:** User-chosen display names (e.g., "Mom", "Dr. Smith") are included in the data sent to xAI's Grok API for meeting summary generation. Meeting titles and other PHI-adjacent fields are anonymized, but display names are sent as-is.

**Rationale:** Display names are self-chosen identifiers, not legal names. Including them produces actionable summaries ("Jane will handle pharmacy pickup" vs "an attendee will handle pharmacy pickup"). Without names, the summary loses most of its practical value for the care circle.

**Alternatives considered:**

- Strip all names: Summary quality degrades significantly — action items become ambiguous ("someone will do X")
- Replace with pseudonyms (Attendee 1, Attendee 2): Requires a mapping table, still loses readability, adds complexity
- Run LLM locally / self-hosted: Not feasible for Edge Functions; would require a separate inference server

**Implications:**

- A BAA with xAI is required before production use if display names are considered PHI
- If a user sets their display name to a legal name, that name will be sent to xAI
- The meeting title is NOT sent (anonymized to "Family Care Meeting") — only display names and agenda content
- The function checks `XAI_API_KEY` availability and usage limits before making any API call
- Falls back gracefully to template-based summary if LLM is unavailable

---

## 2026-02-07: Multi-Language Translation Architecture

**Decision:** Implemented translation via Supabase Edge Functions calling OpenAI gpt-4o-mini, with server-side caching in a dedicated translation_cache table, and client-side in-memory LRU cache (200 entries, 1-hour TTL).

**Rationale:**

- Edge Function approach keeps API keys server-side and allows centralized caching
- OpenAI gpt-4o-mini provides good translation quality at low cost, with medical context prompts
- Separate cache table (vs. inline on handoff_translations) enables cross-handoff cache reuse for common phrases
- Client-side LRU cache reduces network calls for recently viewed content

**Alternatives considered:**

- Direct Google Translate/DeepL API: Rejected because we already use OpenAI and can add medical context to prompts
- Client-side translation (Apple Translate framework): Rejected because quality varies, no custom glossary support, and not all target languages are supported offline
- Storing translations inline on handoffs table: Rejected because cache reuse across handoffs is more efficient

**Implications:**

- Translation quality depends on OpenAI model; can swap to specialized medical translation API later
- Cache invalidation when handoff content changes requires marking translations as stale
- Glossary terms are per-circle, enabling family-specific medical terminology
- Medication name protection uses regex extraction and placeholder substitution

## 2026-02-07: Translation Tier Gating Strategy

**Decision:** FREE tier gets no translation, PLUS gets English ↔ Spanish only, FAMILY gets all 7 languages plus custom medical glossary.

**Rationale:**

- Translation has ongoing API costs per call
- Spanish is the most requested second language for US caregiving population
- Custom glossary is a premium differentiation feature for multi-lingual families
- English-only users (majority) don't need translation, so FREE tier exclusion is fair

**Alternatives considered:**

- Metered translation (N free translations/month): More complex to track, confusing UX
- All languages for PLUS, glossary for FAMILY only: Reduces FAMILY tier value proposition
- Community-contributed translations: Quality risk for medical content

**Implications:**

- PLUS tier value is clear: "translate for your Spanish-speaking family members"
- FAMILY tier value: "support your entire multilingual care team"
- Language expansion (Phase 2) automatically available to FAMILY tier subscribers
