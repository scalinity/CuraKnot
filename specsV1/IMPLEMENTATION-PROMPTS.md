# CuraKnot Feature Implementation Prompts

> 20 Claude Code Prompts for Implementing Differentiator Features
> Aligned with CuraKnot Premium Business Model (Free / Plus / Family tiers)

---

## Usage Instructions

Copy the relevant prompt and paste it into Claude Code when ready to implement that feature. Each prompt includes:

1. **Spec Reference** — Detailed feature specification file
2. **Premium Tier Gating** — What's available at each subscription level
3. **Implementation Scope** — iOS, Supabase, Edge Functions with file paths
4. **Error Handling** — Offline behavior, failure recovery, edge cases
5. **Security Requirements** — Data protection, audit logging, privacy
6. **Testing Requirements** — Unit, integration, and UI tests needed
7. **Accessibility** — VoiceOver, Dynamic Type, inclusive design
8. **Analytics Events** — Tracking for conversion and feature usage
9. **Performance Targets** — SLOs and resource constraints
10. **Acceptance Criteria** — Comprehensive verification checklist

**Tier Reference:**

| Tier       | Price     | Target User         | Key Limits                                         |
| ---------- | --------- | ------------------- | -------------------------------------------------- |
| **Free**   | $0        | New/solo caregivers | 1 circle, 3 members, 1 patient, 10 audio/month     |
| **Plus**   | $9.99/mo  | Primary caregivers  | 3 circles, 10 members, 3 patients, unlimited audio |
| **Family** | $19.99/mo | Large families      | 5 circles, 25 members, 5 patients, all features    |

**Pre-Implementation Checklist (All Features):**

- [ ] Read the detailed spec file completely
- [ ] Verify all dependent features/tables exist
- [ ] Check `circle.plan` field exists and is populated
- [ ] Review existing similar implementations in codebase
- [ ] Confirm Supabase local environment is running

---

## Security & Compliance Patterns (REQUIRED FOR ALL FEATURES)

### Server-Side Tier Enforcement (CRITICAL)

**Never rely solely on iOS-side tier checks.** All tier-gated features MUST have corresponding RLS policies and Edge Function validation.

#### RLS Policy Pattern

```sql
-- Template for tier-gated table access
CREATE POLICY "feature_name_tier_gate"
    ON feature_table FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM circles c
            JOIN circle_members cm ON cm.circle_id = c.id
            WHERE c.id = feature_table.circle_id
              AND cm.user_id = auth.uid()
              AND cm.status = 'ACTIVE'
              AND c.plan IN ('PLUS', 'FAMILY')  -- Adjust per feature
        )
    );

-- For FREE tier with limits (e.g., 5/month)
CREATE POLICY "feature_name_free_limit"
    ON feature_table FOR INSERT
    USING (
        EXISTS (
            SELECT 1 FROM circles c
            JOIN circle_members cm ON cm.circle_id = c.id
            WHERE c.id = feature_table.circle_id
              AND cm.user_id = auth.uid()
              AND (
                  c.plan IN ('PLUS', 'FAMILY')
                  OR (
                      c.plan = 'FREE' AND
                      (SELECT COUNT(*) FROM feature_table ft
                       WHERE ft.circle_id = c.id
                         AND ft.created_at >= date_trunc('month', now())
                      ) < 5  -- Monthly limit for FREE
                  )
              )
        )
    );
```

#### Edge Function Tier Validation

```typescript
// REQUIRED in every tier-gated Edge Function
async function validateTierAccess(
  supabase: SupabaseClient,
  userId: string,
  circleId: string,
  requiredTiers: ('FREE' | 'PLUS' | 'FAMILY')[],
  featureLimits?: { free?: number; plus?: number }
): Promise<{ allowed: boolean; reason?: string; usage?: number; limit?: number }> {
  
  // Get circle plan
  const { data: circle } = await supabase
    .from('circles')
    .select('plan')
    .eq('id', circleId)
    .single();
  
  if (!circle || !requiredTiers.includes(circle.plan)) {
    return { 
      allowed: false, 
      reason: 'TIER_REQUIRED',
      requiredTiers 
    };
  }
  
  // Check usage limits for FREE tier
  if (circle.plan === 'FREE' && featureLimits?.free) {
    const { count } = await supabase
      .from('feature_usage')
      .select('*', { count: 'exact', head: true })
      .eq('circle_id', circleId)
      .gte('created_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString());
    
    if ((count || 0) >= featureLimits.free) {
      return {
        allowed: false,
        reason: 'LIMIT_REACHED',
        usage: count || 0,
        limit: featureLimits.free
      };
    }
  }
  
  return { allowed: true };
}
```

### PHI Context Sanitization (CRITICAL for AI Features)

**Never send raw PHI to external LLMs.** All context must be sanitized:

```typescript
// context-sanitizer.ts - REQUIRED for AI features
interface SanitizedContext {
  sanitizedText: string;
  entityMap: Map<string, string>;  // For internal reference only
}

export function sanitizeContextForLLM(
  handoffs: Handoff[],
  patient: Patient,
  medications: Medication[]
): SanitizedContext {
  const entityMap = new Map<string, string>();
  
  // 1. Replace patient name with generic reference
  entityMap.set(patient.name, 'the patient');
  entityMap.set(patient.id, '[PATIENT_ID]');
  
  // 2. Replace all circle member names
  // "John said..." -> "A family caregiver said..."
  
  // 3. Replace specific dates with relative references
  // "On February 5, 2026" -> "3 days ago"
  
  // 4. Summarize, don't quote verbatim
  // Instead of full handoff text, extract key points:
  // - Symptoms mentioned (without direct quotes)
  // - Medication concerns (generic, not dosages)
  // - Care coordination needs
  
  // 5. Never include:
  // - Full addresses
  // - Phone numbers
  // - Social Security numbers
  // - Insurance policy numbers
  // - Specific financial amounts
  
  // 6. Medication handling:
  // - Include drug class, not specific brand if possible
  // - "Taking a blood pressure medication" vs "Lisinopril 10mg"
  // - Only include specific meds if clinically relevant to query
  
  const sanitizedText = buildSanitizedSummary(handoffs, entityMap);
  
  return { sanitizedText, entityMap };
}

// Maximum context size to prevent data exfiltration
const MAX_CONTEXT_TOKENS = 2000;
const MAX_HANDOFFS_IN_CONTEXT = 10;
const MAX_MEDICATIONS_IN_CONTEXT = 15;
```

### Parameterized Queries (CRITICAL)

**ALL database queries MUST use parameterized statements.** Never interpolate user input.

```typescript
// ❌ WRONG - SQL Injection Risk
const query = `SELECT * FROM handoffs WHERE content LIKE '%${userInput}%'`;

// ✅ CORRECT - Parameterized
const { data } = await supabase
  .from('handoffs')
  .select('*')
  .ilike('content', `%${userInput}%`);  // Supabase SDK handles escaping

// ✅ CORRECT - Raw SQL with parameters
const { data } = await supabase.rpc('search_handoffs', {
  search_term: userInput  // Passed as parameter, not interpolated
});
```

### Idempotency Keys (REQUIRED for Edge Functions)

All Edge Functions that create resources MUST support idempotency:

```typescript
// Edge Function idempotency pattern
serve(async (req) => {
  const idempotencyKey = req.headers.get('X-Idempotency-Key');
  
  if (idempotencyKey) {
    // Check for existing operation with this key
    const { data: existing } = await supabase
      .from('idempotency_log')
      .select('response')
      .eq('key', idempotencyKey)
      .eq('endpoint', 'create-handoff')
      .single();
    
    if (existing) {
      // Return cached response
      return new Response(existing.response, {
        headers: { 'X-Idempotent-Replay': 'true' }
      });
    }
  }
  
  // Process request...
  const result = await processRequest();
  
  // Store for idempotency (TTL: 24 hours)
  if (idempotencyKey) {
    await supabase.from('idempotency_log').insert({
      key: idempotencyKey,
      endpoint: 'create-handoff',
      response: JSON.stringify(result),
      expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000)
    });
  }
  
  return new Response(JSON.stringify(result));
});
```

```sql
-- Idempotency log table
CREATE TABLE IF NOT EXISTS idempotency_log (
    key text NOT NULL,
    endpoint text NOT NULL,
    response jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    PRIMARY KEY (key, endpoint)
);

CREATE INDEX idx_idempotency_expires ON idempotency_log(expires_at);
```

### Standardized Usage Tracking

All tier-limited features use a shared usage tracking table:

```sql
CREATE TABLE IF NOT EXISTS feature_usage (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    feature_type text NOT NULL,  -- DOCUMENT_SCAN | FACILITY_LOG | COACH_MESSAGE | etc.
    
    month date NOT NULL,  -- First of month for grouping
    count int NOT NULL DEFAULT 0,
    
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    
    UNIQUE(circle_id, user_id, feature_type, month)
);

-- Usage limits by tier
CREATE TABLE IF NOT EXISTS feature_limits (
    feature_type text PRIMARY KEY,
    free_limit int,          -- NULL = no access
    plus_limit int,          -- NULL = unlimited
    family_limit int,        -- NULL = unlimited
    reset_period text NOT NULL DEFAULT 'MONTHLY'  -- MONTHLY | DAILY | NEVER
);

INSERT INTO feature_limits VALUES
    ('DOCUMENT_SCAN', 5, NULL, NULL),
    ('FACILITY_LOG', 5, NULL, NULL),
    ('COACH_MESSAGE', NULL, 50, NULL),
    ('GRATITUDE_ENTRY', 5, NULL, NULL),
    ('RIDE_LOG', 5, NULL, NULL),
    ('RESPITE_REQUEST', NULL, NULL, NULL);  -- Plus+ only, no limit
```

### Feature Flags Pattern

Support gradual rollout of features:

```swift
// iOS Feature Flags
enum FeatureFlag: String, CaseIterable {
    case aiCareCoach = "ai_care_coach"
    case symptomPatterns = "symptom_patterns"
    case videoBoard = "video_board"
    // ... etc
}

class FeatureFlagService {
    private var flags: [String: Bool] = [:]
    
    func isEnabled(_ flag: FeatureFlag, for user: User) -> Bool {
        // Check remote config first
        if let remote = remoteFlags[flag.rawValue] {
            return remote
        }
        // Fall back to tier-based access
        return user.tier.hasFeature(flag)
    }
    
    func refresh() async {
        // Fetch from Supabase feature_flags table
        let { data } = await supabase
            .from('feature_flags')
            .select('*')
            .eq('is_active', true)
        
        flags = data.reduce(into: [:]) { $0[$1.name] = $1.enabled }
    }
}
```

```sql
CREATE TABLE IF NOT EXISTS feature_flags (
    name text PRIMARY KEY,
    enabled boolean NOT NULL DEFAULT false,
    rollout_percentage int DEFAULT 100,  -- 0-100 for gradual rollout
    allowed_user_ids uuid[],              -- Specific users for beta testing
    is_active boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now()
);
```

### Retry Backoff Specification

All network operations follow this retry pattern:

```typescript
const RETRY_CONFIG = {
  maxAttempts: 3,
  baseDelayMs: 1000,
  maxDelayMs: 10000,
  jitterPercent: 20,  // ±20% randomization
};

async function withRetry<T>(
  operation: () => Promise<T>,
  config = RETRY_CONFIG
): Promise<T> {
  let lastError: Error;
  
  for (let attempt = 1; attempt <= config.maxAttempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      
      if (attempt < config.maxAttempts) {
        const baseDelay = Math.min(
          config.baseDelayMs * Math.pow(2, attempt - 1),
          config.maxDelayMs
        );
        const jitter = baseDelay * (config.jitterPercent / 100) * (Math.random() * 2 - 1);
        await sleep(baseDelay + jitter);
      }
    }
  }
  
  throw lastError;
}
```

