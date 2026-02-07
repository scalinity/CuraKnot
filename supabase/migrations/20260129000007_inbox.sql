-- Migration: 0007_inbox
-- Description: Care Inbox - quick capture and triage
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: inbox_items
-- ============================================================================

CREATE TABLE inbox_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    kind text NOT NULL CHECK (kind IN ('PHOTO', 'PDF', 'AUDIO', 'TEXT')),
    status text DEFAULT 'NEW' NOT NULL CHECK (status IN ('NEW', 'ASSIGNED', 'TRIAGED', 'ARCHIVED')),
    assigned_to uuid REFERENCES users(id) ON DELETE SET NULL,
    title text,
    note text,
    attachment_id uuid REFERENCES attachments(id) ON DELETE SET NULL,
    text_payload text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX inbox_items_circle_id_idx ON inbox_items(circle_id);
CREATE INDEX inbox_items_status_idx ON inbox_items(status) WHERE status IN ('NEW', 'ASSIGNED');
CREATE INDEX inbox_items_assigned_to_idx ON inbox_items(assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX inbox_items_patient_id_idx ON inbox_items(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX inbox_items_created_at_idx ON inbox_items(created_at);
CREATE INDEX inbox_items_updated_at_idx ON inbox_items(updated_at);

CREATE TRIGGER inbox_items_updated_at
    BEFORE UPDATE ON inbox_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE inbox_items IS 'Quick capture items for later triage and routing';

-- ============================================================================
-- TABLE: inbox_triage_log
-- ============================================================================

CREATE TABLE inbox_triage_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inbox_item_id uuid NOT NULL REFERENCES inbox_items(id) ON DELETE CASCADE,
    triaged_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    triaged_at timestamptz DEFAULT now() NOT NULL,
    destination_type text NOT NULL CHECK (destination_type IN ('HANDOFF', 'TASK', 'BINDER', 'ARCHIVE')),
    destination_id uuid,
    note text
);

CREATE INDEX inbox_triage_log_item_idx ON inbox_triage_log(inbox_item_id);

COMMENT ON TABLE inbox_triage_log IS 'Audit log for inbox item triage decisions';

-- ============================================================================
-- FUNCTION: triage_inbox_item
-- ============================================================================

CREATE OR REPLACE FUNCTION triage_inbox_item(
    p_item_id uuid,
    p_user_id uuid,
    p_destination_type text,
    p_destination_data jsonb DEFAULT NULL,
    p_note text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_item inbox_items%ROWTYPE;
    v_destination_id uuid;
    v_handoff_id uuid;
    v_task_id uuid;
    v_binder_item_id uuid;
BEGIN
    -- Get the inbox item
    SELECT * INTO v_item FROM inbox_items WHERE id = p_item_id;
    
    IF v_item IS NULL THEN
        RETURN jsonb_build_object('error', 'Item not found');
    END IF;
    
    -- Check if user is a member of the circle
    IF NOT is_circle_member(v_item.circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;
    
    -- Check if already triaged
    IF v_item.status = 'TRIAGED' THEN
        RETURN jsonb_build_object('error', 'Item already triaged');
    END IF;
    
    -- Handle based on destination type
    CASE p_destination_type
        WHEN 'HANDOFF' THEN
            -- Create a draft handoff
            INSERT INTO handoffs (
                circle_id,
                patient_id,
                created_by,
                type,
                title,
                summary,
                status
            ) VALUES (
                v_item.circle_id,
                COALESCE(v_item.patient_id, (p_destination_data->>'patient_id')::uuid),
                p_user_id,
                COALESCE(p_destination_data->>'type', 'OTHER'),
                COALESCE(v_item.title, 'Inbox Item'),
                COALESCE(v_item.note, v_item.text_payload, ''),
                'DRAFT'
            )
            RETURNING id INTO v_handoff_id;
            
            -- Link attachment if exists
            IF v_item.attachment_id IS NOT NULL THEN
                UPDATE attachments 
                SET handoff_id = v_handoff_id 
                WHERE id = v_item.attachment_id;
            END IF;
            
            v_destination_id := v_handoff_id;
            
        WHEN 'TASK' THEN
            -- Create a task
            INSERT INTO tasks (
                circle_id,
                patient_id,
                created_by,
                owner_user_id,
                title,
                description,
                due_at,
                priority
            ) VALUES (
                v_item.circle_id,
                v_item.patient_id,
                p_user_id,
                COALESCE((p_destination_data->>'owner_user_id')::uuid, p_user_id),
                COALESCE(v_item.title, 'From Inbox'),
                COALESCE(v_item.note, v_item.text_payload),
                (p_destination_data->>'due_at')::timestamptz,
                COALESCE(p_destination_data->>'priority', 'MED')
            )
            RETURNING id INTO v_task_id;
            
            v_destination_id := v_task_id;
            
        WHEN 'BINDER' THEN
            -- Create a binder item (document or note)
            INSERT INTO binder_items (
                circle_id,
                patient_id,
                type,
                title,
                content_json,
                created_by,
                updated_by
            ) VALUES (
                v_item.circle_id,
                v_item.patient_id,
                CASE 
                    WHEN v_item.kind IN ('PHOTO', 'PDF') THEN 'DOC'
                    ELSE 'NOTE'
                END,
                COALESCE(v_item.title, 'From Inbox'),
                jsonb_build_object(
                    'content', COALESCE(v_item.note, v_item.text_payload, ''),
                    'attachment_id', v_item.attachment_id,
                    'source', 'inbox'
                ),
                p_user_id,
                p_user_id
            )
            RETURNING id INTO v_binder_item_id;
            
            -- Link attachment
            IF v_item.attachment_id IS NOT NULL THEN
                UPDATE attachments 
                SET binder_item_id = v_binder_item_id 
                WHERE id = v_item.attachment_id;
            END IF;
            
            v_destination_id := v_binder_item_id;
            
        WHEN 'ARCHIVE' THEN
            -- Just archive, no destination
            v_destination_id := NULL;
            
        ELSE
            RETURN jsonb_build_object('error', 'Invalid destination type');
    END CASE;
    
    -- Update inbox item status
    UPDATE inbox_items
    SET 
        status = 'TRIAGED',
        updated_at = now()
    WHERE id = p_item_id;
    
    -- Create triage log
    INSERT INTO inbox_triage_log (
        inbox_item_id,
        triaged_by,
        destination_type,
        destination_id,
        note
    ) VALUES (
        p_item_id,
        p_user_id,
        p_destination_type,
        v_destination_id,
        p_note
    );
    
    -- Create audit event
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_item.circle_id,
        p_user_id,
        'INBOX_ITEM_TRIAGED',
        'inbox_item',
        p_item_id,
        jsonb_build_object(
            'destination_type', p_destination_type,
            'destination_id', v_destination_id
        )
    );
    
    RETURN jsonb_build_object(
        'item_id', p_item_id,
        'status', 'TRIAGED',
        'destination_type', p_destination_type,
        'destination_id', v_destination_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION triage_inbox_item IS 'Route an inbox item to handoff, task, binder, or archive';

-- ============================================================================
-- FUNCTION: assign_inbox_item
-- ============================================================================

CREATE OR REPLACE FUNCTION assign_inbox_item(
    p_item_id uuid,
    p_user_id uuid,
    p_assignee_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_item inbox_items%ROWTYPE;
BEGIN
    -- Get the inbox item
    SELECT * INTO v_item FROM inbox_items WHERE id = p_item_id;
    
    IF v_item IS NULL THEN
        RETURN jsonb_build_object('error', 'Item not found');
    END IF;
    
    -- Check if user is a member with at least contributor role
    IF NOT has_circle_role(v_item.circle_id, p_user_id, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;
    
    -- Check assignee is a member
    IF NOT is_circle_member(v_item.circle_id, p_assignee_id) THEN
        RETURN jsonb_build_object('error', 'Assignee is not a circle member');
    END IF;
    
    -- Update the item
    UPDATE inbox_items
    SET 
        assigned_to = p_assignee_id,
        status = 'ASSIGNED',
        updated_at = now()
    WHERE id = p_item_id;
    
    RETURN jsonb_build_object(
        'item_id', p_item_id,
        'status', 'ASSIGNED',
        'assigned_to', p_assignee_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION assign_inbox_item IS 'Assign an inbox item to a circle member for processing';

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE inbox_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inbox_triage_log ENABLE ROW LEVEL SECURITY;

-- inbox_items: Circle members can read
CREATE POLICY inbox_items_select ON inbox_items
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- inbox_items: Contributors+ can insert
CREATE POLICY inbox_items_insert ON inbox_items
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- inbox_items: Contributors+ can update
CREATE POLICY inbox_items_update ON inbox_items
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- inbox_items: Admin+ can delete
CREATE POLICY inbox_items_delete ON inbox_items
    FOR DELETE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- inbox_triage_log: Circle members can read
CREATE POLICY inbox_triage_log_select ON inbox_triage_log
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM inbox_items i 
            WHERE i.id = inbox_triage_log.inbox_item_id 
            AND is_circle_member(i.circle_id, auth.uid())
        )
    );
