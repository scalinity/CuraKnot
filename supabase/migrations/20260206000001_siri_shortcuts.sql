-- ============================================================================
-- Migration: Siri Shortcuts Integration
-- Description: Add source tracking to handoffs, patient aliases for voice recognition
-- Date: 2026-02-06
-- ============================================================================

-- ============================================================================
-- HANDOFFS: Add source tracking and Siri fields
-- ============================================================================

-- Add source column to track where handoffs originate
ALTER TABLE handoffs
ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'APP';

-- Add check constraint for valid sources
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'handoffs_source_check'
    ) THEN
        ALTER TABLE handoffs ADD CONSTRAINT handoffs_source_check
        CHECK (source IN ('APP', 'SIRI', 'WATCH', 'SHORTCUT', 'HELPER_PORTAL'));
    END IF;
END $$;

-- Add siri_raw_text column for preserving original Siri dictation
ALTER TABLE handoffs
ADD COLUMN IF NOT EXISTS siri_raw_text text;

-- Update status constraint to include SIRI_DRAFT
-- First drop the existing constraint, then add new one
ALTER TABLE handoffs DROP CONSTRAINT IF EXISTS handoffs_status_check;
ALTER TABLE handoffs ADD CONSTRAINT handoffs_status_check
CHECK (status IN ('DRAFT', 'SIRI_DRAFT', 'PUBLISHED'));

-- Index for filtering by source
CREATE INDEX IF NOT EXISTS idx_handoffs_source ON handoffs(source);

-- Index for finding Siri drafts that need review
CREATE INDEX IF NOT EXISTS idx_handoffs_siri_drafts
ON handoffs(created_by, status, created_at DESC)
WHERE status = 'SIRI_DRAFT';

COMMENT ON COLUMN handoffs.source IS 'Origin of handoff: APP, SIRI, WATCH, SHORTCUT, HELPER_PORTAL';
COMMENT ON COLUMN handoffs.siri_raw_text IS 'Original Siri dictation text before processing';

-- ============================================================================
-- TABLE: patient_aliases
-- Enables voice recognition disambiguation (e.g., "Mom" -> "Margaret Johnson")
-- ============================================================================

CREATE TABLE IF NOT EXISTS patient_aliases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    alias text NOT NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL
);

-- Case-insensitive unique constraint using a unique index on lowercase alias
-- This prevents both "Mom" and "mom" from being inserted for the same circle
-- This unique index also serves as the lookup index for fast alias resolution
CREATE UNIQUE INDEX IF NOT EXISTS idx_patient_aliases_unique_lower
ON patient_aliases(circle_id, LOWER(alias));

-- Index for finding all aliases for a patient
CREATE INDEX IF NOT EXISTS idx_patient_aliases_patient
ON patient_aliases(patient_id);

COMMENT ON TABLE patient_aliases IS 'Voice recognition aliases for patients (e.g., Mom, Grandma, Dad)';
COMMENT ON COLUMN patient_aliases.alias IS 'Alternative name used in voice commands';

-- ============================================================================
-- RLS POLICIES for patient_aliases
-- ============================================================================

ALTER TABLE patient_aliases ENABLE ROW LEVEL SECURITY;

-- Members can read aliases for their circles
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members read circle aliases') THEN
        CREATE POLICY "Members read circle aliases" ON patient_aliases
        FOR SELECT USING (is_circle_member(circle_id, auth.uid()));
    END IF;
END $$;

-- Contributors+ can create aliases
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create aliases') THEN
        CREATE POLICY "Contributors create aliases" ON patient_aliases
        FOR INSERT WITH CHECK (
            has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR')
            AND created_by = auth.uid()
        );
    END IF;
END $$;

