-- Migration: 0012_shifts
-- Description: Shift Handoff Mode - coverage scheduling and shift summaries
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: care_shifts
-- ============================================================================

CREATE TABLE care_shifts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    owner_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    start_at timestamptz NOT NULL,
    end_at timestamptz NOT NULL,
    status text DEFAULT 'SCHEDULED' NOT NULL CHECK (status IN ('SCHEDULED', 'ACTIVE', 'COMPLETED', 'CANCELED')),
    checklist_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    summary_handoff_id uuid REFERENCES handoffs(id) ON DELETE SET NULL,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT care_shifts_valid_range CHECK (end_at > start_at)
);

CREATE INDEX care_shifts_circle_id_idx ON care_shifts(circle_id);
CREATE INDEX care_shifts_patient_id_idx ON care_shifts(patient_id);
CREATE INDEX care_shifts_owner_idx ON care_shifts(owner_user_id);
CREATE INDEX care_shifts_status_idx ON care_shifts(status);
CREATE INDEX care_shifts_start_at_idx ON care_shifts(start_at);
CREATE INDEX care_shifts_active_idx ON care_shifts(status, start_at, end_at) 
    WHERE status IN ('SCHEDULED', 'ACTIVE');

CREATE TRIGGER care_shifts_updated_at
    BEFORE UPDATE ON care_shifts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE care_shifts IS 'Care coverage shifts for multi-caregiver coordination';

-- ============================================================================
-- TABLE: shift_checklist_templates
-- ============================================================================

CREATE TABLE shift_checklist_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE CASCADE,
    name text NOT NULL,
    items_json jsonb NOT NULL DEFAULT '[]'::jsonb,
    is_default boolean DEFAULT false NOT NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX shift_checklist_templates_circle_idx ON shift_checklist_templates(circle_id);
CREATE INDEX shift_checklist_templates_patient_idx ON shift_checklist_templates(patient_id) WHERE patient_id IS NOT NULL;

CREATE TRIGGER shift_checklist_templates_updated_at
    BEFORE UPDATE ON shift_checklist_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE shift_checklist_templates IS 'Reusable checklist templates for shifts';

-- ============================================================================
-- FUNCTION: get_current_shift
-- ============================================================================

