-- ============================================================================
-- Migration: 20260206000002_calendar_sync.sql
-- Description: Calendar sync tables for bi-directional sync with external calendars
-- ============================================================================

-- ============================================================================
-- TABLE: calendar_connections
-- Purpose: Stores OAuth tokens and sync configuration per user per provider
-- ============================================================================

CREATE TABLE IF NOT EXISTS calendar_connections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,

    -- Provider identification
    provider text NOT NULL CHECK (provider IN ('APPLE', 'GOOGLE', 'OUTLOOK')),
    provider_account_id text,  -- External account identifier (email for Google/Outlook)

    -- Connection status
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACTIVE', 'REVOKED', 'ERROR')),
    status_message text,  -- Error details when status = 'ERROR'

    -- OAuth tokens (Google/Outlook - FAMILY tier only)
    -- SECURITY NOTE: These columns store encrypted tokens. For production use with
    -- Google/Outlook OAuth, implement encryption using one of:
    -- 1. Supabase Vault: SELECT vault.create_secret('token_' || id, token_value)
    -- 2. pgsodium: SELECT pgsodium.crypto_secretbox(token_value, nonce, key_id)
    -- 3. Application-level encryption before insert
    -- Apple Calendar uses EventKit locally, no OAuth tokens stored server-side.
    access_token_encrypted text,
    refresh_token_encrypted text,
    encryption_key_id uuid,  -- Reference to encryption key for rotation support
    token_expires_at timestamptz,

    -- Apple Calendar specific (stored locally on device, synced here for reference)
    apple_calendar_id text,
    apple_calendar_title text,

    -- External calendar selection (Google/Outlook)
    calendar_id text,
    calendar_title text,

    -- Sync configuration
    sync_direction text NOT NULL DEFAULT 'BIDIRECTIONAL'
        CHECK (sync_direction IN ('READ_ONLY', 'WRITE_ONLY', 'BIDIRECTIONAL')),
    conflict_strategy text NOT NULL DEFAULT 'CURAKNOT_WINS'
        CHECK (conflict_strategy IN ('CURAKNOT_WINS', 'EXTERNAL_WINS', 'MANUAL', 'MERGE')),
    sync_interval_minutes int NOT NULL DEFAULT 15,

    -- Event type toggles
    sync_tasks boolean NOT NULL DEFAULT true,
    sync_shifts boolean NOT NULL DEFAULT true,
    sync_appointments boolean NOT NULL DEFAULT true,
    sync_handoff_followups boolean NOT NULL DEFAULT false,

    -- Privacy options
    show_minimal_details boolean NOT NULL DEFAULT false,  -- Show "CuraKnot Event" vs full title

    -- Sync state
    last_sync_at timestamptz,
    last_sync_status text CHECK (last_sync_status IN ('SUCCESS', 'PARTIAL', 'FAILED')),
    last_sync_error text,
    sync_cursor text,  -- Provider-specific sync token/delta token
    events_synced_count int NOT NULL DEFAULT 0,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(user_id, circle_id, provider)
);

-- ============================================================================
-- TABLE: calendar_events
-- Purpose: Maps CuraKnot entities to external calendar events
-- ============================================================================

CREATE TABLE IF NOT EXISTS calendar_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id uuid NOT NULL REFERENCES calendar_connections(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,

    -- Source entity (one of these will be set based on source_type)
    source_type text NOT NULL CHECK (source_type IN ('TASK', 'SHIFT', 'APPOINTMENT', 'HANDOFF_FOLLOWUP')),
    source_task_id uuid REFERENCES tasks(id) ON DELETE CASCADE,
    source_shift_id uuid REFERENCES care_shifts(id) ON DELETE CASCADE,
    source_binder_item_id uuid REFERENCES binder_items(id) ON DELETE CASCADE,
    source_handoff_id uuid REFERENCES handoffs(id) ON DELETE CASCADE,

    -- External calendar reference
    external_event_id text NOT NULL,
    external_calendar_id text,
    external_etag text,  -- For change detection (If-Match header)
    external_ical_uid text,  -- iCal UID for deduplication

    -- Event data snapshot (for conflict detection and display)
    title text NOT NULL,
    description text,
    start_at timestamptz NOT NULL,
    end_at timestamptz,
    all_day boolean NOT NULL DEFAULT false,
    location text,

    -- Recurrence (if applicable)
    recurrence_rule text,  -- RRULE string
    recurrence_id text,  -- For exception instances

    -- Sync state
    sync_status text NOT NULL DEFAULT 'SYNCED'
        CHECK (sync_status IN ('SYNCED', 'PENDING_PUSH', 'PENDING_PULL', 'CONFLICT', 'ERROR', 'DELETED')),
    sync_error text,

    -- Conflict resolution data
    conflict_data_json jsonb,  -- Stores both versions for manual resolution
    conflict_detected_at timestamptz,
    conflict_resolved_at timestamptz,
    conflict_resolution text,  -- 'LOCAL' | 'EXTERNAL' | 'MERGED' | 'DISCARDED'

    -- Timestamps for conflict detection
    last_synced_at timestamptz,
    local_updated_at timestamptz NOT NULL DEFAULT now(),
    external_updated_at timestamptz,

    -- Audit
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(connection_id, external_event_id)
);

