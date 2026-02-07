-- ============================================================================
-- Migration: Care Network Directory & Instant Sharing
-- Description: Tables and functions for care network exports and sharing
-- Date: 2026-02-12
-- ============================================================================

-- ============================================================================
-- TABLE: care_network_exports
-- ============================================================================

CREATE TABLE IF NOT EXISTS care_network_exports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Content
    included_types text[] NOT NULL,  -- MEDICAL, FACILITY, PHARMACY, HOME_CARE, EMERGENCY, INSURANCE
    content_snapshot_json jsonb NOT NULL,  -- Snapshot of provider data at export time
    provider_count int NOT NULL,

    -- PDF
    pdf_storage_key text,

    -- Share link (optional)
    share_link_id uuid REFERENCES share_links(id) ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_care_network_exports_circle
    ON care_network_exports(circle_id);
CREATE INDEX IF NOT EXISTS idx_care_network_exports_patient
    ON care_network_exports(patient_id);
CREATE INDEX IF NOT EXISTS idx_care_network_exports_created_at
    ON care_network_exports(created_at DESC);

COMMENT ON TABLE care_network_exports IS 'Exported care network directory snapshots for sharing';

-- ============================================================================
-- TABLE: provider_notes (Family tier feature)
-- ============================================================================

CREATE TABLE IF NOT EXISTS provider_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    binder_item_id uuid NOT NULL REFERENCES binder_items(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    note text NOT NULL,
    rating int CHECK (rating IS NULL OR (rating >= 1 AND rating <= 5)),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(binder_item_id, created_by)
);

CREATE INDEX IF NOT EXISTS idx_provider_notes_binder_item
    ON provider_notes(binder_item_id);

CREATE TRIGGER provider_notes_updated_at
    BEFORE UPDATE ON provider_notes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE provider_notes IS 'User notes and ratings for providers (Family tier)';

-- ============================================================================
-- ALTER share_links to support care_network type
-- ============================================================================

-- Update the CHECK constraint to include 'care_network'
ALTER TABLE share_links DROP CONSTRAINT IF EXISTS share_links_object_type_check;
ALTER TABLE share_links ADD CONSTRAINT share_links_object_type_check
    CHECK (object_type IN ('appointment_pack', 'emergency_card', 'care_summary', 'care_network'));

-- ============================================================================
-- FUNCTION: compose_care_network_content
-- Aggregates provider data from binder items for export
-- ============================================================================

CREATE OR REPLACE FUNCTION compose_care_network_content(
    p_circle_id uuid,
    p_patient_id uuid,
    p_included_types text[]
)
RETURNS jsonb AS $$
DECLARE
    v_content jsonb;
    v_providers jsonb;
    v_patient patients%ROWTYPE;
BEGIN
    -- Get patient info
    SELECT * INTO v_patient FROM patients WHERE id = p_patient_id;

    -- Aggregate binder items by provider category
    WITH categorized AS (
        SELECT
            bi.id,
            bi.title,
            bi.type,
            bi.content_json,
            bi.updated_at,
            CASE
                WHEN bi.type = 'CONTACT' AND bi.content_json->>'role' IN ('doctor', 'nurse', 'other') THEN 'MEDICAL'
                WHEN bi.type = 'FACILITY' THEN 'FACILITY'
                WHEN bi.type = 'CONTACT' AND bi.content_json->>'organization' ILIKE '%pharmacy%' THEN 'PHARMACY'
                WHEN bi.type = 'CONTACT' AND bi.content_json->>'role' IN ('social_worker') THEN 'HOME_CARE'
                WHEN bi.type = 'CONTACT' AND bi.content_json->>'role' = 'family' THEN 'EMERGENCY'
                WHEN bi.type = 'INSURANCE' THEN 'INSURANCE'
                ELSE 'OTHER'
            END as category
        FROM binder_items bi
        WHERE bi.circle_id = p_circle_id
          AND (bi.patient_id = p_patient_id OR bi.patient_id IS NULL)
          AND bi.is_active = true
          AND bi.type IN ('CONTACT', 'FACILITY', 'INSURANCE')
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c.id,
        'title', c.title,
        'type', c.type,
        'category', c.category,
        'content', c.content_json,
        'updated_at', c.updated_at
    ) ORDER BY c.category, c.title), '[]'::jsonb)
    INTO v_providers
    FROM categorized c
    WHERE c.category = ANY(p_included_types) OR 'ALL' = ANY(p_included_types);

    -- Compose content
    v_content := jsonb_build_object(
        'patient', jsonb_build_object(
            'id', v_patient.id,
            'name', v_patient.display_name,
            'initials', v_patient.initials
        ),
        'generated_at', now(),
        'providers', v_providers,
        'counts', jsonb_build_object(
            'total', jsonb_array_length(v_providers),
            'by_category', (
                SELECT jsonb_object_agg(category, cnt)
                FROM (
                    SELECT
                        p.value->>'category' as category,
                        count(*) as cnt
                    FROM jsonb_array_elements(v_providers) p
                    GROUP BY p.value->>'category'
                ) counts
            )
        )
    );

    RETURN v_content;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: create_care_network_export