CREATE OR REPLACE FUNCTION get_current_shift(
    p_circle_id uuid,
    p_patient_id uuid,
    p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_shift care_shifts%ROWTYPE;
BEGIN
    -- Check membership
    IF NOT is_circle_member(p_circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;
    
    -- Find active or upcoming shift for this user
    SELECT * INTO v_shift
    FROM care_shifts
    WHERE circle_id = p_circle_id
      AND patient_id = p_patient_id
      AND owner_user_id = p_user_id
      AND status IN ('SCHEDULED', 'ACTIVE')
      AND start_at <= now() + interval '1 hour'
      AND end_at > now()
    ORDER BY start_at
    LIMIT 1;
    
    IF v_shift IS NULL THEN
        RETURN jsonb_build_object('has_shift', false);
    END IF;
    
    RETURN jsonb_build_object(
        'has_shift', true,
        'shift', row_to_json(v_shift)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: compute_shift_changes
-- ============================================================================

CREATE OR REPLACE FUNCTION compute_shift_changes(
    p_shift_id uuid,
    p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_shift care_shifts%ROWTYPE;
    v_prev_shift care_shifts%ROWTYPE;
    v_changes jsonb;
    v_handoffs jsonb;
    v_tasks jsonb;
    v_med_changes jsonb;
BEGIN
    -- Get current shift
    SELECT * INTO v_shift FROM care_shifts WHERE id = p_shift_id;
    IF v_shift IS NULL THEN
        RETURN jsonb_build_object('error', 'Shift not found');
    END IF;
    
    -- Check membership
    IF NOT is_circle_member(v_shift.circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;
    
    -- Find previous completed shift
    SELECT * INTO v_prev_shift
    FROM care_shifts
    WHERE circle_id = v_shift.circle_id
      AND patient_id = v_shift.patient_id
      AND status = 'COMPLETED'
      AND end_at < v_shift.start_at
    ORDER BY end_at DESC
    LIMIT 1;
    
    -- Compute since time (previous shift end or 24 hours ago)
    DECLARE
        v_since timestamptz := COALESCE(v_prev_shift.end_at, now() - interval '24 hours');
    BEGIN
        -- Get handoffs since last shift
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', h.id,
            'type', h.type,
            'title', h.title,
            'summary', h.summary,
            'created_at', h.created_at,
            'created_by', u.display_name
        ) ORDER BY h.created_at DESC), '[]'::jsonb)
        INTO v_handoffs
        FROM handoffs h
        JOIN users u ON h.created_by = u.id
        WHERE h.circle_id = v_shift.circle_id
          AND h.patient_id = v_shift.patient_id
          AND h.status = 'PUBLISHED'
          AND h.created_at > v_since;
        
        -- Get new or updated tasks
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', t.id,
            'title', t.title,
            'status', t.status,
            'priority', t.priority,
            'due_at', t.due_at,
            'owner', u.display_name
        ) ORDER BY t.priority DESC, t.due_at), '[]'::jsonb)
        INTO v_tasks
        FROM tasks t
        JOIN users u ON t.owner_user_id = u.id
        WHERE t.circle_id = v_shift.circle_id
          AND t.patient_id = v_shift.patient_id
          AND (t.updated_at > v_since OR (t.status = 'OPEN' AND t.due_at < v_shift.end_at));
        
        -- Get medication changes
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'name', bi.title,
            'updated_at', bi.updated_at
        ) ORDER BY bi.updated_at DESC), '[]'::jsonb)
        INTO v_med_changes
        FROM binder_items bi
        WHERE bi.circle_id = v_shift.circle_id
          AND bi.patient_id = v_shift.patient_id
          AND bi.type = 'MED'
          AND bi.updated_at > v_since;
    END;
    
    RETURN jsonb_build_object(
        'shift_id', v_shift.id,
        'since', COALESCE(v_prev_shift.end_at, now() - interval '24 hours'),
        'previous_shift_owner', (
            SELECT display_name FROM users WHERE id = v_prev_shift.owner_user_id
        ),
        'handoffs', v_handoffs,
        'tasks', v_tasks,
        'med_changes', v_med_changes,
        'counts', jsonb_build_object(
            'handoffs', jsonb_array_length(v_handoffs),
            'tasks', jsonb_array_length(v_tasks),
            'med_changes', jsonb_array_length(v_med_changes)
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: finalize_shift
-- ============================================================================

CREATE OR REPLACE FUNCTION finalize_shift(
    p_shift_id uuid,
    p_user_id uuid,
    p_notes text DEFAULT NULL,
    p_create_handoff boolean DEFAULT true
)
RETURNS jsonb AS $$
DECLARE
    v_shift care_shifts%ROWTYPE;
    v_handoff_id uuid;
    v_checklist_summary text;
BEGIN
    -- Get shift
    SELECT * INTO v_shift FROM care_shifts WHERE id = p_shift_id;
    IF v_shift IS NULL THEN
        RETURN jsonb_build_object('error', 'Shift not found');
    END IF;
    
    -- Check ownership or admin
    IF v_shift.owner_user_id != p_user_id AND NOT has_circle_role(v_shift.circle_id, p_user_id, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Not authorized to finalize this shift');
    END IF;
    
    -- Check status
    IF v_shift.status NOT IN ('SCHEDULED', 'ACTIVE') THEN
        RETURN jsonb_build_object('error', 'Shift already finalized');
    END IF;
    
    -- Build checklist summary
    SELECT string_agg(
        CASE WHEN (item->>'completed')::boolean THEN '✓ ' ELSE '○ ' END || (item->>'text'),
        E'\n'
    )
    INTO v_checklist_summary
    FROM jsonb_array_elements(v_shift.checklist_json) AS item;
    
    -- Create handoff if requested
    IF p_create_handoff THEN
        INSERT INTO handoffs (
            circle_id,
            patient_id,
            created_by,
            type,
            title,
            summary,
            status
        ) VALUES (
            v_shift.circle_id,
            v_shift.patient_id,
            p_user_id,
            'OTHER',
            'Shift Summary: ' || to_char(v_shift.start_at, 'Mon DD HH24:MI') || ' - ' || to_char(v_shift.end_at, 'HH24:MI'),
            COALESCE(p_notes, '') || 
            CASE WHEN v_checklist_summary IS NOT NULL THEN E'\n\nChecklist:\n' || v_checklist_summary ELSE '' END,
            'DRAFT'
        )
        RETURNING id INTO v_handoff_id;
    END IF;
    
    -- Update shift status
    UPDATE care_shifts
    SET 
        status = 'COMPLETED',
        notes = COALESCE(p_notes, notes),
        summary_handoff_id = v_handoff_id,
        updated_at = now()
    WHERE id = p_shift_id;
    
    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_shift.circle_id,
        p_user_id,
        'SHIFT_COMPLETED',
        'care_shift',
        p_shift_id,
        jsonb_build_object('handoff_id', v_handoff_id)
    );
    
    RETURN jsonb_build_object(
        'shift_id', p_shift_id,
        'status', 'COMPLETED',
        'handoff_id', v_handoff_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE care_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_checklist_templates ENABLE ROW LEVEL SECURITY;

-- care_shifts: Circle members can read
CREATE POLICY care_shifts_select ON care_shifts
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- care_shifts: Contributors+ can create
CREATE POLICY care_shifts_insert ON care_shifts
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- care_shifts: Owner or admin can update
CREATE POLICY care_shifts_update ON care_shifts
    FOR UPDATE USING (
        owner_user_id = auth.uid() OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

-- care_shifts: Admin can delete
CREATE POLICY care_shifts_delete ON care_shifts
    FOR DELETE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- shift_checklist_templates: Circle members can read
CREATE POLICY shift_checklist_templates_select ON shift_checklist_templates
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- shift_checklist_templates: Contributors+ can manage
CREATE POLICY shift_checklist_templates_insert ON shift_checklist_templates
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

CREATE POLICY shift_checklist_templates_update ON shift_checklist_templates
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
