-- Migration: 0013_helper_portal
-- Description: Facility Helper Portal - external submissions without account
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: helper_links
-- ============================================================================

CREATE TABLE helper_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    token text UNIQUE NOT NULL,
    name text,  -- Optional label for the helper/facility
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    max_submissions int DEFAULT 100,
    submission_count int DEFAULT 0 NOT NULL,
    last_used_at timestamptz,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX helper_links_token_idx ON helper_links(token);
CREATE INDEX helper_links_circle_id_idx ON helper_links(circle_id);
CREATE INDEX helper_links_patient_id_idx ON helper_links(patient_id);
CREATE INDEX helper_links_active_idx ON helper_links(expires_at) WHERE revoked_at IS NULL;

COMMENT ON TABLE helper_links IS 'Tokenized links for facility/helper external submissions';

-- ============================================================================
-- TABLE: helper_submissions
-- ============================================================================

CREATE TABLE helper_submissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    helper_link_id uuid NOT NULL REFERENCES helper_links(id) ON DELETE CASCADE,
    submitted_at timestamptz DEFAULT now() NOT NULL,
    status text DEFAULT 'PENDING' NOT NULL CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    payload_json jsonb NOT NULL,
    attachments uuid[] DEFAULT '{}',
    submitter_name text,
    submitter_role text,
    reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at timestamptz,
    review_note text,
    result_handoff_id uuid REFERENCES handoffs(id) ON DELETE SET NULL
);

CREATE INDEX helper_submissions_link_idx ON helper_submissions(helper_link_id);
CREATE INDEX helper_submissions_circle_idx ON helper_submissions(circle_id);
CREATE INDEX helper_submissions_status_idx ON helper_submissions(status);
CREATE INDEX helper_submissions_pending_idx ON helper_submissions(circle_id, status) WHERE status = 'PENDING';

COMMENT ON TABLE helper_submissions IS 'External updates submitted via helper links';

-- ============================================================================
-- FUNCTION: create_helper_link
-- ============================================================================

CREATE OR REPLACE FUNCTION create_helper_link(
    p_circle_id uuid,
    p_patient_id uuid,
    p_user_id uuid,
    p_name text DEFAULT NULL,
    p_ttl_days int DEFAULT 30
)
RETURNS jsonb AS $$
DECLARE
    v_token text;
    v_link_id uuid;
    v_expires_at timestamptz;