-- Creates a new export record with content snapshot
-- ============================================================================

CREATE OR REPLACE FUNCTION create_care_network_export(
    p_circle_id uuid,
    p_patient_id uuid,
    p_user_id uuid,
    p_included_types text[],
    p_create_share_link boolean DEFAULT false,
    p_share_link_ttl_hours int DEFAULT 168  -- 7 days
)
RETURNS jsonb AS $$
DECLARE
    v_export_id uuid;
    v_content jsonb;
    v_provider_count int;
    v_share_link_result jsonb;
    v_share_link_id uuid;
BEGIN
    -- Check membership
    IF NOT is_circle_member(p_circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;

    -- Compose content
    v_content := compose_care_network_content(p_circle_id, p_patient_id, p_included_types);
    v_provider_count := (v_content->'counts'->>'total')::int;

    IF v_provider_count = 0 THEN
        RETURN jsonb_build_object('error', 'No providers found to export');
    END IF;

    -- Create export record
    INSERT INTO care_network_exports (
        circle_id,
        patient_id,
        created_by,
        included_types,
        content_snapshot_json,
        provider_count
    ) VALUES (
        p_circle_id,
        p_patient_id,
        p_user_id,
        p_included_types,
        v_content,
        v_provider_count
    )
    RETURNING id INTO v_export_id;

    -- Create share link if requested
    IF p_create_share_link THEN
        v_share_link_result := create_share_link(
            p_circle_id,
            p_user_id,
            'care_network',
            v_export_id,
            p_share_link_ttl_hours
        );

        IF v_share_link_result ? 'error' THEN
            RETURN v_share_link_result;
        END IF;

        v_share_link_id := (v_share_link_result->>'link_id')::uuid;

        -- Update export with share link reference
        UPDATE care_network_exports
        SET share_link_id = v_share_link_id
        WHERE id = v_export_id;
    END IF;

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        p_circle_id,
        p_user_id,
        'CARE_NETWORK_EXPORTED',
        'care_network_export',
        v_export_id,
        jsonb_build_object(
            'patient_id', p_patient_id,
            'included_types', p_included_types,
            'provider_count', v_provider_count,
            'share_link_created', p_create_share_link
        )
    );

    RETURN jsonb_build_object(
        'export_id', v_export_id,
        'content', v_content,
        'share_link', v_share_link_result
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE care_network_exports ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_notes ENABLE ROW LEVEL SECURITY;

-- care_network_exports: Circle members can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'care_network_exports_select') THEN
        CREATE POLICY care_network_exports_select ON care_network_exports
            FOR SELECT USING (is_circle_member(circle_id, auth.uid()));
    END IF;
END $$;

-- care_network_exports: Contributors+ can create
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'care_network_exports_insert') THEN
        CREATE POLICY care_network_exports_insert ON care_network_exports
            FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
    END IF;
END $$;

-- provider_notes: Circle members can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'provider_notes_select') THEN
        CREATE POLICY provider_notes_select ON provider_notes
            FOR SELECT USING (is_circle_member(circle_id, auth.uid()));
    END IF;
END $$;

-- provider_notes: Contributors+ can create/update their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'provider_notes_insert') THEN
        CREATE POLICY provider_notes_insert ON provider_notes
            FOR INSERT WITH CHECK (
                has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR')
                AND created_by = auth.uid()
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'provider_notes_update') THEN
        CREATE POLICY provider_notes_update ON provider_notes
            FOR UPDATE USING (created_by = auth.uid());
    END IF;
END $$;

-- ============================================================================
-- UPDATE plan_limits for care_directory feature
-- ============================================================================

UPDATE plan_limits
SET features_json = features_json || '["care_directory_export", "care_directory_share"]'::jsonb
WHERE plan IN ('PLUS', 'FAMILY')
  AND NOT features_json ? 'care_directory_export';

UPDATE plan_limits
SET features_json = features_json || '["care_directory_notes", "care_directory_ratings"]'::jsonb
WHERE plan = 'FAMILY'
  AND NOT features_json ? 'care_directory_notes';