### Analytics Event Naming Convention

All analytics events follow `{feature}_{action}` format:

| Feature Prefix | Actions |
|----------------|---------|
| `siri` | `invoke`, `block`, `resolve` |
| `calendar` | `connect`, `sync`, `disconnect`, `error` |
| `watch` | `open`, `capture`, `complete_task`, `emergency` |
| `scanner` | `scan`, `classify`, `extract`, `save` |
| `coach` | `start`, `message`, `limit`, `emergency` |
| `questions` | `generate`, `check`, `add_custom`, `include_pdf` |
| `patterns` | `view`, `tap`, `feedback`, `dismiss` |
| `wellness` | `checkin`, `skip`, `alert_show`, `alert_action` |
| `discharge` | `start`, `step`, `complete`, `scan` |
| `facility_log` | `create`, `followup`, `search` |
| `directory` | `view`, `share`, `export`, `action` |
| `photos` | `capture`, `view`, `compare`, `share` |
| `gratitude` | `create`, `share`, `export_memory_book` |
| `video` | `record`, `play`, `react`, `compile` |
| `meeting` | `start`, `decision`, `action_item`, `complete` |
| `transport` | `schedule`, `volunteer`, `confirm`, `complete` |
| `respite` | `search`, `request`, `review`, `log_days` |
| `legal_vault` | `upload`, `view`, `share`, `expire_alert` |
| `translation` | `translate`, `toggle_original`, `glossary_add` |
| `cost` | `log_expense`, `project`, `export` |

---

## Prompt 1: Siri Shortcuts Integration

```
Implement the Siri Shortcuts Integration feature for CuraKnot.

## Specification
Read `specsV1/01-SiriShortcutsIntegration.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier | Access Level |
|------|--------------|
| FREE | Basic "Create Handoff" and "What's Next Task" only |
| PLUS | Full shortcut library (medications, queries, summaries) |
| FAMILY | Same as Plus |

**Gating Implementation:**
- Check `circle.plan` in AppIntent's `perform()` method
- Return `.needsUpgrade(reason:)` IntentResult for gated features
- Track blocked attempts in analytics for conversion insights

## File Structure

```

ios/CuraKnot/
├── Features/
│ └── SiriShortcuts/
│ ├── Intents/
│ │ ├── CreateHandoffIntent.swift
│ │ ├── QueryNextTaskIntent.swift
│ │ ├── QueryMedicationIntent.swift # Plus+
│ │ ├── QueryLastHandoffIntent.swift # Plus+
│ │ └── QueryPatientStatusIntent.swift # Plus+
│ ├── Entities/
│ │ ├── PatientEntity.swift
│ │ └── PatientEntityQuery.swift
│ ├── AppShortcutsProvider.swift
│ └── SiriShortcutsService.swift
├── Core/
│ └── Extensions/
│ └── Patient+Aliases.swift

````

## Implementation Scope

### 1. iOS App Intents Framework
- Create `AppIntent` conforming structs for each shortcut
- Implement `AppShortcutsProvider` with default phrases
- Create `PatientEntity` conforming to `AppEntity` protocol
- Implement `PatientEntityQuery` for Siri to resolve patient names
- Add `aliases: [String]` property to Patient model

### 2. Siri Phrase Configuration
```swift
// AppShortcuts.swift
static var appShortcuts: [AppShortcut] {
    AppShortcut(
        intent: CreateHandoffIntent(),
        phrases: [
            "Tell \(.applicationName) \(\.$patient) \(\.$message)",
            "Log with \(.applicationName) that \(\.$patient) \(\.$message)",
            "Record in \(.applicationName) \(\.$message) for \(\.$patient)"
        ],
        shortTitle: "Create Handoff",
        systemImageName: "waveform"
    )
    // ... more shortcuts
}
````

### 3. Background Processing

- Handle voice capture via `AudioSession` in background
- Queue drafts in `OfflineQueue` when created via Siri
- Use `UNNotificationSound.defaultCritical` for confirmation

### 4. Patient Alias Resolution

- Store aliases in Patient model: `["Grandma", "Nana"]` → Margaret
- Implement fuzzy matching in `PatientEntityQuery`
- Cache resolved aliases for quick lookup

## Error Handling

| Scenario          | Handling                                                               |
| ----------------- | ---------------------------------------------------------------------- |
| No active circle  | Return `.failure("Please open CuraKnot and join a care circle first")` |
| Patient not found | Suggest similar names: "Did you mean Margaret or Mary?"                |
| Offline           | Queue handoff draft, confirm: "I'll save this when you're back online" |
| Auth expired      | Return `.needsAuth` to trigger re-authentication                       |
| Tier gated        | Return upgrade prompt with feature preview                             |

## Security Requirements

- [ ] Never log handoff content in analytics
- [ ] Validate patient belongs to user's circles before returning data
- [ ] Audit log all medication queries (PHI access)
- [ ] Use Keychain for any cached tokens

## Testing Requirements

```swift
// Unit Tests
- PatientEntityQueryTests.swift
  - testResolveByExactName()
  - testResolveByAlias()
  - testFuzzyMatchingSuggestions()
  - testNoMatchReturnsEmpty()

- CreateHandoffIntentTests.swift
  - testCreatesDraftHandoff()
  - testQueuesOffline()
  - testTierGatingFree()
  - testTierGatingPlus()

// Integration Tests
- SiriIntegrationTests.swift
  - testEndToEndHandoffCreation()
  - testMedicationQueryReturnsCorrectData()

// UI Tests (Shortcuts app)
- Verify shortcuts appear in Shortcuts app
- Test phrase variations work
```

## Accessibility

- [ ] All intent responses support VoiceOver reading
- [ ] Confirmation dialogs have clear, spoken descriptions
- [ ] Error messages are descriptive for screen reader users

## Analytics Events

| Event                   | Properties                       | Purpose                |
| ----------------------- | -------------------------------- | ---------------------- |
| `siri_shortcut_invoked` | `intent_type`, `tier`, `success` | Usage tracking         |
| `siri_shortcut_blocked` | `intent_type`, `tier`            | Conversion opportunity |
| `siri_patient_resolved` | `used_alias: bool`               | Alias feature adoption |

## Performance Targets

- Intent resolution: < 500ms
- Patient entity query: < 200ms
- Handoff draft creation: < 1s

## Acceptance Criteria

- [ ] "Hey Siri, tell CuraKnot Mom had a good day" creates handoff draft
- [ ] "Hey Siri, what's Mom's next medication?" returns correct med info (Plus/Family)
- [ ] Free tier can scan but must manually categorize
- [ ] Confidence scores shown; low confidence prompts user review
- [ ] All scanned documents stored securely with audit trail
- [ ] Offline scanning works with queue for classification
- [ ] Med Reconciliation triggered when medication list scanned
- [ ] All tests pass with >85% classification accuracy on test set

```

---

## Prompt 2: Care Calendar Sync

```

Implement the Care Calendar Sync feature for CuraKnot.

## Specification

Read `specsV1/02-CareCalendarSync.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                                         |
| ------ | -------------------------------------------------------------------- |
| FREE   | Read-only view of binder appointments (no sync)                      |
| PLUS   | Bi-directional Apple Calendar sync, iCal feed export                 |
| FAMILY | Multi-provider sync (Apple, Google, Outlook), shared circle calendar |

**Gating Implementation:**

- FREE: Hide sync settings, show "Available with Plus" banner
- PLUS: Enable Apple Calendar, show "More calendars with Family" for Google/Outlook
- FAMILY: Full provider selection

## File Structure

```
ios/CuraKnot/
├── Features/
│   └── CalendarSync/
│       ├── Views/
│       │   ├── CalendarSyncSettingsView.swift
│       │   ├── CalendarProviderSelectionView.swift
│       │   └── ConflictResolutionView.swift
│       ├── ViewModels/
│       │   └── CalendarSyncViewModel.swift
│       ├── Services/
│       │   ├── CalendarSyncService.swift
│       │   ├── AppleCalendarProvider.swift
│       │   ├── GoogleCalendarProvider.swift      # Family
│       │   └── OutlookCalendarProvider.swift     # Family
│       └── Models/
│           └── CalendarConnection.swift

supabase/
├── migrations/
│   └── 20260205_calendar_sync.sql
├── functions/
│   ├── sync-calendar/
│   │   └── index.ts
│   └── generate-ical-feed/
│       └── index.ts
```

## Supabase Schema

```sql
-- migrations/20260205_calendar_sync.sql

-- Enable pgcrypto for encryption
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS calendar_connections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,

    provider text NOT NULL,  -- APPLE | GOOGLE | OUTLOOK
    provider_account_id text,
    
    -- Token encryption using Supabase Vault
    -- Tokens are encrypted with AES-256-GCM using a key from Supabase Vault
    -- Key rotation: Increment encryption_version when rotating keys
    access_token_encrypted text,
    refresh_token_encrypted text,
    encryption_version int NOT NULL DEFAULT 1,  -- For key rotation support
    token_expires_at timestamptz,

    calendar_id text,  -- External calendar ID
    calendar_name text,

    sync_direction text NOT NULL DEFAULT 'BIDIRECTIONAL',  -- TO_CALENDAR | FROM_CALENDAR | BIDIRECTIONAL
    last_sync_at timestamptz,
    sync_status text NOT NULL DEFAULT 'PENDING',  -- PENDING | SYNCING | SUCCESS | ERROR
    sync_error text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(circle_id, user_id, provider, calendar_id)
);

-- Token encryption/decryption functions (server-side only)
-- These use Supabase Vault for key management
CREATE OR REPLACE FUNCTION encrypt_oauth_token(token text, version int DEFAULT 1)
RETURNS text AS $$
DECLARE
    vault_key text;
BEGIN
    -- Retrieve encryption key from Supabase Vault
    SELECT decrypted_secret INTO vault_key 
    FROM vault.decrypted_secrets 
    WHERE name = 'oauth_encryption_key_v' || version;
    
    IF vault_key IS NULL THEN
        RAISE EXCEPTION 'Encryption key not found for version %', version;
    END IF;
    
    RETURN encode(
        encrypt(
            token::bytea,
            vault_key::bytea,
            'aes-gcm'
        ),
        'base64'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrypt_oauth_token(encrypted_token text, version int DEFAULT 1)
RETURNS text AS $$
DECLARE
    vault_key text;
BEGIN
    SELECT decrypted_secret INTO vault_key 
    FROM vault.decrypted_secrets 
    WHERE name = 'oauth_encryption_key_v' || version;
    
    IF vault_key IS NULL THEN
        RAISE EXCEPTION 'Encryption key not found for version %', version;
    END IF;
    
    RETURN convert_from(
        decrypt(
            decode(encrypted_token, 'base64'),
            vault_key::bytea,
            'aes-gcm'
        ),
        'UTF8'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Key rotation procedure
-- 1. Add new key to Vault: oauth_encryption_key_v{N+1}
-- 2. Run this function to re-encrypt all tokens
-- 3. After verification, remove old key
CREATE OR REPLACE FUNCTION rotate_oauth_encryption_keys(old_version int, new_version int)
RETURNS int AS $$
DECLARE
    updated_count int;
BEGIN
    UPDATE calendar_connections
    SET 
        access_token_encrypted = encrypt_oauth_token(
            decrypt_oauth_token(access_token_encrypted, old_version),
            new_version
        ),
        refresh_token_encrypted = encrypt_oauth_token(
            decrypt_oauth_token(refresh_token_encrypted, old_version),
            new_version
        ),
        encryption_version = new_version,
        updated_at = now()
    WHERE encryption_version = old_version
      AND access_token_encrypted IS NOT NULL;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TABLE IF NOT EXISTS calendar_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE CASCADE,

    event_type text NOT NULL,  -- APPOINTMENT | TASK_DUE | SHIFT | MEDICATION_REMINDER
    source_id uuid,  -- Reference to appointment, task, shift, etc.
    source_type text,

    title text NOT NULL,
    description text,
    location text,
    start_time timestamptz NOT NULL,
    end_time timestamptz,
    all_day boolean NOT NULL DEFAULT false,

    external_event_id text,  -- ID in external calendar
    external_calendar_id text,

    last_synced_at timestamptz,
    sync_hash text,  -- For conflict detection

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_calendar_events_circle ON calendar_events(circle_id, start_time);
CREATE INDEX idx_calendar_events_external ON calendar_events(external_event_id);

-- RLS Policies
ALTER TABLE calendar_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own calendar connections"
    ON calendar_connections FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Circle members can view calendar events"
    ON calendar_events FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM circle_members
        WHERE circle_members.circle_id = calendar_events.circle_id
        AND circle_members.user_id = auth.uid()
    ));
