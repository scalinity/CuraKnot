-- Migration: condition_photos
-- Description: Secure Condition Photo Tracking tables, RLS policies, RPC functions
-- Date: 2026-02-15

-- ============================================================================
-- TABLE: tracked_conditions
-- ============================================================================

CREATE TABLE IF NOT EXISTS tracked_conditions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Condition details
    condition_type text NOT NULL CHECK (condition_type IN ('WOUND', 'RASH', 'SWELLING', 'BRUISE', 'SURGICAL', 'OTHER')),
    body_location text NOT NULL,
    description text,
    start_date date NOT NULL,

    -- Status
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RESOLVED', 'ARCHIVED')),
    resolved_date date,
    resolution_notes text,

    -- Privacy (always enforced, not configurable)
    require_biometric boolean NOT NULL DEFAULT true,
    blur_thumbnails boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tracked_conditions_circle ON tracked_conditions(circle_id);
CREATE INDEX idx_tracked_conditions_patient ON tracked_conditions(patient_id);
CREATE INDEX idx_tracked_conditions_status ON tracked_conditions(circle_id, status);
CREATE INDEX idx_tracked_conditions_created_by ON tracked_conditions(created_by);

COMMENT ON TABLE tracked_conditions IS 'Visual conditions tracked with photos (wounds, rashes, swelling, etc.)';

-- ============================================================================
-- TABLE: condition_photos
-- ============================================================================

CREATE TABLE IF NOT EXISTS condition_photos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    condition_id uuid NOT NULL REFERENCES tracked_conditions(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Photo storage (private Supabase Storage bucket, signed URLs only)
    storage_key text UNIQUE NOT NULL,
    thumbnail_key text UNIQUE NOT NULL,

    -- Metadata
    captured_at timestamptz NOT NULL DEFAULT now(),
    notes text,
    annotations_json jsonb,
    lighting_quality text CHECK (lighting_quality IN ('GOOD', 'FAIR', 'POOR')),

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_condition_photos_condition ON condition_photos(condition_id, captured_at DESC);
CREATE INDEX idx_condition_photos_circle ON condition_photos(circle_id);
CREATE INDEX idx_condition_photos_created_by ON condition_photos(created_by);

COMMENT ON TABLE condition_photos IS 'Photos for tracked conditions, stored encrypted in private Storage bucket';

-- ============================================================================
-- TABLE: condition_share_photos (junction for share links)
-- ============================================================================

CREATE TABLE IF NOT EXISTS condition_share_photos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    share_link_id uuid NOT NULL REFERENCES share_links(id) ON DELETE CASCADE,
    condition_photo_id uuid NOT NULL REFERENCES condition_photos(id) ON DELETE CASCADE,
    include_annotations boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(share_link_id, condition_photo_id)
);

CREATE INDEX idx_condition_share_photos_link ON condition_share_photos(share_link_id);

COMMENT ON TABLE condition_share_photos IS 'Junction table linking share links to specific condition photos';

-- ============================================================================
-- TABLE: photo_access_log (audit trail for all photo access)
-- ============================================================================

CREATE TABLE IF NOT EXISTS photo_access_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    condition_photo_id uuid REFERENCES condition_photos(id) ON DELETE SET NULL,
    accessed_by uuid REFERENCES users(id) ON DELETE SET NULL,
    access_type text NOT NULL CHECK (access_type IN ('VIEW', 'DOWNLOAD', 'SHARE_VIEW', 'UPLOAD', 'DELETE', 'SCREENSHOT', 'COMPARE', 'SCREENSHOT_DETECTED')),
    ip_hash text,
    user_agent_hash text,
    metadata_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_photo_access_log_circle ON photo_access_log(circle_id);
CREATE INDEX idx_photo_access_log_photo ON photo_access_log(condition_photo_id);
CREATE INDEX idx_photo_access_log_created ON photo_access_log(created_at DESC);
CREATE INDEX idx_photo_access_log_user ON photo_access_log(accessed_by);

COMMENT ON TABLE photo_access_log IS 'Immutable audit log for condition photo access events';

-- ============================================================================
-- ALTER: share_links — expand object_type constraint, add max_access_count
-- ============================================================================

DO $$ BEGIN
    ALTER TABLE share_links DROP CONSTRAINT IF EXISTS share_links_object_type_check;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE share_links
    ADD CONSTRAINT share_links_object_type_check
    CHECK (object_type IN ('appointment_pack', 'emergency_card', 'care_summary', 'condition_photos'));

DO $$ BEGIN
    ALTER TABLE share_links ADD COLUMN IF NOT EXISTS max_access_count int DEFAULT NULL;
EXCEPTION
    WHEN duplicate_column THEN NULL;
END $$;

-- ============================================================================
-- RLS POLICIES: tracked_conditions
-- ============================================================================

ALTER TABLE tracked_conditions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tracked_conditions' AND policyname = 'Members can view circle conditions') THEN
        CREATE POLICY "Members can view circle conditions" ON tracked_conditions
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = tracked_conditions.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tracked_conditions' AND policyname = 'Contributors can create conditions') THEN
        CREATE POLICY "Contributors can create conditions" ON tracked_conditions
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = tracked_conditions.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
                AND created_by = auth.uid()
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tracked_conditions' AND policyname = 'Contributors can update conditions') THEN
        CREATE POLICY "Contributors can update conditions" ON tracked_conditions
            FOR UPDATE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = tracked_conditions.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tracked_conditions' AND policyname = 'Admins can delete conditions') THEN
        CREATE POLICY "Admins can delete conditions" ON tracked_conditions
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = tracked_conditions.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: condition_photos
-- ============================================================================

