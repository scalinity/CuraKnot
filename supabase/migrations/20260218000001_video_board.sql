-- ============================================================================
-- Migration: Family Video Message Board
-- Description: Video messages for emotional connection within care circles
-- ============================================================================

-- ============================================================================
-- TABLE: video_messages
-- ============================================================================

CREATE TABLE IF NOT EXISTS video_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Video storage
    storage_key text NOT NULL,
    thumbnail_key text,
    duration_seconds int NOT NULL CHECK (duration_seconds > 0 AND duration_seconds <= 60),
    file_size_bytes bigint NOT NULL CHECK (file_size_bytes > 0),

    -- Content
    caption text CHECK (char_length(caption) <= 300),

    -- Status
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('UPLOADING', 'PROCESSING', 'ACTIVE', 'FLAGGED', 'REMOVED', 'DELETED')),
    flagged_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    flagged_at timestamptz,
    removed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    removed_at timestamptz,
    removal_reason text CHECK (char_length(removal_reason) <= 500),

    -- Retention
    save_forever boolean NOT NULL DEFAULT false,
    expires_at timestamptz,
    retention_days int NOT NULL DEFAULT 30 CHECK (retention_days IN (30, 90)),

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,

    -- Constraints for data consistency
    CONSTRAINT video_messages_flagged_consistency CHECK (
        (status = 'FLAGGED' AND flagged_by IS NOT NULL AND flagged_at IS NOT NULL) OR
        (status != 'FLAGGED')
    ),
    CONSTRAINT video_messages_removed_consistency CHECK (
        (status = 'REMOVED' AND removed_by IS NOT NULL AND removed_at IS NOT NULL) OR
        (status != 'REMOVED')
    ),
    CONSTRAINT video_messages_save_forever_consistency CHECK (
        (save_forever = true AND expires_at IS NULL) OR
        (save_forever = false)
    )
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_video_messages_patient
    ON video_messages(patient_id, created_at DESC)
    WHERE status IN ('ACTIVE', 'FLAGGED');

CREATE INDEX IF NOT EXISTS idx_video_messages_circle
    ON video_messages(circle_id, created_at DESC)
    WHERE status IN ('ACTIVE', 'FLAGGED');

CREATE INDEX IF NOT EXISTS idx_video_messages_expires
    ON video_messages(expires_at)
    WHERE expires_at IS NOT NULL AND status = 'ACTIVE' AND save_forever = false;