-- ============================================================================
-- TABLE: ical_feed_tokens
-- Purpose: Secret URLs for read-only iCal subscription feeds
-- ============================================================================

CREATE TABLE IF NOT EXISTS ical_feed_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,

    -- Cryptographic token (32 bytes, base64url encoded = 43 chars)
    -- Used in URL: /functions/v1/ical-feed/{token}
    token text NOT NULL UNIQUE,

    -- Human-readable name for the feed
    feed_name text,

    -- Feed configuration
    include_tasks boolean NOT NULL DEFAULT true,
    include_shifts boolean NOT NULL DEFAULT true,
    include_appointments boolean NOT NULL DEFAULT true,
    include_handoff_followups boolean NOT NULL DEFAULT false,

    -- Patient filtering (NULL = all patients in circle)
    patient_ids uuid[],

    -- Privacy
    show_minimal_details boolean NOT NULL DEFAULT false,

    -- Lookahead window (days into future to include)
    lookahead_days int NOT NULL DEFAULT 90,

    -- Access control
    expires_at timestamptz,  -- NULL = never expires
    revoked_at timestamptz,

    -- Analytics
    access_count int NOT NULL DEFAULT 0,
    last_accessed_at timestamptz,
    last_accessed_ip inet,
    last_accessed_user_agent text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- calendar_connections indexes
CREATE INDEX IF NOT EXISTS idx_calendar_connections_user
    ON calendar_connections(user_id);
CREATE INDEX IF NOT EXISTS idx_calendar_connections_circle
    ON calendar_connections(circle_id);
CREATE INDEX IF NOT EXISTS idx_calendar_connections_active
    ON calendar_connections(status) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_calendar_connections_needs_sync
    ON calendar_connections(last_sync_at)
    WHERE status = 'ACTIVE' AND sync_direction != 'READ_ONLY';