```

## Implementation Scope

### 1. iOS EventKit Integration

```swift
// AppleCalendarProvider.swift
class AppleCalendarProvider: CalendarProvider {
    private let eventStore = EKEventStore()

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func sync(events: [CalendarEvent], to calendarId: String) async throws {
        // Map CuraKnot events to EKEvents
        // Handle conflicts with merge strategy
    }

    func observeChanges() -> AsyncStream<[EKEvent]> {
        // Use EKEventStoreChangedNotification
    }
}
```

### 2. Conflict Resolution

- **CuraKnot Wins (default):** External changes overwritten
- **External Wins:** CuraKnot changes overwritten
- **Manual:** Surface conflicts for user resolution
- **Merge:** Combine non-conflicting fields

### 3. OAuth2 Flows (Family tier)

- Google: Use `ASWebAuthenticationSession` with Google Calendar API
- Microsoft: Use MSAL with Graph Calendar API
- Store tokens encrypted in Supabase

### 4. iCal Feed Generation

```typescript
// generate-ical-feed/index.ts
// Returns signed URL valid for 24h
// Includes: appointments, task due dates, shifts
```

## Error Handling

| Scenario                   | Handling                                                 |
| -------------------------- | -------------------------------------------------------- |
| Calendar permission denied | Show settings deep-link                                  |
| OAuth token expired        | Trigger re-auth flow, show non-blocking banner           |
| Sync conflict              | Queue for manual resolution or auto-resolve per strategy |
| Network error during sync  | Retry with exponential backoff, max 3 attempts           |
| External calendar deleted  | Mark connection as ERROR, prompt user                    |

## Security Requirements

- [ ] Encrypt OAuth tokens at rest (AES-256)
- [ ] Never log calendar event details
- [ ] Validate circle membership before sync operations
- [ ] iCal feed URLs include signed tokens (not guessable)
- [ ] Token refresh happens server-side only

## Testing Requirements

```swift
// Unit Tests
- CalendarSyncServiceTests.swift
  - testEventMappingToEKEvent()
  - testConflictDetection()
  - testConflictResolutionStrategies()

- AppleCalendarProviderTests.swift
  - testPermissionRequest()
  - testEventCreation()
  - testEventUpdate()
  - testEventDeletion()

// Integration Tests
- CalendarSyncIntegrationTests.swift
  - testBidirectionalSync()
  - testOfflineQueueSync()
  - testOAuthTokenRefresh()

// Edge Function Tests
- sync-calendar.test.ts
- generate-ical-feed.test.ts
```

## Accessibility

- [ ] Calendar selection uses standard picker with VoiceOver labels
- [ ] Sync status announcements for VoiceOver users
- [ ] Error states are clearly communicated

## Analytics Events

| Event                     | Properties                               | Purpose       |
| ------------------------- | ---------------------------------------- | ------------- |
| `calendar_connected`      | `provider`, `tier`                       | Adoption      |
| `calendar_sync_completed` | `provider`, `events_synced`, `conflicts` | Health        |
| `calendar_sync_failed`    | `provider`, `error_type`                 | Debugging     |
| `ical_feed_generated`     | `tier`                                   | Feature usage |

## Performance Targets

- Initial sync: < 10s for 100 events
- Incremental sync: < 2s
- iCal feed generation: < 1s

## Acceptance Criteria

- [ ] Plus users can connect Apple Calendar with bi-directional sync
- [ ] Appointments created in CuraKnot appear in connected calendars within 30s
- [ ] Events edited in Apple Calendar update in CuraKnot
- [ ] iCal feed URL works in any calendar app (Google Calendar, Outlook)
- [ ] Free tier sees appropriate upgrade prompts
- [ ] Family tier can connect Google and Outlook calendars
- [ ] Conflict resolution works per selected strategy
- [ ] OAuth tokens refresh automatically without user intervention
- [ ] Offline edits sync when connection restored
- [ ] All tests pass

```

---

## Prompt 3: Apple Watch Companion App

```

Implement the Apple Watch Companion App for CuraKnot.

## Specification

Read `specsV1/03-AppleWatchCompanion.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                              |
| ------ | ----------------------------------------- |
| FREE   | No Watch app access (show upgrade prompt) |
| PLUS   | Full Watch app with all features          |
| FAMILY | Same as Plus                              |

**Gating Implementation:**

- Check subscription via `WatchConnectivity` from iPhone
- Show `PlusRequiredView` on Watch for FREE tier
- Cache subscription status on Watch for offline access

## File Structure

```
ios/
├── CuraKnot/
│   └── Core/
│       └── WatchConnectivity/
│           └── WatchSessionManager.swift
├── CuraKnotWatch/
│   ├── CuraKnotWatchApp.swift
│   ├── Views/
│   │   ├── DashboardView.swift
│   │   ├── HandoffCaptureView.swift
│   │   ├── TaskListView.swift
│   │   ├── EmergencyCardView.swift
│   │   └── PlusRequiredView.swift
│   ├── ViewModels/
│   │   ├── WatchDashboardViewModel.swift
│   │   └── WatchHandoffViewModel.swift
│   ├── Services/
│   │   └── WatchDataManager.swift
│   └── Complications/
│       ├── NextTaskComplication.swift
│       ├── LastHandoffComplication.swift
│       └── EmergencyComplication.swift
├── CuraKnotWatchWidget/
│   └── CuraKnotWatchWidgets.swift
```

## Implementation Scope

### 1. watchOS App Target

```swift
// Add to CuraKnot.xcodeproj
// Target: CuraKnotWatch (watchOS 10.0+)
// Dependencies: WatchConnectivity, WidgetKit, AVFoundation
```

### 2. WatchConnectivity Setup

```swift
// WatchSessionManager.swift (iPhone side)
class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    func sendSubscriptionStatus(_ status: SubscriptionStatus) {
        guard WCSession.default.isReachable else {
            // Use applicationContext for background transfer
            try? WCSession.default.updateApplicationContext([
                "subscriptionStatus": status.rawValue
            ])
            return
        }
        WCSession.default.sendMessage(["subscriptionStatus": status.rawValue], replyHandler: nil)
    }

    func sendCacheData(_ data: WatchCacheData) {
        // Transfer emergency card, today's tasks, recent handoffs
    }
}
```

### 3. Core Watch Features

**Dashboard:**

- Next task due (title, time, quick complete)
- Last handoff summary (truncated)
- Quick action buttons: New Handoff, Tasks, Emergency

**Voice Capture:**

```swift
// WatchHandoffViewModel.swift
class WatchHandoffViewModel: ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0

    func startRecording() {
        // Max 60s, save to temp file
        // Show progress ring
    }

    func stopAndQueue() {
        // Save to WatchConnectivity file transfer queue
        // Show confirmation with haptic
    }
}
```

**Task List:**

- Today's tasks only (to save space)
- Swipe to complete
- Haptic confirmation

**Emergency Card:**

- Works FULLY OFFLINE
- Large, readable text
- One-tap to call emergency contact
- Show: Patient name, DOB, conditions, allergies, medications, emergency contact

### 4. Complications

```swift
// NextTaskComplication.swift
struct NextTaskComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTask", provider: NextTaskProvider()) { entry in
            NextTaskComplicationView(entry: entry)
        }
        .configurationDisplayName("Next Task")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}
```

### 5. Offline Support

```swift
// WatchDataManager.swift
class WatchDataManager {
    // Cache configuration
    private static let maxCacheSizeBytes = 1_000_000  // 1MB max for Watch storage
    private static let emergencyCardPriority = 1      // Never evict
    private static let todayTasksPriority = 2
    private static let recentHandoffsPriority = 3     // Evict first if needed
    
    // Store in UserDefaults.standard (Watch)
    private let emergencyCardKey = "cached_emergency_card"
    private let todayTasksKey = "cached_today_tasks"
    private let recentHandoffsKey = "cached_recent_handoffs"
    private let lastSyncKey = "last_sync_timestamp"
    private let cacheSizeKey = "current_cache_size_bytes"

    var dataAge: TimeInterval {
        // Show staleness indicator if > 1 hour old
        guard let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date else {
            return .infinity
        }
        return Date().timeIntervalSince(lastSync)
    }
    
    var isStale: Bool {
        return dataAge > 3600  // 1 hour
    }
    
    // MARK: - Cache Management
    
    private var currentCacheSize: Int {
        get { UserDefaults.standard.integer(forKey: cacheSizeKey) }
        set { UserDefaults.standard.set(newValue, forKey: cacheSizeKey) }
    }
    
    /// Store data with automatic eviction if needed
    func cacheData(_ data: Data, forKey key: String, priority: Int) {
        let newSize = currentCacheSize + data.count
        
        // If over limit, evict lower priority items
        if newSize > Self.maxCacheSizeBytes {
            evictLowPriorityItems(neededBytes: data.count)
        }
        
        // Store with metadata
        let wrapper = CacheWrapper(data: data, priority: priority, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(wrapper) {
            UserDefaults.standard.set(encoded, forKey: key)
            recalculateCacheSize()
        }
    }
    
    /// LRU eviction starting with lowest priority items
    private func evictLowPriorityItems(neededBytes: Int) {
        var freedBytes = 0
        let evictionOrder = [recentHandoffsKey, todayTasksKey]  // Never evict emergency card
        
        for key in evictionOrder {
            guard freedBytes < neededBytes else { break }
            
            if let data = UserDefaults.standard.data(forKey: key) {
                freedBytes += data.count
                UserDefaults.standard.removeObject(forKey: key)
                print("Watch cache: Evicted \(key) to free \(data.count) bytes")
            }
        }
        
        recalculateCacheSize()
    }
    
    private func recalculateCacheSize() {
        var total = 0
        for key in [emergencyCardKey, todayTasksKey, recentHandoffsKey] {
            if let data = UserDefaults.standard.data(forKey: key) {
                total += data.count
            }
        }
        currentCacheSize = total
    }
    
    /// Clear all cache except emergency card
    func clearNonEssentialCache() {
        UserDefaults.standard.removeObject(forKey: todayTasksKey)
        UserDefaults.standard.removeObject(forKey: recentHandoffsKey)
        recalculateCacheSize()
    }
    
    /// Clear voice recordings after successful transfer
    func clearTransferredRecordings() {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        do {
            let recordings = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "m4a" }
            
            for recording in recordings {
                try fileManager.removeItem(at: recording)
            }
        } catch {
            print("Failed to clear recordings: \(error)")
        }
    }
}

private struct CacheWrapper: Codable {
    let data: Data
    let priority: Int
    let timestamp: Date
}
```

### 6. Watch Storage Management

- **Storage Quota:** Track usage against tier limits
- **Auto-Cleanup:** Delete expired handoff recordings
- **Cache Priority:** Emergency card → Today's tasks → Recent handoffs
- **Data Retention:** Handoff data deleted after 30 days (configurable)

## Error Handling