CREATE INDEX IF NOT EXISTS idx_video_messages_creator
    ON video_messages(created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_video_messages_status
    ON video_messages(status);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_video_messages_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS video_messages_updated_at ON video_messages;
CREATE TRIGGER video_messages_updated_at
    BEFORE UPDATE ON video_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_video_messages_updated_at();

-- ============================================================================
-- TABLE: video_reactions
-- ============================================================================

CREATE TABLE IF NOT EXISTS video_reactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    video_message_id uuid NOT NULL REFERENCES video_messages(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reaction_type text NOT NULL DEFAULT 'LOVE' CHECK (reaction_type IN ('LOVE')),
    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(video_message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_video_reactions_video
    ON video_reactions(video_message_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_video_reactions_user
    ON video_reactions(user_id, created_at DESC);

-- ============================================================================
-- TABLE: video_views
-- ============================================================================

CREATE TABLE IF NOT EXISTS video_views (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    video_message_id uuid NOT NULL REFERENCES video_messages(id) ON DELETE CASCADE,
    viewed_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    viewed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_video_views_video
    ON video_views(video_message_id, viewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_video_views_user
    ON video_views(viewed_by, viewed_at DESC);

-- Note: Daily uniqueness enforced at application level to avoid IMMUTABLE function issues

-- ============================================================================
-- MATERIALIZED VIEW: circle_video_stats (for quota tracking)
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS circle_video_stats AS
SELECT
    circle_id,
    COUNT(*) as total_videos,
    SUM(file_size_bytes) as total_storage_bytes,
    MAX(created_at) as last_video_at
FROM video_messages
WHERE status IN ('ACTIVE', 'FLAGGED', 'PROCESSING', 'UPLOADING')
GROUP BY circle_id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_circle_video_stats_circle
    ON circle_video_stats(circle_id);

-- Function to refresh stats (call after video inserts/deletes)
CREATE OR REPLACE FUNCTION refresh_circle_video_stats()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY circle_video_stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Get video quota for a circle based on subscription plan
-- ============================================================================

CREATE OR REPLACE FUNCTION get_video_quota_bytes(p_plan text)
RETURNS bigint AS $$
BEGIN
    CASE p_plan
        WHEN 'FREE' THEN RETURN 0;  -- No video access
        WHEN 'PLUS' THEN RETURN 524288000;  -- 500 MB
        WHEN 'FAMILY' THEN RETURN 2147483648;  -- 2 GB
        ELSE RETURN 0;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FUNCTION: Get max video duration for subscription plan
-- ============================================================================

CREATE OR REPLACE FUNCTION get_video_max_duration(p_plan text)
RETURNS int AS $$
BEGIN
    CASE p_plan
        WHEN 'FREE' THEN RETURN 0;  -- No video access
        WHEN 'PLUS' THEN RETURN 30;  -- 30 seconds
        WHEN 'FAMILY' THEN RETURN 60;  -- 60 seconds
        ELSE RETURN 0;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FUNCTION: Get retention days for subscription plan
-- ============================================================================

CREATE OR REPLACE FUNCTION get_video_retention_days(p_plan text)
RETURNS int AS $$
BEGIN
    CASE p_plan
        WHEN 'FREE' THEN RETURN 0;  -- No video access
        WHEN 'PLUS' THEN RETURN 30;  -- 30 days
        WHEN 'FAMILY' THEN RETURN 90;  -- 90 days
        ELSE RETURN 0;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FUNCTION: Check video quota for a circle
-- ============================================================================

CREATE OR REPLACE FUNCTION check_video_quota(
    p_user_id uuid,
    p_circle_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_plan text;
    v_limit_bytes bigint;
    v_used_bytes bigint;
BEGIN
    -- Get user's plan
    v_plan := get_user_plan(p_user_id);
    v_limit_bytes := get_video_quota_bytes(v_plan);

    -- Feature not available for FREE
    IF v_plan = 'FREE' THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'feature_locked', true,
            'plan', v_plan,
            'used_bytes', 0,
            'limit_bytes', 0,
            'remaining_bytes', 0
        );
    END IF;

    -- Get current usage from materialized view
    SELECT COALESCE(total_storage_bytes, 0) INTO v_used_bytes
    FROM circle_video_stats
    WHERE circle_id = p_circle_id;

    IF v_used_bytes IS NULL THEN
        v_used_bytes := 0;
    END IF;

    RETURN jsonb_build_object(
        'allowed', v_used_bytes < v_limit_bytes,
        'feature_locked', false,
        'plan', v_plan,
        'used_bytes', v_used_bytes,
        'limit_bytes', v_limit_bytes,
        'remaining_bytes', GREATEST(0, v_limit_bytes - v_used_bytes),
        'max_duration', get_video_max_duration(v_plan),
        'retention_days', get_video_retention_days(v_plan)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE video_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_views ENABLE ROW LEVEL SECURITY;

-- video_messages policies

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members can read active videos') THEN
        CREATE POLICY "Members can read active videos" ON video_messages
            FOR SELECT USING (
                status IN ('ACTIVE', 'FLAGGED') AND
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = video_messages.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors can create videos') THEN
        CREATE POLICY "Contributors can create videos" ON video_messages
            FOR INSERT WITH CHECK (
                created_by = auth.uid() AND
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = video_messages.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Creator can update own video admins can moderate') THEN
        CREATE POLICY "Creator can update own video admins can moderate" ON video_messages
            FOR UPDATE USING (
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
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Creator can delete own admins can delete any') THEN
        CREATE POLICY "Creator can delete own admins can delete any" ON video_messages
            FOR DELETE USING (
                created_by = auth.uid() OR
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = video_messages.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

-- video_reactions policies

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members can read reactions') THEN
        CREATE POLICY "Members can read reactions" ON video_reactions
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM video_messages vm
                    INNER JOIN circle_members cm ON cm.circle_id = vm.circle_id
                    WHERE vm.id = video_reactions.video_message_id
                      AND cm.user_id = auth.uid()
                      AND cm.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members can create reactions') THEN
        CREATE POLICY "Members can create reactions" ON video_reactions
            FOR INSERT WITH CHECK (
                user_id = auth.uid() AND
                EXISTS (
                    SELECT 1 FROM video_messages vm
                    INNER JOIN circle_members cm ON cm.circle_id = vm.circle_id
                    WHERE vm.id = video_reactions.video_message_id
                      AND cm.user_id = auth.uid()
                      AND cm.status = 'ACTIVE'
                      AND vm.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can remove own reactions') THEN
        CREATE POLICY "Users can remove own reactions" ON video_reactions
            FOR DELETE USING (user_id = auth.uid());
    END IF;
END $$;

-- video_views policies

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can read own views') THEN
        CREATE POLICY "Users can read own views" ON video_views
            FOR SELECT USING (viewed_by = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can record own views') THEN
        CREATE POLICY "Users can record own views" ON video_views
            FOR INSERT WITH CHECK (
                viewed_by = auth.uid() AND
                EXISTS (
                    SELECT 1 FROM video_messages vm
                    INNER JOIN circle_members cm ON cm.circle_id = vm.circle_id
                    WHERE vm.id = video_views.video_message_id
                      AND cm.user_id = auth.uid()
                      AND cm.status = 'ACTIVE'
                      AND vm.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- ============================================================================
-- Update plan_limits with video feature flag
-- ============================================================================

UPDATE plan_limits
SET features_json = features_json || '["family_video_board"]'::jsonb
WHERE plan IN ('PLUS', 'FAMILY')
  AND NOT (features_json ? 'family_video_board');
