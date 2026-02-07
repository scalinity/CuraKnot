-- Migration: 0004_binder
-- Description: binder_items, attachments tables
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: binder_items
-- ============================================================================

CREATE TABLE binder_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    type text NOT NULL CHECK (type IN ('MED', 'CONTACT', 'FACILITY', 'INSURANCE', 'DOC', 'NOTE')),
    title text NOT NULL,
    content_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    updated_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX binder_items_circle_id_idx ON binder_items(circle_id);
CREATE INDEX binder_items_type_idx ON binder_items(type);
CREATE INDEX binder_items_patient_id_idx ON binder_items(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX binder_items_is_active_idx ON binder_items(is_active) WHERE is_active = true;
CREATE INDEX binder_items_updated_at_idx ON binder_items(updated_at);

CREATE TRIGGER binder_items_updated_at
    BEFORE UPDATE ON binder_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE binder_items IS 'Reference items (meds, contacts, docs, etc)';

-- ============================================================================
-- TABLE: binder_item_revisions
-- ============================================================================

CREATE TABLE binder_item_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    binder_item_id uuid NOT NULL REFERENCES binder_items(id) ON DELETE CASCADE,
    revision int NOT NULL,
    content_json jsonb NOT NULL,
    edited_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    edited_at timestamptz DEFAULT now() NOT NULL,
    change_note text,
    
    CONSTRAINT binder_item_revisions_unique UNIQUE (binder_item_id, revision)
);

CREATE INDEX binder_item_revisions_item_id_idx ON binder_item_revisions(binder_item_id);

COMMENT ON TABLE binder_item_revisions IS 'Revision history for binder items';

-- ============================================================================
-- TABLE: attachments
-- ============================================================================

CREATE TABLE attachments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    uploader_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    handoff_id uuid REFERENCES handoffs(id) ON DELETE SET NULL,
    binder_item_id uuid REFERENCES binder_items(id) ON DELETE SET NULL,
    kind text NOT NULL CHECK (kind IN ('PHOTO', 'PDF', 'AUDIO')),
    mime_type text NOT NULL,
    byte_size int NOT NULL,
    sha256 text NOT NULL,
    storage_key text UNIQUE NOT NULL,
    filename text,
    created_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT attachments_has_parent CHECK (handoff_id IS NOT NULL OR binder_item_id IS NOT NULL)
);

CREATE INDEX attachments_circle_id_idx ON attachments(circle_id);
CREATE INDEX attachments_handoff_id_idx ON attachments(handoff_id) WHERE handoff_id IS NOT NULL;
CREATE INDEX attachments_binder_item_id_idx ON attachments(binder_item_id) WHERE binder_item_id IS NOT NULL;
CREATE INDEX attachments_storage_key_idx ON attachments(storage_key);

COMMENT ON TABLE attachments IS 'File attachments linked to handoffs or binder items';

-- ============================================================================
-- FUNCTION: create_binder_item_revision
-- ============================================================================

CREATE OR REPLACE FUNCTION create_binder_item_revision()
RETURNS TRIGGER AS $$
DECLARE
    v_revision int;
BEGIN
    -- Only create revision if content_json changed
    IF OLD.content_json IS DISTINCT FROM NEW.content_json THEN
        -- Get next revision number
        SELECT COALESCE(MAX(revision), 0) + 1 INTO v_revision
        FROM binder_item_revisions
        WHERE binder_item_id = NEW.id;
        
        -- Create revision record
        INSERT INTO binder_item_revisions (binder_item_id, revision, content_json, edited_by)
        VALUES (NEW.id, v_revision, OLD.content_json, NEW.updated_by);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER binder_items_revision_trigger
    BEFORE UPDATE ON binder_items
    FOR EACH ROW
    EXECUTE FUNCTION create_binder_item_revision();

-- ============================================================================
-- CONTENT JSON SCHEMAS (as comments for reference)
-- ============================================================================

COMMENT ON COLUMN binder_items.content_json IS 'Type-specific content. Schemas:

MED: {
  "name": "string",
  "dose": "string",
  "schedule": "string",
  "purpose": "string",
  "prescriber": "string",
  "start_date": "date",
  "stop_date": "date | null",
  "pharmacy": "string | null",
  "notes": "string | null"
}

CONTACT: {
  "name": "string",
  "role": "string (doctor, nurse, social_worker, family, other)",
  "phone": "string | null",
  "email": "string | null",
  "organization": "string | null",
  "address": "string | null",
  "notes": "string | null"
}

FACILITY: {
  "name": "string",
  "type": "string (hospital, nursing_home, rehab, other)",
  "address": "string",
  "phone": "string | null",
  "unit_room": "string | null",
  "visiting_hours": "string | null",
  "notes": "string | null"
}

INSURANCE: {
  "provider": "string",
  "plan_name": "string",
  "member_id": "string",
  "group_number": "string | null",
  "phone": "string | null",
  "notes": "string | null"
}

DOC: {
  "description": "string | null",
  "document_type": "string (medical_record, insurance, legal, other)",
  "date": "date | null",
  "attachment_id": "uuid"
}

NOTE: {
  "content": "string"
}
';