ALTER TABLE condition_photos ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'condition_photos' AND policyname = 'Members can view circle photos') THEN
        CREATE POLICY "Members can view circle photos" ON condition_photos
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = condition_photos.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'condition_photos' AND policyname = 'Contributors can upload photos') THEN
        CREATE POLICY "Contributors can upload photos" ON condition_photos
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = condition_photos.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
                AND created_by = auth.uid()
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'condition_photos' AND policyname = 'Admins can delete photos') THEN
        CREATE POLICY "Admins can delete photos" ON condition_photos
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = condition_photos.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: condition_share_photos
-- ============================================================================

ALTER TABLE condition_share_photos ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'condition_share_photos' AND policyname = 'Members can view share photo links') THEN
        CREATE POLICY "Members can view share photo links" ON condition_share_photos
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM share_links
                    JOIN circle_members ON circle_members.circle_id = share_links.circle_id
                    WHERE share_links.id = condition_share_photos.share_link_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'condition_share_photos' AND policyname = 'Contributors can create share photo links') THEN
        CREATE POLICY "Contributors can create share photo links" ON condition_share_photos
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM share_links
                    JOIN circle_members ON circle_members.circle_id = share_links.circle_id
                    WHERE share_links.id = condition_share_photos.share_link_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: photo_access_log
-- ============================================================================

ALTER TABLE photo_access_log ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'photo_access_log' AND policyname = 'Authenticated users can insert access logs') THEN
        CREATE POLICY "Authenticated users can insert access logs" ON photo_access_log
            FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'photo_access_log' AND policyname = 'Admins can view access logs') THEN
        CREATE POLICY "Admins can view access logs" ON photo_access_log
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = photo_access_log.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- RPC: check_condition_limit
-- ============================================================================

CREATE OR REPLACE FUNCTION check_condition_limit(
    p_circle_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_plan text;
    v_active_count int;
    v_limit int;
BEGIN
    v_plan := get_user_plan(auth.uid());

    SELECT COUNT(*) INTO v_active_count
    FROM tracked_conditions
    WHERE circle_id = p_circle_id
      AND status = 'ACTIVE';

    CASE v_plan
        WHEN 'FREE' THEN
            RETURN jsonb_build_object(
                'allowed', false,
                'current', v_active_count,
                'limit', 0,
                'reason', 'Feature requires Plus or Family plan'
            );
        WHEN 'PLUS' THEN
            v_limit := 5;
        WHEN 'FAMILY' THEN
            RETURN jsonb_build_object(
                'allowed', true,
                'current', v_active_count,
                'limit', NULL,
                'unlimited', true
            );
        ELSE
            RETURN jsonb_build_object(
                'allowed', false,
                'current', v_active_count,
                'limit', 0,
                'reason', 'Unknown plan'
            );
    END CASE;

    RETURN jsonb_build_object(
        'allowed', v_active_count < v_limit,
        'current', v_active_count,
        'limit', v_limit,
        'unlimited', false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- UPDATE: plan_limits — add condition photo features
-- ============================================================================

UPDATE plan_limits
SET features_json = features_json || '["condition_photo_tracking"]'::jsonb,
    updated_at = now()
WHERE plan = 'PLUS'
  AND NOT (features_json ? 'condition_photo_tracking');

UPDATE plan_limits
SET features_json = features_json || '["condition_photo_tracking", "condition_photo_compare", "condition_photo_share"]'::jsonb,
    updated_at = now()
WHERE plan = 'FAMILY'
  AND NOT (features_json ? 'condition_photo_tracking');

-- ============================================================================
-- STORAGE: Create condition-photos bucket (private)
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'condition-photos',
    'condition-photos',
    false,
    10485760,  -- 10MB
    ARRAY['image/jpeg', 'image/png']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: Only circle members can upload/read via signed URLs
-- Path format: {circle_id}/{condition_id}/{photo_id}.jpg
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle members can upload condition photos') THEN
        CREATE POLICY "Circle members can upload condition photos" ON storage.objects
            FOR INSERT WITH CHECK (
                bucket_id = 'condition-photos'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 3
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = (string_to_array(name, '/'))[1]::uuid
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle members can read condition photos') THEN
        CREATE POLICY "Circle members can read condition photos" ON storage.objects
            FOR SELECT USING (
                bucket_id = 'condition-photos'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 3
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = (string_to_array(name, '/'))[1]::uuid
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle admins can delete condition photos') THEN
        CREATE POLICY "Circle admins can delete condition photos" ON storage.objects
            FOR DELETE USING (
                bucket_id = 'condition-photos'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 3
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = (string_to_array(name, '/'))[1]::uuid
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- TRIGGER: auto-update updated_at on tracked_conditions
-- ============================================================================

CREATE OR REPLACE FUNCTION update_tracked_conditions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tracked_conditions_updated_at ON tracked_conditions;
CREATE TRIGGER tracked_conditions_updated_at
    BEFORE UPDATE ON tracked_conditions
    FOR EACH ROW
    EXECUTE FUNCTION update_tracked_conditions_updated_at();
