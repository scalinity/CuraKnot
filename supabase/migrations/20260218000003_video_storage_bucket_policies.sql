-- ============================================================================
-- Migration: Video Storage Bucket with RLS Policies
-- Description: Create video-messages storage bucket with proper access controls
-- ============================================================================

-- Create the storage bucket (idempotent)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'video-messages',
    'video-messages',
    false,  -- Private bucket, requires authentication
    104857600,  -- 100MB limit per file
    ARRAY['video/mp4', 'video/quicktime', 'image/jpeg']::text[]
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================
-- Storage RLS Policies for video-messages bucket
-- ============================================================================

-- Drop existing policies to recreate with proper security
DROP POLICY IF EXISTS "Circle members can read videos" ON storage.objects;
DROP POLICY IF EXISTS "Circle members can upload videos" ON storage.objects;
DROP POLICY IF EXISTS "Video owner can delete own videos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete any video" ON storage.objects;

-- Policy: Circle members can read videos from their circles
CREATE POLICY "Circle members can read videos" ON storage.objects
    FOR SELECT
    USING (
        bucket_id = 'video-messages'
        AND auth.uid() IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM circle_members cm
            WHERE cm.user_id = auth.uid()
              AND cm.status = 'ACTIVE'
              AND cm.circle_id::text = split_part(name, '/', 1)
        )
    );

-- Policy: Circle members with Contributor+ role can upload videos
CREATE POLICY "Circle members can upload videos" ON storage.objects
    FOR INSERT
    WITH CHECK (
        bucket_id = 'video-messages'
        AND auth.uid() IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM circle_members cm
            WHERE cm.user_id = auth.uid()
              AND cm.status = 'ACTIVE'
              AND cm.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
              AND cm.circle_id::text = split_part(name, '/', 1)
        )
        -- Validate file path format: circleId/videoId.mp4 or circleId/videoId_thumb.jpg
        AND name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(_thumb)?\.(mp4|jpg)$'
    );

-- Policy: Video owner can delete within 24 hours
CREATE POLICY "Video owner can delete own videos" ON storage.objects
    FOR DELETE
    USING (
        bucket_id = 'video-messages'
        AND auth.uid() IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM video_messages vm
            WHERE vm.storage_key = name
              AND vm.created_by = auth.uid()
              AND vm.created_at > now() - interval '24 hours'
        )
    );

-- Policy: Admins/Owners can delete any video in their circle
CREATE POLICY "Admins can delete any video" ON storage.objects
    FOR DELETE
    USING (
        bucket_id = 'video-messages'
        AND auth.uid() IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM circle_members cm
            WHERE cm.user_id = auth.uid()
              AND cm.status = 'ACTIVE'
              AND cm.role IN ('OWNER', 'ADMIN')
              AND cm.circle_id::text = split_part(name, '/', 1)
        )
    );

-- ============================================================================
-- Add audit logging for video operations
-- ============================================================================

CREATE TABLE IF NOT EXISTS video_audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id uuid REFERENCES video_messages(id) ON DELETE SET NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL CHECK (action IN ('CREATE', 'VIEW', 'REACT', 'FLAG', 'DELETE', 'MODERATE')),
    details jsonb DEFAULT '{}',
    ip_address inet,
    user_agent text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for efficient querying
CREATE INDEX IF NOT EXISTS idx_video_audit_log_video_id ON video_audit_log(video_id);
CREATE INDEX IF NOT EXISTS idx_video_audit_log_user_id ON video_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_video_audit_log_created_at ON video_audit_log(created_at);

-- Enable RLS on audit log
ALTER TABLE video_audit_log ENABLE ROW LEVEL SECURITY;

-- Only service role can access audit log
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role only for audit' AND tablename = 'video_audit_log') THEN
        CREATE POLICY "Service role only for audit" ON video_audit_log
            FOR ALL USING (false);
    END IF;
END $$;

-- ============================================================================
-- Function to log video actions (called by Edge Functions)
-- ============================================================================

CREATE OR REPLACE FUNCTION log_video_action(
    p_video_id uuid,
    p_user_id uuid,
    p_action text,
    p_details jsonb DEFAULT '{}',
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS void AS $$
BEGIN
    -- Validate action
    IF p_action NOT IN ('CREATE', 'VIEW', 'REACT', 'FLAG', 'DELETE', 'MODERATE') THEN
        RAISE EXCEPTION 'Invalid action: %', p_action;
    END IF;

    INSERT INTO video_audit_log (video_id, user_id, action, details, ip_address, user_agent)
    VALUES (p_video_id, p_user_id, p_action, p_details, p_ip_address, p_user_agent);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Fix SECURITY DEFINER functions to validate auth.uid()
-- ============================================================================

-- Update check_rate_limit to validate caller
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
    -- Security check: user can only check their own rate limit OR service role
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot check rate limit for other users';
    END IF;

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

-- Update check_video_quota to validate caller
CREATE OR REPLACE FUNCTION check_video_quota(
    p_user_id uuid,
    p_circle_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_plan text;
    v_feature_locked boolean;
    v_limit_bytes bigint;
    v_used_bytes bigint;
    v_max_duration int;
    v_retention_days int;
BEGIN
    -- Security check: user must be authenticated and either checking own quota or service role
    IF auth.uid() IS NULL THEN
        -- Allow service role (no auth.uid() means service role key)
        NULL;
    ELSIF auth.uid() != p_user_id THEN
        -- Verify caller is a member of the same circle (can check circle quota)
        IF NOT EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_id = p_circle_id
              AND user_id = auth.uid()
              AND status = 'ACTIVE'
        ) THEN
            RAISE EXCEPTION 'Unauthorized: not a member of this circle';
        END IF;
    END IF;

    -- Get user's subscription plan
    SELECT COALESCE(s.plan, 'FREE') INTO v_plan
    FROM subscriptions s
    WHERE s.user_id = p_user_id
      AND s.status = 'ACTIVE';

    IF v_plan IS NULL THEN
        v_plan := 'FREE';
    END IF;

    -- Check feature access
    v_feature_locked := v_plan = 'FREE';

    -- Set limits based on plan
    CASE v_plan
        WHEN 'FREE' THEN
            v_limit_bytes := 0;
            v_max_duration := 0;
            v_retention_days := 0;
        WHEN 'PLUS' THEN
            v_limit_bytes := 524288000; -- 500MB
            v_max_duration := 30;
            v_retention_days := 30;
        WHEN 'FAMILY' THEN
            v_limit_bytes := 2147483648; -- 2GB
            v_max_duration := 60;
            v_retention_days := 90;
        ELSE
            v_limit_bytes := 0;
            v_max_duration := 0;
            v_retention_days := 0;
    END CASE;

    -- Calculate used bytes for circle
    SELECT COALESCE(SUM(file_size_bytes), 0) INTO v_used_bytes
    FROM video_messages
    WHERE circle_id = p_circle_id
      AND status != 'DELETED';

    RETURN jsonb_build_object(
        'allowed', NOT v_feature_locked AND v_used_bytes < v_limit_bytes,
        'feature_locked', v_feature_locked,
        'plan', v_plan,
        'used_bytes', v_used_bytes,
        'limit_bytes', v_limit_bytes,
        'remaining_bytes', GREATEST(0, v_limit_bytes - v_used_bytes),
        'max_duration', v_max_duration,
        'retention_days', v_retention_days
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
