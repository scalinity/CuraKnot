-- ============================================================================
-- Migration: 20260206000005_calendar_sync_security.sql
-- Description: Security and data integrity fixes for calendar sync
--              - Add input validation to SECURITY DEFINER functions
--              - Add CHECK constraints for data integrity
--              - Add missing indexes for performance
-- ============================================================================

-- ============================================================================
-- FUNCTION FIXES: Add input validation to SECURITY DEFINER functions
-- ============================================================================

-- Fix has_calendar_access to validate inputs
CREATE OR REPLACE FUNCTION has_calendar_access(p_user_id uuid, p_circle_id uuid)
RETURNS text AS $$
DECLARE
    v_features jsonb;
BEGIN
    -- Input validation for SECURITY DEFINER function
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'Invalid input: p_user_id cannot be null';
    END IF;

    IF p_circle_id IS NULL THEN
        RAISE EXCEPTION 'Invalid input: p_circle_id cannot be null';
    END IF;

    -- Check if user is member of circle with active subscription
    SELECT pl.features_json INTO v_features
    FROM circle_members cm
    JOIN subscriptions s ON s.user_id = cm.user_id
    JOIN plan_limits pl ON pl.plan = s.plan
    WHERE cm.user_id = p_user_id
      AND cm.circle_id = p_circle_id
      AND cm.status = 'ACTIVE'
      AND s.status IN ('ACTIVE', 'TRIALING')
    LIMIT 1;

    IF v_features IS NULL THEN
        RETURN 'READ_ONLY';  -- Default for non-members or inactive subscriptions
    END IF;

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

-- Update validate_ical_token to return token_id for audit logging
-- Must drop first because return type is changing
DROP FUNCTION IF EXISTS validate_ical_token(text);

CREATE OR REPLACE FUNCTION validate_ical_token(p_token text)
RETURNS TABLE (
    is_valid boolean,
    circle_id uuid,
    feed_config jsonb,
    error_code text,
    token_id uuid
) AS $$
DECLARE
    v_token_record RECORD;
    v_new_count integer;
BEGIN
    -- Input validation for SECURITY DEFINER function
    IF p_token IS NULL THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'INVALID_TOKEN_FORMAT'::text, NULL::uuid;
        RETURN;
    END IF;

    -- Validate token format (exactly 43 chars of base64url: alphanumeric, -, _)
    IF p_token !~ '^[A-Za-z0-9_-]{43}$' THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'INVALID_TOKEN_FORMAT'::text, NULL::uuid;
        RETURN;
    END IF;

    -- Use FOR UPDATE to lock the row and prevent race conditions
    SELECT * INTO v_token_record
    FROM ical_feed_tokens
    WHERE token = p_token
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'TOKEN_NOT_FOUND'::text, NULL::uuid;
        RETURN;
    END IF;

    IF v_token_record.revoked_at IS NOT NULL THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'TOKEN_REVOKED'::text, NULL::uuid;
        RETURN;
    END IF;

    IF v_token_record.expires_at IS NOT NULL AND v_token_record.expires_at < now() THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'TOKEN_EXPIRED'::text, NULL::uuid;
        RETURN;
    END IF;

    -- Atomic rate limiting: update and return new count in one operation
    UPDATE ical_feed_tokens
    SET
        access_count = CASE
            WHEN last_accessed_at IS NULL OR last_accessed_at < now() - interval '1 hour'
            THEN 1
            ELSE access_count + 1
        END,
        last_accessed_at = now()
    WHERE id = v_token_record.id
    RETURNING access_count INTO v_new_count;

    -- Check rate limit (100 requests per hour)
    IF v_new_count > 100 THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'RATE_LIMITED'::text, v_token_record.id;
        RETURN;
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
        NULL::text,
        v_token_record.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CHECK CONSTRAINTS: Data integrity
-- ============================================================================

-- Add CHECK constraint for sync_interval_minutes (5 min to 24 hours)
ALTER TABLE calendar_connections
DROP CONSTRAINT IF EXISTS chk_sync_interval_minutes;

ALTER TABLE calendar_connections
ADD CONSTRAINT chk_sync_interval_minutes
CHECK (sync_interval_minutes >= 5 AND sync_interval_minutes <= 1440);

-- Add CHECK constraint for lookahead_days (1 to 730 days = 2 years)
ALTER TABLE ical_feed_tokens
DROP CONSTRAINT IF EXISTS chk_lookahead_days;

ALTER TABLE ical_feed_tokens
ADD CONSTRAINT chk_lookahead_days
CHECK (lookahead_days >= 1 AND lookahead_days <= 730);

-- Add CHECK constraint for token format (exactly 43 chars base64url)
ALTER TABLE ical_feed_tokens
DROP CONSTRAINT IF EXISTS chk_token_format;

ALTER TABLE ical_feed_tokens
ADD CONSTRAINT chk_token_format
CHECK (token ~ '^[A-Za-z0-9_-]{43}$');

-- Add CHECK constraint for source_type matching source_id columns
ALTER TABLE calendar_events
DROP CONSTRAINT IF EXISTS chk_source_type_id_match;

ALTER TABLE calendar_events
ADD CONSTRAINT chk_source_type_id_match
CHECK (
    (source_type = 'TASK' AND source_task_id IS NOT NULL AND source_shift_id IS NULL AND source_binder_item_id IS NULL AND source_handoff_id IS NULL) OR
    (source_type = 'SHIFT' AND source_shift_id IS NOT NULL AND source_task_id IS NULL AND source_binder_item_id IS NULL AND source_handoff_id IS NULL) OR
    (source_type = 'APPOINTMENT' AND source_binder_item_id IS NOT NULL AND source_task_id IS NULL AND source_shift_id IS NULL AND source_handoff_id IS NULL) OR
    (source_type = 'HANDOFF_FOLLOWUP' AND source_handoff_id IS NOT NULL AND source_task_id IS NULL AND source_shift_id IS NULL AND source_binder_item_id IS NULL)
);

-- ============================================================================
-- INDEXES: Performance improvements
-- ============================================================================

-- Index for incremental sync by sync_cursor
CREATE INDEX IF NOT EXISTS idx_calendar_connections_sync_cursor
ON calendar_connections(sync_cursor)
WHERE sync_cursor IS NOT NULL;

-- Index for event deduplication by external_ical_uid
CREATE INDEX IF NOT EXISTS idx_calendar_events_ical_uid
ON calendar_events(external_ical_uid)
WHERE external_ical_uid IS NOT NULL;

-- Remove redundant token index (UNIQUE constraint already creates index)
DROP INDEX IF EXISTS idx_ical_feed_tokens_token;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION has_calendar_access IS
    'Returns calendar access level for a user in a circle. Validates inputs before processing.';

COMMENT ON FUNCTION validate_ical_token IS
    'Validates iCal feed token with atomic rate limiting (100 req/hour). Returns token_id for audit logging.';

COMMENT ON CONSTRAINT chk_source_type_id_match ON calendar_events IS
    'Ensures source_type matches the correct source_id column (only one source_id can be set)';

COMMENT ON CONSTRAINT chk_sync_interval_minutes ON calendar_connections IS
    'Sync interval must be between 5 minutes and 24 hours (1440 minutes)';

COMMENT ON CONSTRAINT chk_lookahead_days ON ical_feed_tokens IS
    'Lookahead days must be between 1 and 730 (2 years)';

COMMENT ON CONSTRAINT chk_token_format ON ical_feed_tokens IS
    'Token must be exactly 43 characters of base64url encoding';
