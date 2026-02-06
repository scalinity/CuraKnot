-- ============================================================================
-- Migration: Video Board Security Fixes
-- Description: Add WITH CHECK to UPDATE policy, add rate limiting support
-- ============================================================================

-- Drop and recreate UPDATE policy with WITH CHECK clause
DROP POLICY IF EXISTS "Creator can update own video admins can moderate" ON video_messages;

CREATE POLICY "Creator can update own video admins can moderate" ON video_messages
    FOR UPDATE
    USING (
        -- Creator within 24 hours
        (created_by = auth.uid() AND created_at > now() - interval '24 hours') OR
        -- Admin/Owner for moderation
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = video_messages.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
              AND circle_members.role IN ('ADMIN', 'OWNER')
        )
    )
    WITH CHECK (
        -- Prevent escalation: can only update to certain statuses
        -- Creator can only update caption, save_forever (not status except to FLAGGED)
        (
            created_by = auth.uid() AND
            created_at > now() - interval '24 hours' AND
            status IN ('ACTIVE', 'FLAGGED')
        ) OR
        -- Admin/Owner can set any allowed status
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = video_messages.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
              AND circle_members.role IN ('ADMIN', 'OWNER')
        )
    );

-- ============================================================================
-- TABLE: video_upload_rate_limits (for rate limiting at DB level)
-- ============================================================================

CREATE TABLE IF NOT EXISTS video_upload_rate_limits (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    upload_count int NOT NULL DEFAULT 0,
    window_start timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE video_upload_rate_limits ENABLE ROW LEVEL SECURITY;

-- Only service role can access this table
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role only' AND tablename = 'video_upload_rate_limits') THEN
        CREATE POLICY "Service role only" ON video_upload_rate_limits
            FOR ALL USING (false);
    END IF;
END $$;

-- ============================================================================
-- FUNCTION: Check and increment upload rate limit (simplified API)
-- ============================================================================

CREATE OR REPLACE FUNCTION check_rate_limit(
    p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_max_uploads int := 10;
    v_window_hours int := 1;
    v_window_start timestamptz;
    v_record video_upload_rate_limits%ROWTYPE;
    v_allowed boolean;
BEGIN
    v_window_start := now() - (v_window_hours || ' hours')::interval;

    -- Get or create rate limit record
    SELECT * INTO v_record
    FROM video_upload_rate_limits
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Create new record
        INSERT INTO video_upload_rate_limits (user_id, upload_count, window_start)
        VALUES (p_user_id, 1, now())
        ON CONFLICT (user_id) DO UPDATE
        SET upload_count = CASE
                WHEN video_upload_rate_limits.window_start < v_window_start THEN 1
                ELSE video_upload_rate_limits.upload_count + 1
            END,
            window_start = CASE
                WHEN video_upload_rate_limits.window_start < v_window_start THEN now()
                ELSE video_upload_rate_limits.window_start
            END,
            updated_at = now()
        RETURNING * INTO v_record;

        v_allowed := v_record.upload_count <= v_max_uploads;
    ELSE
        -- Check if window has expired
        IF v_record.window_start < v_window_start THEN
            -- Reset window
            UPDATE video_upload_rate_limits
            SET upload_count = 1, window_start = now(), updated_at = now()
            WHERE user_id = p_user_id;
            v_allowed := true;
        ELSIF v_record.upload_count >= v_max_uploads THEN
            -- Rate limited
            v_allowed := false;
        ELSE
            -- Increment
            UPDATE video_upload_rate_limits
            SET upload_count = upload_count + 1, updated_at = now()
            WHERE user_id = p_user_id;
            v_allowed := true;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'allowed', v_allowed,
        'current_count', COALESCE(v_record.upload_count, 1),
        'max_uploads', v_max_uploads,
        'window_hours', v_window_hours
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Check video quota for a user (extended version)
-- ============================================================================

CREATE OR REPLACE FUNCTION check_video_upload_rate_limit(
    p_user_id uuid,
    p_max_uploads int DEFAULT 10,
    p_window_hours int DEFAULT 1
)
RETURNS jsonb AS $$
DECLARE
    v_record video_upload_rate_limits%ROWTYPE;
    v_window_start timestamptz;
    v_allowed boolean;
BEGIN
    v_window_start := now() - (p_window_hours || ' hours')::interval;

    -- Get or create rate limit record
    SELECT * INTO v_record
    FROM video_upload_rate_limits
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Create new record
        INSERT INTO video_upload_rate_limits (user_id, upload_count, window_start)
        VALUES (p_user_id, 1, now())
        ON CONFLICT (user_id) DO UPDATE
        SET upload_count = CASE
                WHEN video_upload_rate_limits.window_start < v_window_start THEN 1
                ELSE video_upload_rate_limits.upload_count + 1
            END,
            window_start = CASE
                WHEN video_upload_rate_limits.window_start < v_window_start THEN now()
                ELSE video_upload_rate_limits.window_start
            END,
            updated_at = now()
        RETURNING * INTO v_record;

        v_allowed := v_record.upload_count <= p_max_uploads;
    ELSE
        -- Check if window has expired
        IF v_record.window_start < v_window_start THEN
            -- Reset window
            UPDATE video_upload_rate_limits
            SET upload_count = 1, window_start = now(), updated_at = now()
            WHERE user_id = p_user_id;
            v_allowed := true;
        ELSIF v_record.upload_count >= p_max_uploads THEN
            -- Rate limited
            v_allowed := false;
        ELSE
            -- Increment
            UPDATE video_upload_rate_limits
            SET upload_count = upload_count + 1, updated_at = now()
            WHERE user_id = p_user_id;
            v_allowed := true;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'allowed', v_allowed,
        'current_count', COALESCE(v_record.upload_count, 1),
        'max_uploads', p_max_uploads,
        'window_hours', p_window_hours
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Add file validation constraint (magic bytes will be checked server-side)
-- ============================================================================

-- Add a check that storage_key follows expected pattern
ALTER TABLE video_messages DROP CONSTRAINT IF EXISTS video_messages_storage_key_format;
ALTER TABLE video_messages ADD CONSTRAINT video_messages_storage_key_format
    CHECK (storage_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.mp4$');

-- Add similar check for thumbnail_key
ALTER TABLE video_messages DROP CONSTRAINT IF EXISTS video_messages_thumbnail_key_format;
ALTER TABLE video_messages ADD CONSTRAINT video_messages_thumbnail_key_format
    CHECK (thumbnail_key IS NULL OR thumbnail_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_thumb\.jpg$');

-- ============================================================================
-- Refresh video stats function alias
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_video_stats()
RETURNS void AS $$
BEGIN
    PERFORM refresh_circle_video_stats();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