| Scenario             | Handling                                               |
| --------------------- | ---------------------------------------------------- |
| iPhone not reachable | Use cached data, show staleness indicator              |
| Recording fails      | Show error, suggest retry, check microphone permission |
| Subscription expired | Show graceful downgrade with cached emergency card     |
| Watch storage full   | Clear old handoff recordings, keep emergency card      |
| Sync failed          | Queue for retry, show pending indicator                |

## Security Requirements

- [ ] Emergency card data encrypted on Watch
- [ ] Clear sensitive cache on subscription downgrade
- [ ] Require Watch passcode for app access
- [ ] Voice recordings deleted after successful transfer

## Testing Requirements

```swift
// Unit Tests (Watch)
- WatchDataManagerTests.swift
  - testCacheStorage()
  - testStalenessCalculation()
  - testSubscriptionStatusHandling()

- WatchHandoffViewModelTests.swift
  - testRecordingFlow()
  - testQueueForTransfer()

// Integration Tests
- WatchConnectivityTests.swift
  - testDataTransferToWatch()
  - testFileTransferFromWatch()
  - testSubscriptionStatusSync()

// UI Tests
- Test complication updates
- Test voice recording flow
- Test emergency card accessibility
```

## Accessibility

- [ ] All text supports Dynamic Type (accessibility sizes)
- [ ] VoiceOver labels on all controls
- [ ] Haptic feedback for confirmations
- [ ] Emergency card uses high-contrast colors
- [ ] Complications data readable by VoiceOver

## Analytics Events

| Event                       | Properties          | Purpose          |
| ------------------------- | ------------------- | ---------------- |
| `watch_app_opened`          | `tier`, `data_age`  | Usage            |
| `watch_handoff_recorded`    | `duration`          | Feature adoption |
| `watch_task_completed`      | -                   | Engagement       |
| `watch_emergency_viewed`    | -                   | Feature value    |
| `watch_complication_tapped` | `complication_type` | Entry points     |

## Performance Targets

- App launch: < 2s
- Complication refresh: < 500ms
- Voice recording start: < 300ms
- Emergency card display: < 100ms (must be instant)

## Acceptance Criteria

- [ ] Watch app installs alongside iPhone app for Plus/Family users
- [ ] Voice capture on Watch creates handoff draft synced to iPhone
- [ ] Tasks can be completed directly from Watch with haptic confirmation
- [ ] Complications show real-time data on Watch face
- [ ] Emergency Card accessible offline with one tap
- [ ] Free tier users see upgrade prompt when opening Watch app
- [ ] Staleness indicator shows when data is > 1 hour old
- [ ] All complications work in all supported families
- [ ] Voice recordings transfer successfully when iPhone in range
- [ ] All accessibility requirements met

```

---

## Prompt 4: Universal Document Scanner

```

Implement the Universal Document Scanner with AI Auto-Filing for CuraKnot.

## Specification

Read `specsV1/04-UniversalDocumentScanner.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                               |
| ------ | ---------------------------------------------------------- |
| FREE   | 5 scans/month, basic scan to Binder (manual categorization only) |
| PLUS   | Unlimited scans, AI classification + auto-routing suggestions    |
| FAMILY | Unlimited scans, AI classification + full data extraction + auto-population |

**Gating Implementation:**

- FREE: Allow 5 scans/month, skip AI classification step, go directly to manual save
- PLUS: Unlimited scans, show AI suggestions, user confirms destination
- FAMILY: Unlimited scans, auto-populate extracted fields, user confirms

**Usage Tracking (FREE tier):**

```swift
// Track scan usage against monthly limit
func canPerformScan() async throws -> Bool {
    let tierAccess = try await validateTierAccess(
        circleId: currentCircle.id,
        requiredTiers: [.free, .plus, .family],
        featureLimits: FeatureLimits(free: 5, plus: nil, family: nil)
    )
    
    if !tierAccess.allowed && tierAccess.reason == "LIMIT_REACHED" {
        showUpgradePrompt(
            title: "Scan Limit Reached",
            message: "You've used \(tierAccess.usage ?? 0) of 5 scans this month. Upgrade to Plus for unlimited scanning."
        )
        return false
    }
    return tierAccess.allowed
}
```

**Server-Side RLS (REQUIRED):**

```sql
-- Enforce FREE tier scan limit at database level
CREATE POLICY "document_scan_tier_limit"
    ON scanned_documents FOR INSERT
    USING (
        EXISTS (
            SELECT 1 FROM circles c
            JOIN circle_members cm ON cm.circle_id = c.id
            WHERE c.id = scanned_documents.circle_id
              AND cm.user_id = auth.uid()
              AND (
                  c.plan IN ('PLUS', 'FAMILY')
                  OR (
                      c.plan = 'FREE' AND
                      (SELECT COUNT(*) FROM scanned_documents sd
                       WHERE sd.circle_id = c.id
                         AND sd.created_at >= date_trunc('month', now())
                      ) < 5
                  )
              )
        )
    );
```

## File Structure

```
ios/CuraKnot/
├── Features/
│   └── DocumentScanner/
│       ├── Views/
│       │   ├── DocumentScannerView.swift
│       │   ├── ScanReviewView.swift
│       │   ├── ClassificationResultView.swift
│       │   └── ExtractionConfirmationView.swift
│       ├── ViewModels/
│       │   └── DocumentScannerViewModel.swift
│       ├── Services/
│       │   ├── DocumentScannerService.swift
│       │   ├── OCRService.swift
│       │   └── DocumentClassifier.swift
│       └── Models/
│           ├── ScannedDocument.swift
│           └── ClassificationResult.swift

supabase/functions/
└── classify-document/
    ├── index.ts
    └── prompts/
        └── classification-prompt.ts
```

## Supabase Edge Function

```typescript
// classify-document/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ClassifyRequest {
  ocrText: string;
  imageMetadata: {
    width: number;
    height: number;
    hasTable: boolean;
  };
  circleId: string;
  tier: "FREE" | "PLUS" | "FAMILY";
}

interface ClassifyResponse {
  documentType:
    | "DISCHARGE_SUMMARY"
    | "PRESCRIPTION"
    | "LAB_RESULT"
    | "BILL"
    | "INSURANCE_CARD"
    | "MEDICATION_LIST"
    | "OTHER";
  confidence: number;
  suggestedDestination: string;
  extractedEntities?: {
    medications?: Array<{ name: string; dose: string; frequency: string }>;
    providers?: Array<{ name: string; role: string; phone?: string }>;
    amounts?: Array<{ value: number; description: string }>;
    dates?: Array<{ date: string; description: string }>;
  };
}

serve(async (req) => {
  // Validate auth
  // Call LLM for classification
  // If FAMILY tier, also extract entities
  // Return classification with confidence
});
```

## Implementation Scope

### 1. iOS VisionKit Integration

```swift
// DocumentScannerService.swift
class DocumentScannerService {
    func presentScanner(from viewController: UIViewController) -> AnyPublisher<[UIImage], Error> {
        let scannerVC = VNDocumentCameraViewController()
        // Configure and present
    }

    func performOCR(on image: UIImage) async throws -> String {
        let requestHandler = VNImageRequestHandler(cgImage: image.cgImage!)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try requestHandler.perform([request])
        // Return concatenated text
    }
}
```

### 2. Classification Flow

```swift
// DocumentScannerViewModel.swift
func classifyDocument() async {
    guard tier != .free else {
        // Skip to manual categorization
        state = .manualCategorization
        return
    }

    state = .classifying

    let result = try await classificationService.classify(
        ocrText: scannedText,
        tier: tier
    )

    if result.confidence > 0.8 {
        state = .showingSuggestion(result)
    } else {
        state = .manualCategorization(suggestion: result)
    }
}
```

### 3. Auto-Routing Logic

| Document Type     | Destination                   | Additional Action                       |
| ----------------- | ----------------------------- | --------------------------------------- |
| DISCHARGE_SUMMARY | Create handoff draft          | Flag medications for Med Reconciliation |
| PRESCRIPTION      | Binder > Medications          | Extract med details (Family)            |
| LAB_RESULT        | Create handoff                | Highlight abnormal values               |
| BILL              | Binder > Documents or Billing | Extract amount, due date (Family)       |
| INSURANCE_CARD    | Binder > Insurance            | Extract policy number (Family)          |
| MEDICATION_LIST   | Trigger Med Reconciliation    | Compare with current meds               |

### 4. Data Extraction (Family tier)

```swift
// ExtractionConfirmationView.swift
struct ExtractionConfirmationView: View {
    let extractedData: ExtractedEntities
    @Binding var confirmedMedications: [Medication]

    var body: some View {
        List {
            Section("Extracted Medications") {
                ForEach(extractedData.medications) { med in
                    MedicationExtractionRow(
                        extracted: med,
                        isConfirmed: confirmedMedications.contains(med)
                    )
                }
            }
            // Similar for providers, amounts, dates
        }
    }
}
```

## Error Handling

| Scenario                        | Handling                                                |
| ------------------------------- | ------------------------------------------------------ |
| Camera permission denied        | Show settings link with explanation                     |
| OCR fails                       | Allow manual text entry, suggest retake                 |
| Classification confidence < 50% | Default to manual, show "We're not sure"                |
| LLM API error                   | Fall back to keyword-based classification               |
| Extraction confidence low       | Show extracted data as suggestions, not auto-fill       |
| Network offline                 | Queue for classification when online, allow manual save |

## Security Requirements

- [ ] Scanned images stored encrypted in Supabase Storage
- [ ] OCR text never logged in full (truncate in logs)
- [ ] LLM prompts don't include PHI in system prompt
- [ ] Extracted medication names validated against known database
- [ ] Audit log for document scans with classification results

## Testing Requirements

```swift
// Unit Tests
- OCRServiceTests.swift
  - testTextRecognitionAccuracy()
  - testHandlesBlurryImage()
  - testHandlesRotatedDocument()

- DocumentClassifierTests.swift
  - testPrescriptionClassification()
  - testDischargeClassification()
  - testLowConfidenceHandling()

// Integration Tests
- DocumentScannerIntegrationTests.swift
  - testEndToEndScanToMedication()
  - testEndToEndScanToBinder()
  - testOfflineQueueing()

// Edge Function Tests
- classify-document.test.ts
  - testClassificationAccuracy()
  - testExtractionAccuracy()
  - testTierGating()
```

## Accessibility

- [ ] Scanner UI works with VoiceOver (describe what camera sees)
- [ ] Extracted data review supports Dynamic Type
- [ ] Confirmation buttons have clear labels
- [ ] Error states clearly announced

## Analytics Events

| Event                     | Properties                       | Purpose       |
| ------------------------- | -------------------------------- | ------------- |
| `document_scanned`        | `tier`                           | Usage         |
| `document_classified`     | `type`, `confidence`, `tier`     | AI accuracy   |
| `classification_accepted` | `type`, `was_suggested`          | UX quality    |
| `classification_changed`  | `from_type`, `to_type`           | Training data |
| `extraction_confirmed`    | `entity_types`, `entities_count` | Feature value |

## Performance Targets

- OCR: < 2s per page
- Classification API: < 3s
- Full extraction: < 5s
- Scan to save (manual): < 10s total

## Acceptance Criteria

- [ ] Scanning a prescription auto-detects type with >80% accuracy
- [ ] Discharge papers create handoff draft with key info extracted
- [ ] Bills route correctly with amount extracted (Family)
- [ ] Free tier can scan but must manually categorize
- [ ] Confidence scores shown; low confidence prompts user review
- [ ] All scanned documents stored securely with audit trail
- [ ] Offline scanning works with queue for classification
- [ ] Med Reconciliation triggered when medication list scanned
- [ ] All tests pass with >85% classification accuracy on test set

```

---

## Prompt 5: AI Care Coach