-- calendar_events indexes
CREATE INDEX IF NOT EXISTS idx_calendar_events_connection
    ON calendar_events(connection_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_circle
    ON calendar_events(circle_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_patient
    ON calendar_events(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calendar_events_sync_pending
    ON calendar_events(sync_status) WHERE sync_status IN ('PENDING_PUSH', 'PENDING_PULL', 'CONFLICT');
CREATE INDEX IF NOT EXISTS idx_calendar_events_source_task
    ON calendar_events(source_task_id) WHERE source_task_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calendar_events_source_shift
    ON calendar_events(source_shift_id) WHERE source_shift_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calendar_events_source_binder
    ON calendar_events(source_binder_item_id) WHERE source_binder_item_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calendar_events_time_range
    ON calendar_events(start_at, end_at);

-- ical_feed_tokens indexes
CREATE INDEX IF NOT EXISTS idx_ical_feed_tokens_token
    ON ical_feed_tokens(token);
CREATE INDEX IF NOT EXISTS idx_ical_feed_tokens_circle
    ON ical_feed_tokens(circle_id);
-- Index for active (non-revoked) tokens - expiration check done at query time
CREATE INDEX IF NOT EXISTS idx_ical_feed_tokens_active
    ON ical_feed_tokens(id)
    WHERE revoked_at IS NULL;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE calendar_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ical_feed_tokens ENABLE ROW LEVEL SECURITY;

-- calendar_connections: Users can manage their own connections within their circles
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_connections_select' AND tablename = 'calendar_connections') THEN
        CREATE POLICY calendar_connections_select ON calendar_connections
            FOR SELECT USING (
                user_id = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = calendar_connections.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_connections_insert' AND tablename = 'calendar_connections') THEN
        CREATE POLICY calendar_connections_insert ON calendar_connections
            FOR INSERT WITH CHECK (
                user_id = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = calendar_connections.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_connections_update' AND tablename = 'calendar_connections') THEN
        CREATE POLICY calendar_connections_update ON calendar_connections
            FOR UPDATE USING (
                user_id = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = calendar_connections.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_connections_delete' AND tablename = 'calendar_connections') THEN
        CREATE POLICY calendar_connections_delete ON calendar_connections
            FOR DELETE USING (
                user_id = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = calendar_connections.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- calendar_events: Users can see events for their connections
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_events_select' AND tablename = 'calendar_events') THEN
        CREATE POLICY calendar_events_select ON calendar_events
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM calendar_connections c
                    WHERE c.id = calendar_events.connection_id
                    AND c.user_id = auth.uid()
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_events_insert' AND tablename = 'calendar_events') THEN
        CREATE POLICY calendar_events_insert ON calendar_events
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM calendar_connections c
                    WHERE c.id = calendar_events.connection_id
                    AND c.user_id = auth.uid()
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_events_update' AND tablename = 'calendar_events') THEN
        CREATE POLICY calendar_events_update ON calendar_events
            FOR UPDATE USING (
                EXISTS (
                    SELECT 1 FROM calendar_connections c
                    WHERE c.id = calendar_events.connection_id
                    AND c.user_id = auth.uid()
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'calendar_events_delete' AND tablename = 'calendar_events') THEN
        CREATE POLICY calendar_events_delete ON calendar_events
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM calendar_connections c
                    WHERE c.id = calendar_events.connection_id
                    AND c.user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- ical_feed_tokens: Admins can manage, service role can read for feed generation
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ical_feed_tokens_select' AND tablename = 'ical_feed_tokens') THEN
        CREATE POLICY ical_feed_tokens_select ON ical_feed_tokens
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = ical_feed_tokens.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                    AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ical_feed_tokens_insert' AND tablename = 'ical_feed_tokens') THEN
        CREATE POLICY ical_feed_tokens_insert ON ical_feed_tokens
            FOR INSERT WITH CHECK (
                created_by = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = ical_feed_tokens.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                    AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ical_feed_tokens_update' AND tablename = 'ical_feed_tokens') THEN
        CREATE POLICY ical_feed_tokens_update ON ical_feed_tokens
            FOR UPDATE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = ical_feed_tokens.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                    AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ical_feed_tokens_delete' AND tablename = 'ical_feed_tokens') THEN
        CREATE POLICY ical_feed_tokens_delete ON ical_feed_tokens
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = ical_feed_tokens.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                    AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to check if user has calendar sync feature access
CREATE OR REPLACE FUNCTION has_calendar_access(p_user_id uuid, p_circle_id uuid)
RETURNS text AS $$
DECLARE
    v_plan text;
    v_features jsonb;
BEGIN
    -- Get circle's plan
    SELECT plan INTO v_plan
    FROM circles
    WHERE id = p_circle_id;

    IF v_plan IS NULL THEN
        RETURN 'NONE';
    END IF;

    -- Get plan features
    SELECT features_json INTO v_features
    FROM plan_limits
    WHERE plan = v_plan;

    -- Check feature flags
    IF v_features ? 'shared_calendar' THEN
        RETURN 'MULTI_PROVIDER';  -- FAMILY tier
    ELSIF v_features ? 'calendar_bidirectional' THEN
        RETURN 'SINGLE_PROVIDER';  -- PLUS tier
    ELSIF v_features ? 'calendar_readonly' THEN
        RETURN 'READ_ONLY';  -- FREE tier
    ELSE
        RETURN 'READ_ONLY';  -- Default to read-only
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to validate iCal feed token
CREATE OR REPLACE FUNCTION validate_ical_token(p_token text)
RETURNS TABLE (
    is_valid boolean,
    circle_id uuid,
    feed_config jsonb,
    error_code text
) AS $$
DECLARE
    v_token_record ical_feed_tokens%ROWTYPE;
BEGIN
    SELECT * INTO v_token_record
    FROM ical_feed_tokens
    WHERE token = p_token;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'TOKEN_NOT_FOUND';
        RETURN;
    END IF;

    IF v_token_record.revoked_at IS NOT NULL THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'TOKEN_REVOKED';
        RETURN;
    END IF;

    IF v_token_record.expires_at IS NOT NULL AND v_token_record.expires_at < now() THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'TOKEN_EXPIRED';
        RETURN;
    END IF;

    -- Rate limiting: max 100 requests per hour per token
    IF v_token_record.access_count > 100 
       AND v_token_record.last_accessed_at IS NOT NULL
       AND v_token_record.last_accessed_at > now() - interval '1 hour' THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'RATE_LIMITED';
        RETURN;
    END IF;

    -- Reset access count if last access was more than 1 hour ago
    IF v_token_record.last_accessed_at IS NULL 
       OR v_token_record.last_accessed_at < now() - interval '1 hour' THEN
        UPDATE ical_feed_tokens
        SET access_count = 1,
            last_accessed_at = now()
        WHERE id = v_token_record.id;
    ELSE
        -- Update access stats
        UPDATE ical_feed_tokens
        SET access_count = access_count + 1,
            last_accessed_at = now()
        WHERE id = v_token_record.id;
    END IF;

    RETURN QUERY SELECT
        true,
        v_token_record.circle_id,
        jsonb_build_object(
            'include_tasks', v_token_record.include_tasks,
            'include_shifts', v_token_record.include_shifts,
            'include_appointments', v_token_record.include_appointments,
            'include_handoff_followups', v_token_record.include_handoff_followups,
            'patient_ids', v_token_record.patient_ids,
            'show_minimal_details', v_token_record.show_minimal_details,
            'lookahead_days', v_token_record.lookahead_days
        ),
        NULL::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_calendar_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS calendar_connections_updated_at ON calendar_connections;
CREATE TRIGGER calendar_connections_updated_at
    BEFORE UPDATE ON calendar_connections
    FOR EACH ROW EXECUTE FUNCTION update_calendar_updated_at();

DROP TRIGGER IF EXISTS calendar_events_updated_at ON calendar_events;
CREATE TRIGGER calendar_events_updated_at
    BEFORE UPDATE ON calendar_events
    FOR EACH ROW EXECUTE FUNCTION update_calendar_updated_at();

DROP TRIGGER IF EXISTS ical_feed_tokens_updated_at ON ical_feed_tokens;
CREATE TRIGGER ical_feed_tokens_updated_at
    BEFORE UPDATE ON ical_feed_tokens
    FOR EACH ROW EXECUTE FUNCTION update_calendar_updated_at();

-- ============================================================================
-- UPDATE PLAN LIMITS
-- Add calendar feature flags if not present
-- ============================================================================

-- Add calendar_readonly to FREE tier
UPDATE plan_limits
SET features_json = features_json || '["calendar_readonly"]'::jsonb
WHERE plan = 'FREE'
  AND NOT features_json ? 'calendar_readonly';

-- Ensure calendar_bidirectional is in PLUS tier
UPDATE plan_limits
SET features_json = features_json || '["calendar_bidirectional"]'::jsonb
WHERE plan = 'PLUS'
  AND NOT features_json ? 'calendar_bidirectional';

-- Ensure shared_calendar is in FAMILY tier (already present per CLAUDE.md)
UPDATE plan_limits
SET features_json = features_json || '["shared_calendar"]'::jsonb
WHERE plan = 'FAMILY'
  AND NOT features_json ? 'shared_calendar';

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE calendar_connections IS 'Stores calendar provider connections with OAuth tokens and sync configuration per user';
COMMENT ON TABLE calendar_events IS 'Maps CuraKnot entities (tasks, shifts, appointments) to external calendar events';
COMMENT ON TABLE ical_feed_tokens IS 'Secret tokens for read-only iCal subscription feeds';

COMMENT ON FUNCTION has_calendar_access IS 'Returns calendar access level based on subscription tier: NONE, READ_ONLY, SINGLE_PROVIDER, MULTI_PROVIDER';
COMMENT ON FUNCTION validate_ical_token IS 'Validates iCal feed token and returns feed configuration if valid';
