-- ============================================================================
-- Migration: 20260206000004_fix_rate_limiting_race.sql
-- Description: Fix race condition in rate limiting by using atomic operations
-- ============================================================================

-- Replace the validate_ical_token function with atomic rate limiting
CREATE OR REPLACE FUNCTION validate_ical_token(p_token text)
RETURNS TABLE (
    is_valid boolean,
    circle_id uuid,
    feed_config jsonb,
    error_code text
) AS $$
DECLARE
    v_token_record RECORD;
    v_new_count integer;
BEGIN
    -- Validate token format (base64url: alphanumeric, -, _)
    IF p_token !~ '^[A-Za-z0-9_-]+$' THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'INVALID_TOKEN_FORMAT';
        RETURN;
    END IF;

    -- Use FOR UPDATE to lock the row and prevent race conditions
    SELECT * INTO v_token_record
    FROM ical_feed_tokens
    WHERE token = p_token
    FOR UPDATE;

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

    -- Atomic rate limiting: update and return new count in one operation
    -- Reset count if window expired, otherwise increment
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
    -- Note: We check AFTER incrementing so the limit is enforced atomically
    IF v_new_count > 100 THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::jsonb, 'RATE_LIMITED';
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
        NULL::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION validate_ical_token IS
    'Validates iCal feed token with atomic rate limiting (100 req/hour). Uses FOR UPDATE to prevent race conditions.';
