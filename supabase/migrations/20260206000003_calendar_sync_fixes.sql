-- ============================================================================
-- Migration: 20260206000003_calendar_sync_fixes.sql
-- Description: Security fixes for calendar sync - RLS policies and rate limiting
-- ============================================================================

-- ============================================================================
-- FIX: Update RLS policies to check circle membership on update/delete
-- ============================================================================

-- Drop and recreate calendar_connections update policy with circle membership check
DROP POLICY IF EXISTS calendar_connections_update ON calendar_connections;
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

-- Drop and recreate calendar_connections delete policy with circle membership check
DROP POLICY IF EXISTS calendar_connections_delete ON calendar_connections;
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

-- ============================================================================
-- FIX: Update validate_ical_token function with rate limiting
-- ============================================================================

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
-- Add encryption_key_id column if not exists (for future OAuth token encryption)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'calendar_connections'
        AND column_name = 'encryption_key_id'
    ) THEN
        ALTER TABLE calendar_connections ADD COLUMN encryption_key_id uuid;
        COMMENT ON COLUMN calendar_connections.encryption_key_id IS
            'Reference to encryption key for OAuth token rotation. Use with Supabase Vault or pgsodium.';
    END IF;
END $$;

-- Drop old encryption_version column if it exists (replaced by encryption_key_id)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'calendar_connections'
        AND column_name = 'encryption_version'
    ) THEN
        ALTER TABLE calendar_connections DROP COLUMN encryption_version;
    END IF;
END $$;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION validate_ical_token IS
    'Validates iCal feed token with rate limiting (100 req/hour). Returns feed configuration if valid.';