BEGIN
    -- Check permissions (admin only)
    IF NOT has_circle_role(p_circle_id, p_user_id, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Admin role required');
    END IF;
    
    -- Generate token
    v_token := encode(gen_random_bytes(24), 'base64');
    v_token := replace(replace(replace(v_token, '+', '-'), '/', '_'), '=', '');
    v_expires_at := now() + (p_ttl_days || ' days')::interval;
    
    -- Create link
    INSERT INTO helper_links (
        circle_id,
        patient_id,
        token,
        name,
        expires_at,
        created_by
    ) VALUES (
        p_circle_id,
        p_patient_id,
        v_token,
        p_name,
        v_expires_at,
        p_user_id
    )
    RETURNING id INTO v_link_id;
    
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
        'HELPER_LINK_CREATED',
        'helper_link',
        v_link_id,
        jsonb_build_object('name', p_name, 'ttl_days', p_ttl_days)
    );
    
    RETURN jsonb_build_object(
        'link_id', v_link_id,
        'token', v_token,
        'expires_at', v_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: validate_helper_link
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_helper_link(p_token text)
RETURNS jsonb AS $$
DECLARE
    v_link helper_links%ROWTYPE;
    v_patient patients%ROWTYPE;
BEGIN
    -- Get link
    SELECT * INTO v_link FROM helper_links WHERE token = p_token;
    
    IF v_link IS NULL THEN
        RETURN jsonb_build_object('valid', false, 'error', 'Link not found');
    END IF;
    
    IF v_link.revoked_at IS NOT NULL THEN
        RETURN jsonb_build_object('valid', false, 'error', 'Link has been revoked');
    END IF;
    
    IF v_link.expires_at < now() THEN
        RETURN jsonb_build_object('valid', false, 'error', 'Link has expired');
    END IF;
    
    IF v_link.submission_count >= v_link.max_submissions THEN
        RETURN jsonb_build_object('valid', false, 'error', 'Submission limit reached');
    END IF;
    
    -- Get patient info (limited)
    SELECT * INTO v_patient FROM patients WHERE id = v_link.patient_id;
    
    RETURN jsonb_build_object(
        'valid', true,
        'link_id', v_link.id,
        'patient_label', COALESCE(v_patient.initials, LEFT(v_patient.display_name, 1) || '.'),
        'helper_name', v_link.name
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: submit_helper_update
-- ============================================================================

CREATE OR REPLACE FUNCTION submit_helper_update(
    p_token text,
    p_payload jsonb,
    p_submitter_name text DEFAULT NULL,
    p_submitter_role text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_link helper_links%ROWTYPE;
    v_submission_id uuid;
BEGIN
    -- Validate link
    SELECT * INTO v_link FROM helper_links WHERE token = p_token;
    
    IF v_link IS NULL THEN
        RETURN jsonb_build_object('error', 'Link not found');
    END IF;
    
    IF v_link.revoked_at IS NOT NULL THEN
        RETURN jsonb_build_object('error', 'Link has been revoked');
    END IF;
    
    IF v_link.expires_at < now() THEN
        RETURN jsonb_build_object('error', 'Link has expired');
    END IF;
    
    IF v_link.submission_count >= v_link.max_submissions THEN
        RETURN jsonb_build_object('error', 'Submission limit reached');
    END IF;
    
    -- Create submission
    INSERT INTO helper_submissions (
        circle_id,
        patient_id,
        helper_link_id,
        payload_json,
        submitter_name,
        submitter_role
    ) VALUES (
        v_link.circle_id,
        v_link.patient_id,
        v_link.id,
        p_payload,
        p_submitter_name,
        p_submitter_role
    )
    RETURNING id INTO v_submission_id;
    
    -- Update link usage
    UPDATE helper_links
    SET 
        submission_count = submission_count + 1,
        last_used_at = now()
    WHERE id = v_link.id;
    
    -- Create notification for circle admins
    INSERT INTO notification_outbox (user_id, circle_id, notification_type, title, body, data_json)
    SELECT 
        cm.user_id,
        v_link.circle_id,
        'HELPER_SUBMISSION',
        'New Helper Update',
        COALESCE(p_submitter_name, 'A helper') || ' submitted an update',
        jsonb_build_object('submission_id', v_submission_id)
    FROM circle_members cm
    WHERE cm.circle_id = v_link.circle_id
      AND cm.role IN ('OWNER', 'ADMIN')
      AND cm.status = 'ACTIVE';
    
    RETURN jsonb_build_object(
        'submission_id', v_submission_id,
        'status', 'PENDING'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: review_helper_submission
-- ============================================================================

CREATE OR REPLACE FUNCTION review_helper_submission(
    p_submission_id uuid,
    p_user_id uuid,
    p_action text,  -- 'APPROVE' or 'REJECT'
    p_note text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_submission helper_submissions%ROWTYPE;
    v_handoff_id uuid;
BEGIN
    -- Get submission
    SELECT * INTO v_submission FROM helper_submissions WHERE id = p_submission_id;
    
    IF v_submission IS NULL THEN
        RETURN jsonb_build_object('error', 'Submission not found');
    END IF;
    
    IF v_submission.status != 'PENDING' THEN
        RETURN jsonb_build_object('error', 'Submission already reviewed');
    END IF;
    
    -- Check permissions
    IF NOT has_circle_role(v_submission.circle_id, p_user_id, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Admin role required');
    END IF;
    
    IF p_action = 'APPROVE' THEN
        -- Create handoff from submission
        INSERT INTO handoffs (
            circle_id,
            patient_id,
            created_by,
            type,
            title,
            summary,
            status
        ) VALUES (
            v_submission.circle_id,
            v_submission.patient_id,
            p_user_id,
            'FACILITY_UPDATE',
            COALESCE(v_submission.payload_json->>'title', 'External Update from ' || COALESCE(v_submission.submitter_name, 'Helper')),
            COALESCE(v_submission.payload_json->>'summary', v_submission.payload_json::text),
            'PUBLISHED'
        )
        RETURNING id INTO v_handoff_id;
        
        -- Update submission
        UPDATE helper_submissions
        SET 
            status = 'APPROVED',
            reviewed_by = p_user_id,
            reviewed_at = now(),
            review_note = p_note,
            result_handoff_id = v_handoff_id
        WHERE id = p_submission_id;
        
    ELSE -- REJECT
        UPDATE helper_submissions
        SET 
            status = 'REJECTED',
            reviewed_by = p_user_id,
            reviewed_at = now(),
            review_note = p_note
        WHERE id = p_submission_id;
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
        v_submission.circle_id,
        p_user_id,
        'HELPER_SUBMISSION_REVIEWED',
        'helper_submission',
        p_submission_id,
        jsonb_build_object('action', p_action, 'handoff_id', v_handoff_id)
    );
    
    RETURN jsonb_build_object(
        'submission_id', p_submission_id,
        'status', CASE WHEN p_action = 'APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END,
        'handoff_id', v_handoff_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE helper_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE helper_submissions ENABLE ROW LEVEL SECURITY;

-- helper_links: Admin can manage
CREATE POLICY helper_links_select ON helper_links
    FOR SELECT USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

CREATE POLICY helper_links_insert ON helper_links
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

CREATE POLICY helper_links_update ON helper_links
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- helper_submissions: Admin can view and manage
CREATE POLICY helper_submissions_select ON helper_submissions
    FOR SELECT USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

CREATE POLICY helper_submissions_update ON helper_submissions
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));