-- Contributors+ can update their own aliases, Admins+ can update any
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors update aliases') THEN
        CREATE POLICY "Contributors update aliases" ON patient_aliases
        FOR UPDATE USING (
            has_circle_role(circle_id, auth.uid(), 'ADMIN')
            OR (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR') AND created_by = auth.uid())
        );
    END IF;
END $$;

-- Contributors+ can delete their own aliases, Admins+ can delete any
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors delete aliases') THEN
        CREATE POLICY "Contributors delete aliases" ON patient_aliases
        FOR DELETE USING (
            has_circle_role(circle_id, auth.uid(), 'ADMIN')
            OR (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR') AND created_by = auth.uid())
        );
    END IF;
END $$;

-- ============================================================================
-- FUNCTION: resolve_patient_by_name
-- Fuzzy matching for Siri voice input
-- ============================================================================

CREATE OR REPLACE FUNCTION resolve_patient_by_name(
    p_circle_id uuid,
    p_name_query text
)
RETURNS TABLE (
    patient_id uuid,
    display_name text,
    match_type text,
    confidence numeric
) AS $$
DECLARE
    v_query_lower text := LOWER(TRIM(p_name_query));
BEGIN
    RETURN QUERY
    WITH matches AS (
        -- Exact alias match (highest confidence)
        SELECT
            pa.patient_id,
            p.display_name,
            'ALIAS_EXACT'::text as match_type,
            1.0::numeric as confidence
        FROM patient_aliases pa
        JOIN patients p ON p.id = pa.patient_id
        WHERE pa.circle_id = p_circle_id
          AND LOWER(pa.alias) = v_query_lower
          AND p.archived_at IS NULL

        UNION ALL

        -- Exact display name match
        SELECT
            p.id,
            p.display_name,
            'NAME_EXACT'::text,
            0.95::numeric
        FROM patients p
        WHERE p.circle_id = p_circle_id
          AND LOWER(p.display_name) = v_query_lower
          AND p.archived_at IS NULL

        UNION ALL

        -- First name match
        SELECT
            p.id,
            p.display_name,
            'FIRST_NAME'::text,
            0.8::numeric
        FROM patients p
        WHERE p.circle_id = p_circle_id
          AND LOWER(SPLIT_PART(p.display_name, ' ', 1)) = v_query_lower
          AND p.archived_at IS NULL

        UNION ALL

        -- Alias prefix match
        SELECT
            pa.patient_id,
            p.display_name,
            'ALIAS_PREFIX'::text,
            0.7::numeric
        FROM patient_aliases pa
        JOIN patients p ON p.id = pa.patient_id
        WHERE pa.circle_id = p_circle_id
          AND LOWER(pa.alias) LIKE v_query_lower || '%'
          AND LOWER(pa.alias) != v_query_lower  -- Exclude exact matches
          AND p.archived_at IS NULL

        UNION ALL

        -- Display name contains query
        SELECT
            p.id,
            p.display_name,
            'CONTAINS'::text,
            0.5::numeric
        FROM patients p
        WHERE p.circle_id = p_circle_id
          AND LOWER(p.display_name) LIKE '%' || v_query_lower || '%'
          AND LOWER(p.display_name) != v_query_lower  -- Exclude exact matches
          AND p.archived_at IS NULL
    )
    SELECT DISTINCT ON (m.patient_id)
        m.patient_id,
        m.display_name,
        m.match_type,
        m.confidence
    FROM matches m
    ORDER BY m.patient_id, m.confidence DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION resolve_patient_by_name IS 'Fuzzy match patient by name or alias for Siri voice input';

-- ============================================================================
-- FUNCTION: get_siri_drafts_pending_review
-- Returns Siri drafts for a user that need review
-- ============================================================================

CREATE OR REPLACE FUNCTION get_siri_drafts_pending_review(
    p_user_id uuid,
    p_max_age_days int DEFAULT 7
)
RETURNS SETOF handoffs
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT h.*
    FROM handoffs h
    JOIN circle_members cm ON cm.circle_id = h.circle_id
    WHERE cm.user_id = p_user_id
      AND cm.status = 'ACTIVE'
      AND h.status = 'SIRI_DRAFT'
      AND h.created_at > now() - (COALESCE(p_max_age_days, 7) || ' days')::interval
    ORDER BY h.created_at DESC;
$$;

COMMENT ON FUNCTION get_siri_drafts_pending_review IS 'Get pending Siri draft handoffs for review';

-- ============================================================================
-- Add siri_settings to users table
-- ============================================================================

-- Add Siri settings to user settings JSON
-- This allows users to configure default patient, etc.
COMMENT ON COLUMN users.settings_json IS 'User settings including siri: {defaultPatientId, confirmBeforePublish, voiceFeedbackEnabled}';