```

Implement the AI Care Coach conversational guidance feature for CuraKnot.

## Specification

Read `specsV1/05-AICareCoach.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                            |
| ------ | --------------------------------------------------------- |
| FREE   | No access (show feature preview with upgrade CTA)        |
| PLUS   | Unlimited messages, basic context                        |
| FAMILY | Unlimited messages, full context, proactive suggestions |

**Gating Implementation:**

- Track monthly usage in `coach_usage` table
- Reset counts on billing cycle (1st of month)
- Show remaining messages in UI: "47 of 50 messages remaining"
- At limit: Show upgrade prompt with feature preview

## File Structure

```
ios/CuraKnot/
├── Features/
│   └── CareCoach/
│       ├── Views/
│       │   ├── CoachChatView.swift
│       │   ├── CoachMessageBubble.swift
│       │   ├── CoachContextChip.swift
│       │   ├── CoachQuickActions.swift
│       │   └── CoachUpgradePrompt.swift
│       ├── ViewModels/
│       │   └── CoachChatViewModel.swift
│       ├── Services/
│       │   └── CoachService.swift
│       └── Models/
│           ├── CoachConversation.swift
│           └── CoachMessage.swift

supabase/
├── migrations/
│   └── 20260205_care_coach.sql
├── functions/
│   ├── coach-chat/
│   │   ├── index.ts
│   │   ├── context-builder.ts
│   │   ├── guardrails.ts
│   │   └── prompts/
│   │       └── system-prompt.ts
│   └── analyze-proactive-suggestions/
│       └── index.ts
```

## Supabase Schema

```sql
-- migrations/20260205_care_coach.sql

-- Enable pgcrypto for encryption
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS coach_conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,

    title text,  -- Auto-generated from first message

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS coach_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES coach_conversations(id) ON DELETE CASCADE,

    role text NOT NULL,  -- USER | ASSISTANT | SYSTEM
    content text NOT NULL,

    -- Context used for this message
    context_handoff_ids uuid[],
    context_binder_ids uuid[],

    -- Metadata
    tokens_used int,
    model_version text,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS coach_usage (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    month date NOT NULL,  -- First of month

    messages_used int NOT NULL DEFAULT 0,
    messages_limit int NOT NULL DEFAULT 50,

    UNIQUE(user_id, month)
);

CREATE INDEX idx_coach_conversations_user ON coach_conversations(user_id, updated_at DESC);
CREATE INDEX idx_coach_messages_conversation ON coach_messages(conversation_id, created_at);
CREATE INDEX idx_coach_usage_lookup ON coach_usage(user_id, month);

-- RLS
ALTER TABLE coach_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users access own conversations"
    ON coach_conversations FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Users access own messages"
    ON coach_messages FOR ALL USING (
        conversation_id IN (SELECT id FROM coach_conversations WHERE user_id = auth.uid())
    );

CREATE POLICY "Users access own usage"
    ON coach_usage FOR ALL USING (user_id = auth.uid());
```

## Edge Function Implementation

```typescript
// coach-chat/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

interface ChatRequest {
  conversationId?: string;
  message: string;
  patientId?: string;
}

serve(async (req) => {
  const supabase = createClient(/* ... */);
  const {
    data: { user },
  } = await supabase.auth.getUser(/* ... */);

  // 1. Check usage limits
  const usage = await getOrCreateUsage(user.id);
  if (usage.messages_used >= usage.messages_limit) {
    return new Response(
      JSON.stringify({
        error: "LIMIT_REACHED",
        used: usage.messages_used,
        limit: usage.messages_limit,
      }),
      { status: 429 },
    );
  }

  // 2. Build context
  const context = await buildContext(user.id, patientId);

  // 3. Apply guardrails
  const guardrailResult = await checkGuardrails(message);
  if (guardrailResult.blocked) {
    return emergencyResponse(guardrailResult.reason);
  }

  // 4. Call LLM
  const response = await callLLM(systemPrompt, context, message);

  // 5. Increment usage
  await incrementUsage(user.id);

  // 6. Save message
  await saveMessage(conversationId, message, response);

  return new Response(JSON.stringify({ response }));
});
```

```typescript
// coach-chat/context-builder.ts
import { sanitizeContextForLLM, MAX_CONTEXT_TOKENS, MAX_HANDOFFS_IN_CONTEXT } from './context-sanitizer';

export async function buildContext(
  userId: string, 
  patientId: string,
  supabase: SupabaseClient
): Promise<SanitizedContext> {
  // 1. Fetch recent handoffs (limited)
  const { data: handoffs } = await supabase
    .from('handoffs')
    .select('id, summary, symptoms, created_at')  // Only needed fields, not full content
    .eq('patient_id', patientId)
    .order('created_at', { ascending: false })
    .limit(MAX_HANDOFFS_IN_CONTEXT);
  
  // 2. Fetch patient info (no identifiers sent to LLM)
  const { data: patient } = await supabase
    .from('patients')
    .select('id, name, conditions, allergies')
    .eq('id', patientId)
    .single();
  
  // 3. Fetch current medications (drug class only, not specific dosages)
  const { data: medications } = await supabase
    .from('binder_items')
    .select('name, category')
    .eq('patient_id', patientId)
    .eq('item_type', 'MED')
    .eq('is_active', true)
    .limit(MAX_MEDICATIONS_IN_CONTEXT);
  
  // 4. CRITICAL: Sanitize before sending to LLM
  return sanitizeContextForLLM(handoffs || [], patient, medications || []);
}
```

```typescript
// coach-chat/prompts/system-prompt.ts
export const SYSTEM_PROMPT = `You are CuraKnot's Care Coach, a supportive AI assistant for family caregivers.

IMPORTANT GUIDELINES:
1. You are NOT a doctor. Never diagnose conditions or prescribe treatments.
2. Always recommend consulting healthcare providers for medical decisions.
3. If someone describes an emergency, immediately direct them to call 911.
4. Be warm, empathetic, and supportive - caregiving is emotionally challenging.
5. Provide practical, actionable suggestions when possible.
6. Reference the patient's specific context (handoffs, medications) when relevant.
7. Acknowledge the caregiver's efforts and validate their feelings.

You have access to:
- Recent handoffs about the patient
- Current medications in the care binder
- Upcoming appointments
- Task history

When referencing this context, mention it naturally: "I see from the handoff on Feb 3rd that..."

NEVER:
- Recommend specific medications or dosages
- Suggest stopping prescribed treatments
- Make predictions about prognosis
- Provide mental health crisis counseling (direct to 988)`;
```

## iOS Implementation

```swift
// CoachChatViewModel.swift
@MainActor
class CoachChatViewModel: ObservableObject {
    @Published var messages: [CoachMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var usageInfo: UsageInfo?
    @Published var showUpgradePrompt = false

    private let coachService: CoachService
    private var streamTask: Task<Void, Never>?

    func sendMessage() async {
        guard !inputText.isEmpty else { return }

        let userMessage = inputText
        inputText = ""

        // Add user message immediately
        messages.append(CoachMessage(role: .user, content: userMessage))

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await coachService.chat(
                message: userMessage,
                conversationId: currentConversationId
            )

            if response.limitReached {
                showUpgradePrompt = true
                return
            }

            messages.append(CoachMessage(
                role: .assistant,
                content: response.content,
                contextReferences: response.contextReferences
            ))

            usageInfo = response.usageInfo
        } catch {
            messages.append(CoachMessage(
                role: .assistant,
                content: "I'm sorry, I encountered an error. Please try again.",
                isError: true
            ))
        }
    }
}
```

## Error Handling

| Scenario              | Handling                                             |
| --------------------- | ---------------------------------------------------- |
| Rate limit (50/month) | Show upgrade prompt, disable input                   |
| LLM API timeout       | "I'm thinking..." → retry once → show retry button   |
| Network offline       | Disable coach, show "Coach requires internet"        |
| Context fetch fails   | Proceed without context, note limitation in response |
| Emergency detected    | Immediate 911 redirect, log for safety review        |
| Inappropriate content | Polite deflection, don't engage                      |

## Security Requirements

- [ ] Never log full conversation content
- [ ] PHI in context is summarized, not sent raw to LLM
- [ ] Emergency redirects logged for safety audits
- [ ] Rate limiting prevents abuse
- [ ] Conversations are user-private (not shared in circle)
- [ ] Context references don't expose data user can't access

## Testing Requirements

```swift
// Unit Tests
- CoachChatViewModelTests.swift
  - testSendMessageSuccess()
  - testRateLimitHandling()
  - testEmergencyDetection()

// Integration Tests
- CoachServiceIntegrationTests.swift
  - testFullConversationFlow()
  - testContextIncluded()
  - testUsageTracking()

// Edge Function Tests
- coach-chat.test.ts
  - testGuardrails()
  - testContextBuilding()
  - testUsageLimits()
  - testEmergencyResponse()

// Safety Tests
- GuardrailTests.ts
  - testAllEmergencyPatternsDetected()
  - testDiagnosisRequestsDisclaimed()
  - testNoMedicalAdviceGiven()
```

## Accessibility

- [ ] Chat supports Dynamic Type
- [ ] VoiceOver announces new messages
- [ ] Loading state announced
- [ ] Quick action buttons have labels
- [ ] Context chips are VoiceOver-friendly

## Analytics Events

| Event                        | Properties             | Purpose    |
| ------------------------- | ---------------------- | ---------- |
| `coach_conversation_started` | `tier`, `patient_id`   | Adoption   |
| `coach_message_sent`         | `tier`, `context_size` | Usage      |
| `coach_limit_reached`        | `tier`                 | Conversion |
| `coach_emergency_detected`   | `pattern`              | Safety     |
| `coach_upgrade_clicked`      | `from_limit`           | Conversion |

## Performance Targets

- First response: < 5s
- Streaming first token: < 2s
- Context fetch: < 1s
- Full conversation load: < 500ms

## Acceptance Criteria

- [ ] Plus users can chat with Coach up to 50 messages/month
- [ ] Coach references recent handoffs and binder data naturally
- [ ] Medical advice requests receive appropriate disclaimers
- [ ] Emergency keywords trigger immediate 911 redirect
- [ ] Family tier receives unlimited messages
- [ ] Usage counter accurate and resets monthly
- [ ] Proactive suggestions surface for Family tier
- [ ] Conversation history persists across sessions
- [ ] Streaming responses work for smooth UX
- [ ] All guardrail tests pass

```

---

## Prompt 6: Smart Appointment Questions

```

Implement the Smart Appointment Question Generator for CuraKnot.

## Specification

Read `specsV1/06-SmartAppointmentQuestions.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                     |
| ------ | ------------------------------------------------ |
| FREE   | No access (show preview with 2 sample questions) |
| PLUS   | Unlimited entries, photo attachments             |
| FAMILY | Full features + Memory Book PDF export           |

## Emotional Design Principles

This feature is about emotional resilience, not data capture:

1. **No Gamification:** No streaks, points, or badges
2. **No Guilt:** Prompts are always gentle and optional
3. **Private by Default:** User chooses to share, not the other way
4. **Celebrate Joy:** Focus on positive moments, not obligations

## Implementation follows the established pattern.

## Acceptance Criteria

- [ ] Good Moment entries capture quickly (< 30 seconds)
- [ ] Milestones can have titles and types
- [ ] Privacy controls work (private entries hidden from others)
- [ ] Photos attach to entries (Plus+)
- [ ] Memory Book PDF generates correctly (Family)
- [ ] Free tier shows upgrade prompt at limit
- [ ] Prompts are dismissible and disableable
- [ ] No gamification elements

```

---

## Prompt 7: Symptom Pattern Surfacing

