-- Migration: 0011_med_reconciliation
-- Description: Medication Reconciliation - scan labels, OCR, verification workflow
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: med_scan_sessions
-- ============================================================================

CREATE TABLE med_scan_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status text DEFAULT 'PENDING' NOT NULL CHECK (status IN ('PENDING', 'PROCESSING', 'READY', 'FAILED')),
    source_object_keys text[] NOT NULL DEFAULT '{}',
    ocr_text text,  -- Protected field, not exposed to viewers
    error_message text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX med_scan_sessions_circle_id_idx ON med_scan_sessions(circle_id);
CREATE INDEX med_scan_sessions_patient_id_idx ON med_scan_sessions(patient_id);
CREATE INDEX med_scan_sessions_status_idx ON med_scan_sessions(status);
CREATE INDEX med_scan_sessions_created_at_idx ON med_scan_sessions(created_at);

CREATE TRIGGER med_scan_sessions_updated_at
    BEFORE UPDATE ON med_scan_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE med_scan_sessions IS 'OCR scanning sessions for medication reconciliation';

-- ============================================================================
-- TABLE: med_proposals
-- ============================================================================

CREATE TABLE med_proposals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES med_scan_sessions(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    proposed_json jsonb NOT NULL,  -- Parsed med fields + per-field confidence
    diff_json jsonb,  -- Computed diff against existing meds
    status text DEFAULT 'PROPOSED' NOT NULL CHECK (status IN ('PROPOSED', 'ACCEPTED', 'REJECTED', 'MERGED')),
    existing_med_id uuid REFERENCES binder_items(id) ON DELETE SET NULL,
    accepted_by uuid REFERENCES users(id) ON DELETE SET NULL,
    accepted_at timestamptz,
    rejected_by uuid REFERENCES users(id) ON DELETE SET NULL,
    rejected_at timestamptz,
    rejection_reason text,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX med_proposals_session_idx ON med_proposals(session_id);
CREATE INDEX med_proposals_status_idx ON med_proposals(status);
CREATE INDEX med_proposals_patient_idx ON med_proposals(patient_id);

COMMENT ON TABLE med_proposals IS 'Proposed medication entries from OCR with verification status';

-- ============================================================================
-- FUNCTION: process_med_scan_results
-- ============================================================================

CREATE OR REPLACE FUNCTION process_med_scan_results(
    p_session_id uuid,
    p_ocr_text text,
    p_parsed_meds jsonb
)
RETURNS jsonb AS $$
DECLARE
    v_session med_scan_sessions%ROWTYPE;
    v_med jsonb;
    v_existing_med binder_items%ROWTYPE;
    v_diff jsonb;
    v_proposal_id uuid;
    v_proposals_created int := 0;
BEGIN
    -- Get session
    SELECT * INTO v_session FROM med_scan_sessions WHERE id = p_session_id;
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('error', 'Session not found');
    END IF;
    
    -- Store OCR text (protected)
    UPDATE med_scan_sessions
    SET ocr_text = p_ocr_text, status = 'PROCESSING'
    WHERE id = p_session_id;
    
    -- Process each parsed medication
    FOR v_med IN SELECT * FROM jsonb_array_elements(p_parsed_meds)
    LOOP
        -- Check for existing medication match
        SELECT * INTO v_existing_med
        FROM binder_items
        WHERE circle_id = v_session.circle_id
          AND patient_id = v_session.patient_id
          AND type = 'MED'
          AND is_active = true
          AND (
              lower(title) = lower(v_med->>'name')
              OR lower(content_json->>'name') = lower(v_med->>'name')
          )
        LIMIT 1;
        
        -- Compute diff if existing found
        IF v_existing_med IS NOT NULL THEN
            v_diff := jsonb_build_object(
                'has_match', true,
                'existing_id', v_existing_med.id,
                'existing_title', v_existing_med.title,
                'dose_changed', v_existing_med.content_json->>'dose' IS DISTINCT FROM v_med->>'dose',
                'schedule_changed', v_existing_med.content_json->>'schedule' IS DISTINCT FROM v_med->>'schedule'
            );
        ELSE
            v_diff := jsonb_build_object('has_match', false, 'is_new', true);
        END IF;
        
        -- Create proposal
        INSERT INTO med_proposals (
            session_id,
            circle_id,
            patient_id,
            proposed_json,
            diff_json,
            existing_med_id
        ) VALUES (
            p_session_id,
            v_session.circle_id,
            v_session.patient_id,
            v_med,
            v_diff,
            v_existing_med.id
        )
        RETURNING id INTO v_proposal_id;
        
        v_proposals_created := v_proposals_created + 1;
    END LOOP;
    
    -- Update session status
    UPDATE med_scan_sessions
    SET status = 'READY'
    WHERE id = p_session_id;
    
    RETURN jsonb_build_object(
        'session_id', p_session_id,
        'proposals_created', v_proposals_created,
        'status', 'READY'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: accept_med_proposal
-- ============================================================================

CREATE OR REPLACE FUNCTION accept_med_proposal(
    p_proposal_id uuid,
    p_user_id uuid,
    p_modified_json jsonb DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_proposal med_proposals%ROWTYPE;
    v_final_data jsonb;
    v_binder_item_id uuid;
    v_handoff_id uuid;
BEGIN
    -- Get proposal
    SELECT * INTO v_proposal FROM med_proposals WHERE id = p_proposal_id;
    IF v_proposal IS NULL THEN
        RETURN jsonb_build_object('error', 'Proposal not found');
    END IF;
    
    IF v_proposal.status != 'PROPOSED' THEN
        RETURN jsonb_build_object('error', 'Proposal already processed');
    END IF;
    
    -- Check permissions
    IF NOT has_circle_role(v_proposal.circle_id, p_user_id, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;
    
    -- Use modified data if provided, otherwise use original
    v_final_data := COALESCE(p_modified_json, v_proposal.proposed_json);
    
    IF v_proposal.existing_med_id IS NOT NULL THEN
        -- Update existing medication
        UPDATE binder_items
        SET 
            content_json = content_json || v_final_data,
            updated_by = p_user_id,
            updated_at = now()
        WHERE id = v_proposal.existing_med_id;
        
        v_binder_item_id := v_proposal.existing_med_id;
    ELSE
        -- Create new medication
        INSERT INTO binder_items (
            circle_id,
            patient_id,
            type,
            title,
            content_json,
            created_by,
            updated_by
        ) VALUES (
            v_proposal.circle_id,
            v_proposal.patient_id,
            'MED',
            COALESCE(v_final_data->>'name', 'Unknown Medication'),
            v_final_data || jsonb_build_object(
                'source', 'reconciliation',
                'verified_at', now(),
                'verified_by', p_user_id
            ),
            p_user_id,
            p_user_id
        )
        RETURNING id INTO v_binder_item_id;
    END IF;
    
    -- Update proposal status
    UPDATE med_proposals
    SET 
        status = 'ACCEPTED',
        accepted_by = p_user_id,
        accepted_at = now()
    WHERE id = p_proposal_id;
    
    -- Create audit event
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_proposal.circle_id,
        p_user_id,
        'MED_PROPOSAL_ACCEPTED',
        'med_proposal',
        p_proposal_id,
        jsonb_build_object(
            'binder_item_id', v_binder_item_id,
            'was_update', v_proposal.existing_med_id IS NOT NULL
        )
    );
    
    RETURN jsonb_build_object(
        'proposal_id', p_proposal_id,
        'binder_item_id', v_binder_item_id,
        'status', 'ACCEPTED'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: reject_med_proposal
-- ============================================================================

CREATE OR REPLACE FUNCTION reject_med_proposal(
    p_proposal_id uuid,
    p_user_id uuid,
    p_reason text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_proposal med_proposals%ROWTYPE;
BEGIN
    -- Get proposal
    SELECT * INTO v_proposal FROM med_proposals WHERE id = p_proposal_id;
    IF v_proposal IS NULL THEN
        RETURN jsonb_build_object('error', 'Proposal not found');
    END IF;
    
    IF v_proposal.status != 'PROPOSED' THEN
        RETURN jsonb_build_object('error', 'Proposal already processed');
    END IF;
    
    -- Check permissions
    IF NOT has_circle_role(v_proposal.circle_id, p_user_id, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;
    
    -- Update proposal status
    UPDATE med_proposals
    SET 
        status = 'REJECTED',
        rejected_by = p_user_id,
        rejected_at = now(),
        rejection_reason = p_reason
    WHERE id = p_proposal_id;
    
    RETURN jsonb_build_object(
        'proposal_id', p_proposal_id,
        'status', 'REJECTED'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- VIEW: med_proposals_with_details
-- ============================================================================

CREATE OR REPLACE VIEW med_proposals_with_details AS
SELECT 
    mp.*,
    ms.source_object_keys,
    ms.status as session_status,
    p.display_name as patient_name,
    bi.title as existing_med_name,
    bi.content_json as existing_med_content
FROM med_proposals mp
JOIN med_scan_sessions ms ON mp.session_id = ms.id
JOIN patients p ON mp.patient_id = p.id
LEFT JOIN binder_items bi ON mp.existing_med_id = bi.id;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE med_scan_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE med_proposals ENABLE ROW LEVEL SECURITY;

-- med_scan_sessions: Circle members can read (except ocr_text for viewers)
CREATE POLICY med_scan_sessions_select ON med_scan_sessions
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- med_scan_sessions: Contributors+ can create
CREATE POLICY med_scan_sessions_insert ON med_scan_sessions
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- med_scan_sessions: Contributors+ can update
CREATE POLICY med_scan_sessions_update ON med_scan_sessions
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- med_proposals: Circle members can read
CREATE POLICY med_proposals_select ON med_proposals
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- med_proposals: Contributors+ can update (accept/reject)
CREATE POLICY med_proposals_update ON med_proposals
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
