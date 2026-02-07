-- Migration: 0002_handoffs
-- Description: handoffs, handoff_revisions, read_receipts tables
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: handoffs
-- ============================================================================

CREATE TABLE handoffs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    type text NOT NULL CHECK (type IN ('VISIT', 'CALL', 'APPOINTMENT', 'FACILITY_UPDATE', 'OTHER')),
    title text NOT NULL CHECK (length(title) <= 80),
    summary text CHECK (summary IS NULL OR length(summary) <= 600),
    keywords text[] DEFAULT '{}',
    status text DEFAULT 'DRAFT' NOT NULL CHECK (status IN ('DRAFT', 'PUBLISHED')),
    published_at timestamptz,
    current_revision int DEFAULT 1 NOT NULL,
    raw_transcript text, -- Protected field
    audio_storage_key text,
    confidence_json jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX handoffs_circle_id_idx ON handoffs(circle_id);
CREATE INDEX handoffs_patient_id_idx ON handoffs(patient_id);
CREATE INDEX handoffs_created_by_idx ON handoffs(created_by);
CREATE INDEX handoffs_status_idx ON handoffs(status);
CREATE INDEX handoffs_published_at_idx ON handoffs(published_at DESC) WHERE published_at IS NOT NULL;
CREATE INDEX handoffs_updated_at_idx ON handoffs(updated_at);

-- Full-text search index
CREATE INDEX handoffs_fts_idx ON handoffs 
    USING GIN (to_tsvector('english', title || ' ' || COALESCE(summary, '')));

CREATE TRIGGER handoffs_updated_at
    BEFORE UPDATE ON handoffs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE handoffs IS 'Handoff records (structured briefs)';
COMMENT ON COLUMN handoffs.raw_transcript IS 'Protected field - access controlled by RLS';

-- ============================================================================
-- TABLE: handoff_revisions
-- ============================================================================

CREATE TABLE handoff_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    handoff_id uuid NOT NULL REFERENCES handoffs(id) ON DELETE CASCADE,
    revision int NOT NULL,
    structured_json jsonb NOT NULL,
    edited_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    edited_at timestamptz DEFAULT now() NOT NULL,
    change_note text,
    
    CONSTRAINT handoff_revisions_unique UNIQUE (handoff_id, revision)
);

CREATE INDEX handoff_revisions_handoff_id_idx ON handoff_revisions(handoff_id);

COMMENT ON TABLE handoff_revisions IS 'Immutable revision history for handoffs';

-- ============================================================================
-- TABLE: read_receipts
-- ============================================================================

CREATE TABLE read_receipts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    handoff_id uuid NOT NULL REFERENCES handoffs(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    read_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT read_receipts_unique UNIQUE (handoff_id, user_id)
);

CREATE INDEX read_receipts_user_id_idx ON read_receipts(user_id);
CREATE INDEX read_receipts_handoff_id_idx ON read_receipts(handoff_id);

COMMENT ON TABLE read_receipts IS 'Track which users have read which handoffs';

-- ============================================================================
-- FUNCTION: publish_handoff
-- ============================================================================

CREATE OR REPLACE FUNCTION publish_handoff(
    p_handoff_id uuid,
    p_structured_json jsonb,
    p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_handoff handoffs%ROWTYPE;
    v_revision int;
BEGIN
    -- Get the handoff
    SELECT * INTO v_handoff FROM handoffs WHERE id = p_handoff_id;
    
    IF v_handoff IS NULL THEN
        RETURN jsonb_build_object('error', 'Handoff not found');
    END IF;
    
    -- Check if user can publish
    IF NOT has_circle_role(v_handoff.circle_id, p_user_id, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Permission denied');
    END IF;
    
    -- Determine revision number
    IF v_handoff.status = 'DRAFT' THEN
        v_revision := 1;
    ELSE
        v_revision := v_handoff.current_revision + 1;
    END IF;
    
    -- Create revision record
    INSERT INTO handoff_revisions (handoff_id, revision, structured_json, edited_by)
    VALUES (p_handoff_id, v_revision, p_structured_json, p_user_id);
    
    -- Update handoff
    UPDATE handoffs
    SET 
        status = 'PUBLISHED',
        published_at = COALESCE(published_at, now()),
        current_revision = v_revision,
        title = COALESCE(p_structured_json->>'title', title),
        summary = p_structured_json->>'summary',
        keywords = COALESCE(
            ARRAY(SELECT jsonb_array_elements_text(p_structured_json->'keywords')),
            keywords
        ),
        updated_at = now()
    WHERE id = p_handoff_id;
    
    RETURN jsonb_build_object(
        'handoff_id', p_handoff_id,
        'revision', v_revision,
        'published_at', now()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION publish_handoff IS 'Publish a handoff, creating a revision record';