```

Implement the Symptom Pattern Surfacing feature for CuraKnot.

## Specification

Read `specsV1/07-SymptomPatternSurfacing.md` for complete requirements.

## Premium Tier Gating

| Tier   | Access Level                        |
| ------ | ----------------------------------- |
| FREE   | No access (Insights section hidden) |
| PLUS   | Full pattern detection and alerts   |
| FAMILY | Same as Plus                        |

## Key Implementation Notes

- Daily cron job analyzes handoffs for each patient
- Pattern types: FREQUENCY, TREND, CORRELATION, NEW, ABSENCE
- **CRITICAL: All insights framed as observations, NOT medical assessments**
- Always include disclaimer: "This is an observation from your handoffs, not a medical assessment."
- Link patterns to Smart Appointment Questions feature

## Acceptance Criteria

- [ ] Daily analysis runs and generates relevant insights
- [ ] Insights show specific handoff sources
- [ ] Non-clinical language used throughout
- [ ] User feedback captured and stored
- [ ] Patterns link to Smart Appointment Questions
- [ ] Free tier does not see Insights section
- [ ] Dismissed insights don't reappear

```

---

## Prompt 8: Caregiver Wellness Check-ins

```

Implement the Caregiver Wellness & Burnout Detection feature for CuraKnot.

## Specification

Read `specsV1/08-CaregiverWellnessCheckins.md` for complete requirements.

## Premium Tier Gating

| Tier   | Access Level                        |
| ------ | ----------------------------------- |
| FREE   | No access (show preview in profile) |
| PLUS   | Full wellness tracking and alerts   |
| FAMILY | Same as Plus                        |

## Privacy Clarification

**Wellness data is USER-PRIVATE (not shared with circle).**
- Only the user can see their own wellness scores and check-in history
- Burnout alerts suggest other circle members by name (from membership data, not wellness scores)
- Example: "Consider asking Sarah to help" - Sarah's name comes from circle membership, NOT from comparing wellness scores
- Notes field is encrypted at rest

## Key Implementation Notes

- Weekly check-in: stress (1-5), sleep (1-5), capacity (1-5)
- Burnout signals detected from check-ins + handoff patterns (frequency, late-night entries)
- Notifications are gentle, never guilt-inducing

## Acceptance Criteria

- [ ] Weekly check-in flow takes < 30 seconds
- [ ] Wellness score calculated from check-ins + handoff patterns
- [ ] Burnout alerts triggered by sustained negative signals
- [ ] Suggestions personalized with circle member names
- [ ] User can disable check-in reminders
- [ ] Wellness data NOT visible to other circle members

```

---

## Prompt 9: Hospital Discharge Wizard

```

Implement the Hospital Discharge Planning Wizard for CuraKnot.

## Specification

Read `specsV1/09-HospitalDischargeWizard.md` for complete requirements.

## Premium Tier Gating

| Tier   | Access Level                                   |
| ------ | ---------------------------------------------- |
| FREE   | No access (show preview with upgrade CTA)      |
| PLUS   | Full wizard with templates and task generation |
| FAMILY | Same as Plus                                   |

## Discharge Templates (Complete)

```sql
INSERT INTO discharge_templates (template_name, discharge_type, items, is_system) VALUES
('General Discharge', 'OTHER', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1},
  {"category": "BEFORE_LEAVING", "item_text": "Review medication list with nurse", "sort_order": 2},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule follow-up appointments", "sort_order": 3},
  {"category": "BEFORE_LEAVING", "item_text": "Ask about warning signs to watch for", "sort_order": 4},
  {"category": "MEDICATIONS", "item_text": "Fill new prescriptions", "sort_order": 1},
  {"category": "MEDICATIONS", "item_text": "Set up medication organizer", "sort_order": 2},
  {"category": "MEDICATIONS", "item_text": "Reconcile with existing medications", "sort_order": 3},
  {"category": "HOME_PREP", "item_text": "Prepare bedroom for easy access", "sort_order": 1},
  {"category": "HOME_PREP", "item_text": "Install grab bars in bathroom", "sort_order": 2},
  {"category": "FIRST_WEEK", "item_text": "Watch for warning signs listed in discharge papers", "sort_order": 1},
  {"category": "FIRST_WEEK", "item_text": "Keep discharge papers accessible", "sort_order": 2}
]'::jsonb, true),

('Post-Surgery', 'SURGERY', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1},
  {"category": "BEFORE_LEAVING", "item_text": "Review wound care instructions", "sort_order": 2},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule follow-up with surgeon", "sort_order": 3},
  {"category": "BEFORE_LEAVING", "item_text": "Get pain management plan", "sort_order": 4},
  {"category": "MEDICATIONS", "item_text": "Fill pain medication prescription", "sort_order": 1},
  {"category": "MEDICATIONS", "item_text": "Fill antibiotics if prescribed", "sort_order": 2},
  {"category": "MEDICATIONS", "item_text": "Get stool softeners if needed", "sort_order": 3},
  {"category": "EQUIPMENT", "item_text": "Obtain wound care supplies", "sort_order": 1},
  {"category": "EQUIPMENT", "item_text": "Get mobility aids (walker, crutches)", "sort_order": 2},
  {"category": "HOME_PREP", "item_text": "Set up recovery area (bed, supplies within reach)", "sort_order": 1},
  {"category": "HOME_PREP", "item_text": "Install grab bars in bathroom", "sort_order": 2},
  {"category": "HOME_PREP", "item_text": "Move bedroom to first floor if needed", "sort_order": 3},
  {"category": "HOME_PREP", "item_text": "Remove area rugs and tripping hazards", "sort_order": 4},
  {"category": "FIRST_WEEK", "item_text": "Begin home therapy exercises", "sort_order": 1},
  {"category": "FIRST_WEEK", "item_text": "Monitor blood pressure twice daily", "sort_order": 2},
  {"category": "FIRST_WEEK", "item_text": "Weigh daily (watch for fluid retention)", "sort_order": 3},
  {"category": "FIRST_WEEK", "item_text": "Report any chest pain immediately", "sort_order": 4}
]'::jsonb, true),

('Stroke Recovery', 'STROKE', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule rehabilitation therapy (PT/OT/Speech)", "sort_order": 2},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule neurology follow-up", "sort_order": 3},
  {"category": "BEFORE_LEAVING", "item_text": "Review stroke warning signs (FAST)", "sort_order": 4},
  {"category": "MEDICATIONS", "item_text": "Fill blood thinner prescription", "sort_order": 1},
  {"category": "MEDICATIONS", "item_text": "Fill blood pressure medications", "sort_order": 2},
  {"category": "MEDICATIONS", "item_text": "Set up pill organizer with clear labeling", "sort_order": 3},
  {"category": "EQUIPMENT", "item_text": "Get mobility aids (wheelchair, walker)", "sort_order": 1},
  {"category": "EQUIPMENT", "item_text": "Get adaptive equipment (utensils, dressing aids)", "sort_order": 2},
  {"category": "HOME_PREP", "item_text": "Install grab bars in bathroom", "sort_order": 1},
  {"category": "HOME_PREP", "item_text": "Move bedroom to first floor if needed", "sort_order": 2},
  {"category": "HOME_PREP", "item_text": "Remove area rugs and tripping hazards", "sort_order": 3},
  {"category": "FIRST_WEEK", "item_text": "Begin home therapy exercises", "sort_order": 1},
  {"category": "FIRST_WEEK", "item_text": "Monitor blood pressure twice daily", "sort_order": 2},
  {"category": "FIRST_WEEK", "item_text": "Weigh daily (watch for fluid retention)", "sort_order": 3},
  {"category": "FIRST_WEEK", "item_text": "Report any chest pain immediately", "sort_order": 4}
]'::jsonb, true),

('Cardiac', 'CARDIAC', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule cardiology follow-up", "sort_order": 2},
  {"category": "BEFORE_LEAVING", "item_text": "Enroll in cardiac rehabilitation program", "sort_order": 3},
  {"category": "BEFORE_LEAVING", "item_text": "Review heart attack warning signs", "sort_order": 4},
  {"category": "MEDICATIONS", "item_text": "Fill heart medications (beta blockers, ACE inhibitors)", "sort_order": 1},
  {"category": "MEDICATIONS", "item_text": "Fill blood thinners if prescribed", "sort_order": 2},
  {"category": "MEDICATIONS", "item_text": "Get nitroglycerin if prescribed", "sort_order": 3},
  {"category": "EQUIPMENT", "item_text": "Get blood pressure monitor", "sort_order": 1},
  {"category": "EQUIPMENT", "item_text": "Get pulse oximeter if recommended", "sort_order": 2},
  {"category": "HOME_PREP", "item_text": "Prepare heart-healthy meals", "sort_order": 1},
  {"category": "HOME_PREP", "item_text": "Set up medication reminder system", "sort_order": 2},
  {"category": "FIRST_WEEK", "item_text": "Monitor blood pressure twice daily", "sort_order": 1},
  {"category": "FIRST_WEEK", "item_text": "Weigh daily (watch for fluid retention)", "sort_order": 2},
  {"category": "FIRST_WEEK", "item_text": "Follow activity restrictions", "sort_order": 3},
  {"category": "FIRST_WEEK", "item_text": "Report any chest pain immediately", "sort_order": 4}
]'::jsonb, true);
```

## Acceptance Criteria

- [ ] Wizard guides user through discharge planning in < 5 minutes
- [ ] All 4 templates have complete checklist items
- [ ] Checklist items automatically create assignable Tasks
- [ ] Document scanner extracts data to pre-fill checklist
- [ ] Progress visible on patient dashboard
- [ ] Plan can be resumed if interrupted

```

---

## Prompt 10: Facility Communication Log

```

Implement the Facility Communication Log for CuraKnot.

## Specification

Read `specsV1/10-FacilityCommunicationLog.md` for complete requirements.

## Premium Tier Gating

| Tier   | Access Level                                             |
| ------ | -------------------------------------------------------- |
| FREE   | No access (feature hidden)                               |
| PLUS   | Basic logging (call, message, notes), no AI suggestions |
| FAMILY | Full features (call, message, notes, AI suggestions)     |

## Acceptance Criteria

- [ ] One-tap logging after facility calls
- [ ] Communication history searchable by facility, date, contact
- [ ] Follow-up reminders work correctly
- [ ] AI suggests tasks from communication summaries (Plus+)
- [ ] Quick actions (call, email, directions) work
- [ ] Free tier sees feature locked state

```

---

## Prompt 11: Care Network Directory

```

Implement the Care Network Directory & Instant Sharing for CuraKnot.

## Specification

Read `specsV1/11-CareNetworkDirectory.md` for complete requirements.

## Premium Tier Gating

| Tier   | Access Level                               |
| ------ | ------------------------------------------ |
| FREE   | View-only directory from Binder data       |
| PLUS   | PDF export, secure link sharing            |
| FAMILY | Full features + provider notes and ratings |

## Acceptance Criteria

- [ ] Directory aggregates all providers from Binder
- [ ] One-tap sharing generates secure link
- [ ] PDF export is professionally formatted
- [ ] Quick actions (call, email, directions) work
- [ ] Family tier can add notes and ratings
- [ ] Free tier can view but not export/share

```

---

## Prompt 12: Condition Photo Tracking

```

Implement the Secure Condition Photo Tracking feature for CuraKnot.

## Specification

Read `specsV1/12-ConditionPhotoTracking.md` for complete requirements.

## Premium Tier Gating

| Tier   | Access Level                                               |
| ------ | ---------------------------------------------------------- |
| FREE   | No access (feature hidden)                                 |
| PLUS   | 5 active conditions, basic timeline, no comparison/sharing |
| FAMILY | Unlimited conditions, comparison view, clinician sharing   |

## Critical Security Requirements (MANDATORY)

1. **Biometric Gate:** ALWAYS require Face ID/Touch ID to view any photo (no opt-out)
2. **Encrypted Storage:** All photos encrypted at rest
3. **No Photo Library:** Photos excluded from device photo library
4. **Audit Logging:** Every photo view logged with timestamp and user
5. **Blurred Thumbnails:** Timeline shows blurred previews by default
6. **Short TTL Shares:** Clinician share links max 7 days, single-use option

## Acceptance Criteria

- [ ] Photos ALWAYS require biometric to view (mandatory)
- [ ] Timeline shows progression with blurred thumbnails
- [ ] Comparison view shows side-by-side (Family)
- [ ] Clinician share links work without login
- [ ] All photo access is logged
- [ ] Plus tier limited to 5 active conditions
- [ ] Photos not accessible from device photo library

```

---

## Prompt 13: Gratitude & Milestone Journal

```

Implement the Gratitude & Milestone Journal for CuraKnot.

## Specification

Read `specsV1/13-GratitudeJournal.md` for complete requirements.

## Premium Tier Gating

| Tier   | Access Level                           |
| ------ | -------------------------------------- |
| FREE   | 5 entries/month, no photos             |
| PLUS   | Unlimited entries, photo attachments   |
| FAMILY | Full features + Memory Book PDF export |

## Emotional Design Principles (REQUIRED)

1. **No Gamification:** No streaks, points, or badges - caregiving is not a game
2. **No Guilt:** Prompts are always gentle and optional - "Would you like to share a moment?"
3. **Private by Default:** User explicitly chooses to share, entries are private unless shared
4. **Celebrate Joy:** Focus on positive moments and small wins, not obligations

## Acceptance Criteria

- [ ] Good Moment entries capture quickly (< 30 seconds)
- [ ] Milestones can have titles and types
- [ ] Privacy controls work (private entries hidden from others)
- [ ] Photos attach to entries (Plus+)
- [ ] Memory Book PDF generates correctly (Family)
- [ ] Free tier shows upgrade prompt at limit
- [ ] NO gamification elements (no streaks, badges, points)

```

---

## Prompt 14: Family Video Message Board

```

Implement the Family Video Message Board for CuraKnot.

## Specification

Read `specsV1/14-FamilyVideoBoard.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                           |
| ------ | ------------------------------------------------------ |
| FREE   | No access (feature hidden)                               |
| PLUS   | 30-second videos, 30-day retention                     |
| FAMILY | 60-second videos, 90-day retention, compilation export |

## Technical Considerations

1. **Video Compression:** 
   - **Resolution:** Max 720p (1280x720), downscale higher resolution inputs
   - **Codec:** HEVC (H.265) preferred, H.264 fallback for older devices
   - **Bitrate:** Target 2 Mbps for 720p, 1.2 Mbps for 480p
   - **Quality Preset:** `AVAssetExportPresetMediumQuality` for balance
   - **File Size Limits:** Plus: ~7.5 MB (30s), Family: ~15 MB (60s)
   - **Audio:** AAC 128kbps mono (adequate for voice)
   
2. **Thumbnail Generation:** Server-side via Edge Function
   - Extract frame at 1 second mark
   - Generate 320x180 JPEG thumbnails
   - Store in separate Supabase Storage bucket for fast loading
   
3. **Storage Quotas:** Track against tier storage limits
   - Plus: 500 MB total video storage per circle
   - Family: 2 GB total video storage per circle
   - Show usage in settings: "Using 250 MB of 500 MB"
   
4. **Retention Policies:** Auto-delete after retention period
   - Plus: 30 days
   - Family: 90 days
   - Send warning notification 7 days before expiration
   - Allow "Keep Forever" for Family tier (counts against quota)
   
5. **Patient-Friendly Playback:** Large UI, simple controls, auto-play
   - Minimum touch targets: 60x60 pt (larger than standard 44pt)
   - Auto-play with muted audio (tap to unmute)
   - Loop option for short messages
   - High contrast play/pause buttons

6. **Upload Handling:**
   - Background upload with progress indicator
   - Resume interrupted uploads
   - Compress before upload (not server-side)
   - Max upload time: 60s timeout with retry

```swift
// VideoCompressionService.swift
class VideoCompressionService {
    func compressForUpload(
        inputURL: URL,
        maxDuration: TimeInterval,
        tier: SubscriptionTier
    ) async throws -> URL {
        let asset = AVAsset(url: inputURL)
        
        // Determine export preset based on device capability
        let preset: String
        if AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality) {
            preset = AVAssetExportPresetHEVC1920x1080  // Will downscale to 720p
        } else {
            preset = AVAssetExportPreset1280x720  // H.264 fallback
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: preset
        ) else {
            throw VideoError.compressionFailed
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Limit duration based on tier
        let duration = min(asset.duration.seconds, maxDuration)
        exportSession.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        
        // Target bitrate via video composition (approximate)
        // 2 Mbps = ~250 KB/s = ~7.5 MB for 30s
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw VideoError.compressionFailed
        }
        
        return outputURL
    }
}
```

## Implementation follows the established pattern with video-specific handling.

## Acceptance Criteria

- [ ] Video recording works with duration limits by tier
- [ ] Patient-friendly playback UI with large touch targets
- [ ] Reactions ("Send Love") and view tracking work
- [ ] Expired videos auto-cleanup runs
- [ ] Family tier can create compilations
- [ ] Free tier sees feature locked state
- [ ] Storage usage tracked against quotas
- [ ] Videos compressed to reasonable file sizes

```

---

## Prompt 15: Family Meeting Mode

```

Implement the Family Meeting Mode for CuraKnot.

## Specification

Read `specsV1/15-FamilyMeetingMode.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                             |
| ------ | -------------------------------------------------------- |
| FREE   | No access (feature hidden)                               |
| PLUS   | Basic meetings (agenda, decisions, manual task creation) |
| FAMILY | Full features (recurring, auto-tasks, calendar invites)  |

## Key Features

1. **Agenda Builder:** Add/reorder items, suggested topics from app
2. **During Meeting:** Navigate items, capture notes/decisions, add action items
3. **Action Items → Tasks:** One-tap task creation from action items
4. **Meeting Summary:** Auto-generate handoff with decisions and action items
5. **Calendar Integration:** Send invites, recurring meetings

## Implementation follows the established pattern.

## Acceptance Criteria

- [ ] Meeting flow guides user through agenda → discussion → summary
- [ ] Decisions captured and documented
- [ ] Action items become assignable Tasks (Family)
- [ ] Calendar invites sent (Family)
- [ ] Meeting summary published as Handoff
- [ ] Plus tier has basic functionality; Family has full features
- [ ] Suggested topics pulled from overdue tasks, recent changes

```

---

## Prompt 16: Medical Transportation Coordinator

```

Implement the Medical Transportation Coordinator for CuraKnot.

## Specification

Read `specsV1/16-MedicalTransportation.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                         |
| ------ | ---------------------------------------------------- |
| FREE   | No access (feature hidden)                             |
| PLUS   | Directory + availability requests, reviews           |
| FAMILY | Full features + booking integration, respite tracking, reminders |

## Key Features

1. **Ride Scheduling:** Link to appointments, addresses, special needs
2. **Driver Coordination:** Volunteer, request, track fairness
3. **Reminders:** Patient + driver reminders, unconfirmed alerts
4. **Transport Directory (Family):** Local services, capabilities
5. **Analytics (Family):** Rides per member, distribution fairness

## Implementation follows the established pattern.

## Acceptance Criteria

- [ ] Rides can be scheduled and linked to appointments
- [ ] Circle members can volunteer or be requested to drive
- [ ] Reminders sent to patients and drivers
- [ ] Unconfirmed ride alerts work (24h before)
- [ ] Transport directory shows local options (Family)
- [ ] Ride distribution analytics available (Family)
- [ ] Special needs tracked (wheelchair, oxygen, etc.)

```

---

## Prompt 17: Respite Care Finder

```

Implement the Respite Care Finder & Booking for CuraKnot.

## Specification

Read `specsV1/17-RespiteCareFinder.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                                     |
| ------ | ---------------------------------------------------------------- |
| FREE   | View directory only (no requests)                                |
| PLUS   | Directory + availability requests, reviews                       |
| FAMILY | Full features + booking integration, respite tracking, reminders |

## Key Features

1. **Provider Directory:** Location-based search, filter by type/services/price
2. **Availability Requests:** Submit request with patient info sharing consent
3. **Reviews:** Circle member reviews with ratings
4. **Respite Tracking (Family):** Log days used, annual goal
5. **Break Reminders (Family):** Weekly reminders to take respite

## Implementation follows the established pattern.

## Acceptance Criteria

- [ ] Location-based search returns nearby providers
- [ ] Filters work for type, services, price range
- [ ] Availability requests submitted successfully
- [ ] Respite days tracked over time (Family)
- [ ] Caregiver break reminders sent (Family)
- [ ] Free tier can browse but not request
- [ ] Reviews tied to verified CuraKnot users

```

---

## Prompt 18: Legal Document Vault

```

Implement the Legal Document Vault for CuraKnot.

## Specification

Read `specsV1/18-LegalDocumentVault.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                                         |
| ------ | -------------------------------------------------------------------- |
| FREE   | No access (feature hidden)                                           |
| PLUS   | Store up to 5 documents, basic sharing                               |
| FAMILY | Unlimited documents, expiration tracking, emergency card integration |

## Legal Document Types Enum

```swift
enum LegalDocumentType: String, Codable, CaseIterable {
    case powerOfAttorney = "POA"
    case healthcareProxy = "HEALTHCARE_PROXY"
    case advanceDirective = "ADVANCE_DIRECTIVE"
    case hipaaAuthorization = "HIPAA_AUTH"
    case doNotResuscitate = "DNR"
    case polst = "POLST"  // Physician Orders for Life-Sustaining Treatment
    case will = "WILL"
    case trust = "TRUST"
    case guardianship = "GUARDIANSHIP"
    case other = "OTHER"
    
    var displayName: String {
        switch self {
        case .powerOfAttorney: return "Power of Attorney"
        case .healthcareProxy: return "Healthcare Proxy"
        case .advanceDirective: return "Advance Directive / Living Will"
        case .hipaaAuthorization: return "HIPAA Authorization"
        case .doNotResuscitate: return "Do Not Resuscitate (DNR)"
        case .polst: return "POLST / MOLST"
        default: return "Other Legal Document"
        }
    }
    
    var expirationReminderDays: Int? {
        switch self {
        case .powerOfAttorney: return 365  // Annual review recommended
        case .hipaaAuthorization: return 365
        case .polst: return 365
        default: return nil  // No standard expiration
        }
    }
}
```

```sql
-- Supabase Schema for Legal Vault
CREATE TYPE legal_document_type AS ENUM (
    'POA', 'HEALTHCARE_PROXY', 'ADVANCE_DIRECTIVE', 'HIPAA_AUTH',
    'DNR', 'POLST', 'WILL', 'TRUST', 'GUARDIANSHIP', 'OTHER'
);

CREATE TABLE IF NOT EXISTS legal_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    
    document_type legal_document_type NOT NULL,
    title text NOT NULL,
    description text,
    
    -- Storage
    storage_path text NOT NULL,
    file_size_bytes int NOT NULL,
    mime_type text NOT NULL,
    
    -- Dates
    effective_date date,
    expiration_date date,
    expiration_reminder_sent boolean DEFAULT false,
    
    -- Access control (per-member granular access)
    owner_user_id uuid NOT NULL,
    access_user_ids uuid[] NOT NULL DEFAULT '{}',
    
    -- Audit
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    last_viewed_at timestamptz,
    view_count int NOT NULL DEFAULT 0
);

-- Per-member access control
CREATE TABLE IF NOT EXISTS legal_document_access (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    granted_by uuid NOT NULL,
    granted_at timestamptz NOT NULL DEFAULT now(),
    
    UNIQUE(document_id, user_id)
);

-- Audit log for compliance
CREATE TABLE IF NOT EXISTS legal_document_audit (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    action text NOT NULL,  -- VIEW | DOWNLOAD | SHARE | UPDATE | DELETE
    ip_address inet,
    user_agent text,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

## Critical Security Requirements

Legal documents are highly sensitive:

1. **Encrypted Storage:** All documents encrypted at rest (Supabase Storage encryption)
2. **Biometric Required:** View ALWAYS requires Face ID/Touch ID (no opt-out for legal docs)
3. **Per-Document Access:** Granular member access controls (not just circle membership)
4. **Complete Audit Trail:** Every view, share, download logged with IP and timestamp
5. **Short-Lived Shares:** Max 7 days, optional access code, single-use option

## Implementation follows the established pattern with security emphasis.

## Acceptance Criteria

- [ ] Documents ALWAYS require biometric to view (mandatory, not optional)
- [ ] Per-member access controls work correctly
- [ ] Share links expire correctly (max 7 days)
- [ ] Expiration reminders sent (Family)
- [ ] Emergency Card can link to critical documents
- [ ] All access logged for audit with IP addresses
- [ ] Plus tier limited to 5 documents
- [ ] Document types properly categorized

```

---

## Prompt 19: Multi-Language Translation

```

Implement the Multi-Language Handoff Translation for CuraKnot.

## Specification

Read `specsV1/19-MultiLanguageTranslation.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                             |
| ------ | ---------------------------------------- |
| FREE   | No translation (see original only)       |
| PLUS   | English ↔ Spanish translation only       |
| FAMILY | All 7 languages, custom medical glossary |

## Supported Languages (ISO 639-1 Codes)

```swift
enum SupportedLanguage: String, Codable, CaseIterable {
    // Phase 1 - Launch
    case english = "en"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    
    // Phase 2 - Expansion
    case vietnamese = "vi"
    case korean = "ko"
    case tagalog = "tl"
    case french = "fr"
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .chineseSimplified: return "简体中文"
        case .vietnamese: return "Tiếng Việt"
        case .korean: return "한국어"
        case .tagalog: return "Tagalog"
        case .french: return "Français"
        }
    }
    
    var nativeDirection: LayoutDirection {
        return .leftToRight  // All supported languages are LTR
    }
    
    static var phase1Languages: [SupportedLanguage] {
        [.english, .spanish, .chineseSimplified]
    }
    
    static var phase2Languages: [SupportedLanguage] {
        [.vietnamese, .korean, .tagalog, .french]
    }
    
    func isAvailable(for tier: SubscriptionTier) -> Bool {
        switch tier {
        case .free: return self == .english  // No translation
        case .plus: return self == .english || self == .spanish
        case .family: return true
        }
    }
}
```

```sql
-- Store translations with cache
CREATE TABLE IF NOT EXISTS handoff_translations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    handoff_id uuid NOT NULL REFERENCES handoffs(id) ON DELETE CASCADE,
    revision_id uuid REFERENCES handoff_revisions(id),
    
    source_language text NOT NULL,  -- ISO 639-1: 'en', 'es', 'zh-Hans'
    target_language text NOT NULL,  -- ISO 639-1
    
    translated_title text,
    translated_summary text,
    translated_content jsonb,  -- Structured brief fields
    
    -- Quality tracking
    translation_engine text NOT NULL,  -- 'GOOGLE' | 'DEEPL' | 'OPENAI'
    confidence_score decimal(3,2),
    
    -- Cache management
    source_hash text NOT NULL,  -- Hash of source content
    is_stale boolean NOT NULL DEFAULT false,
    
    created_at timestamptz NOT NULL DEFAULT now(),
    
    UNIQUE(handoff_id, target_language)
);

-- Custom medical glossary per circle
CREATE TABLE IF NOT EXISTS translation_glossary (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    
    source_language text NOT NULL,
    target_language text NOT NULL,
    
    source_term text NOT NULL,
    translated_term text NOT NULL,
    context text,  -- Optional usage context
    
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    
    UNIQUE(circle_id, source_language, target_language, source_term)
);

CREATE INDEX idx_translations_lookup ON handoff_translations(handoff_id, target_language);
CREATE INDEX idx_glossary_lookup ON translation_glossary(circle_id, source_language, target_language);
```

## Translation Principles

1. **Preserve Original:** Never overwrite, always compute on-read
2. **Medical Safety:** Never translate medication names (keep original + transliteration)
3. **Glossary Support:** Custom circle terms override generic translation
4. **Disclaimers:** Flag medical content with disclaimer in target language

```swift
// TranslationService.swift
class TranslationService {
    /// Translate handoff content, using cache when available
    func translateHandoff(
        _ handoff: Handoff,
        to targetLanguage: SupportedLanguage,
        circleGlossary: [GlossaryEntry]?
    ) async throws -> TranslatedHandoff {
        // 1. Check cache
        if let cached = await checkCache(handoff.id, targetLanguage) {
            if !cached.isStale && cached.sourceHash == handoff.contentHash {
                return cached
            }
        }
        
        // 2. Apply glossary substitutions before translation
        var contentToTranslate = handoff.content
        let medicationNames = extractMedicationNames(contentToTranslate)
        
        // 3. Protect medication names from translation
        let placeholders = medicationNames.enumerated().map { (i, med) in
            (med, "[[MED_\(i)]]")
        }
        for (med, placeholder) in placeholders {
            contentToTranslate = contentToTranslate.replacingOccurrences(of: med, with: placeholder)
        }
        
        // 4. Translate via API
        let translated = try await translationAPI.translate(
            text: contentToTranslate,
            from: handoff.sourceLanguage,
            to: targetLanguage
        )
        
        // 5. Restore medication names (untranslated)
        var finalContent = translated
        for (med, placeholder) in placeholders {
            finalContent = finalContent.replacingOccurrences(of: placeholder, with: med)
        }
        
        // 6. Apply custom glossary overrides
        if let glossary = circleGlossary {
            for entry in glossary {
                finalContent = finalContent.replacingOccurrences(
                    of: entry.genericTranslation,
                    with: entry.customTranslation
                )
            }
        }
        
        // 7. Cache and return
        let result = TranslatedHandoff(
            handoffId: handoff.id,
            targetLanguage: targetLanguage,
            content: finalContent,
            medicationDisclaimer: generateMedDisclaimer(targetLanguage)
        )
        await cacheTranslation(result)
        
        return result
    }
    
    private func generateMedDisclaimer(_ language: SupportedLanguage) -> String {
        switch language {
        case .spanish:
            return "⚠️ Los nombres de medicamentos se muestran en su idioma original por seguridad."
        case .chineseSimplified:
            return "⚠️ 为安全起见，药物名称以原文显示。"
        // ... other languages
        default:
            return "⚠️ Medication names shown in original language for safety."
        }
    }
}
```

## Acceptance Criteria

- [ ] Handoffs display in user's preferred language
- [ ] Toggle shows original text alongside translation
- [ ] Medical terms flagged with safety disclaimer
- [ ] Custom glossary terms override generic translation (Family)
- [ ] Translation cache reduces API calls (>80% cache hit rate)
- [ ] Plus tier limited to English/Spanish only
- [ ] Medication names NEVER translated (shown in original)
- [ ] ISO 639-1 language codes used consistently in database

```

---

## Prompt 20: Care Cost Projection Tool

```

Implement the Care Cost Projection Tool for CuraKnot.

## Specification

Read `specsV1/20-CareCostProjection.md` for complete requirements, UX flows, and data models.

## Premium Tier Gating

| Tier   | Access Level                                       |
| ------ | -------------------------------------------------- |
| FREE   | No access (feature hidden)                         |
| PLUS   | Expense tracking, basic monthly cost view          |
| FAMILY | Full projections, scenario modeling, report export |

## Financial Disclaimers Required

This is NOT financial advice:

1. **Clear Disclaimers:** "This is not financial advice. Consult a professional."
2. **Data Sources:** Show source and date for cost estimates
3. **Projections Are Estimates:** "Based on current patterns and local averages"
4. **No Liability:** Users make their own financial decisions

## Implementation follows the established pattern with disclaimer emphasis.

## Acceptance Criteria

- [ ] Expense logging with receipt attachments works
- [ ] Monthly/yearly expense summaries calculated
- [ ] Cost projections by scenario (Family)
- [ ] Local cost data used for estimates
- [ ] Expense report exports correctly (PDF/CSV)
- [ ] Clear disclaimers throughout (not financial advice)
- [ ] Plus tier limited to expense tracking
- [ ] Data sources and dates displayed

```

---

## Implementation Order Recommendation

For optimal dependency management, implement in this order:

### Foundation (Weeks 1-2)
1. **Siri Shortcuts** — Standalone, establishes App Intents patterns
2. **Care Calendar Sync** — Standalone, EventKit foundation
3. **Apple Watch** — Depends on WatchConnectivity, core data caching

### AI Features (Weeks 3-4)
4. **Universal Document Scanner** — Enables other features (discharge, med reconciliation)
5. **AI Care Coach** — Core AI infrastructure, LLM patterns
6. **Smart Appointment Questions** — Builds on AI patterns
7. **Symptom Pattern Surfacing** — Uses handoff NLP, cron job patterns

### Caregiver Support (Weeks 5-6)
8. **Caregiver Wellness** — Standalone, notification patterns
9. **Hospital Discharge Wizard** — Uses tasks, integrates with scanner
10. **Facility Communication Log** — Uses binder, task integration

### Reference Features (Weeks 7-8)
11. **Care Network Directory** — Uses binder data, PDF generation
12. **Condition Photo Tracking** — Standalone, privacy patterns
13. **Legal Document Vault** — Uses share_links, biometric patterns

### Engagement Features (Weeks 9-10)
14. **Gratitude Journal** — Standalone, photo storage
15. **Family Video Board** — Video infrastructure, storage management
16. **Family Meeting Mode** — Uses tasks, handoffs, calendar

### Expansion Features (Weeks 11-12)
17. **Medical Transportation** — Uses calendar, tasks, notifications
18. **Respite Care Finder** — Standalone, location services
19. **Multi-Language Translation** — Affects all content, caching
20. **Care Cost Projection** — Uses binder, billing data

---

## Notes for Implementation

### Tier Enforcement
```swift
// SubscriptionService.swift
extension SubscriptionTier {
    var hasFeature(_ feature: Feature) -> Bool {
        switch feature {
        case .siriAdvanced: return self >= .plus
        case .calendarSync: return self >= .plus
        case .watchApp: return self >= .plus
        // ... etc
        }
    }
}
````

### Analytics Pattern

```swift
// All ViewModels should follow this pattern
@MainActor
class FeatureViewModel: ObservableObject {
    @Published var state: ViewState = .idle
    @Published var error: FeatureError?

    enum ViewState {
        case idle, loading, loaded, error
    }

    func performAction() async {
        state = .loading
        do {
            // Action
            state = .loaded
        } catch {
            state = .error
            self.error = FeatureError(underlyingError: error)
        }
    }
}
```

### Error Handling Pattern

```swift
// Error Handling Pattern
@MainActor
class FeatureViewModel: ObservableObject {
    @Published var state: ViewState = .idle
    @Published var error: FeatureError?

    enum ViewState {
        case idle, loading, loaded, error
    }

    func performAction() async {
        state = .loading
        do {
            // Action
            state = .loaded
        } catch {
            state = .error
            self.error = FeatureError(underlyingError: error)
        }
    }
}
```

### Testing Requirements (All Features)

- Unit test coverage: > 80%
- Integration tests for all Edge Functions
- UI tests for critical flows
- Accessibility audit (VoiceOver, Dynamic Type)
- Performance profiling (Instruments)

### Pre-Commit Checklist

- [ ] All tests pass
- [ ] No compiler warnings
- [ ] Accessibility audit passed
- [ ] Analytics events verified
- [ ] Tier gating tested for all tiers
- [ ] Error states tested
- [ ] Offline behavior verified
