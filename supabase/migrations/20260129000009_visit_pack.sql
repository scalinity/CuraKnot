-- Migration: 0009_visit_pack
-- Description: Clinician Visit Pack - appointment briefs and share links
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: appointment_packs
-- ============================================================================

CREATE TABLE appointment_packs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    range_start timestamptz NOT NULL,
    range_end timestamptz NOT NULL,
    template text DEFAULT 'general' NOT NULL,
    content_json jsonb NOT NULL,
    pdf_object_key text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX appointment_packs_circle_id_idx ON appointment_packs(circle_id);
CREATE INDEX appointment_packs_patient_id_idx ON appointment_packs(patient_id);
CREATE INDEX appointment_packs_created_at_idx ON appointment_packs(created_at);

COMMENT ON TABLE appointment_packs IS 'Generated appointment briefs for clinician visits';

-- ============================================================================
-- TABLE: share_links (Reusable for multiple object types)
-- ============================================================================

CREATE TABLE share_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    object_type text NOT NULL CHECK (object_type IN ('appointment_pack', 'emergency_card', 'care_summary')),
    object_id uuid NOT NULL,
    token text UNIQUE NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    access_count int DEFAULT 0 NOT NULL,
    last_accessed_at timestamptz,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX share_links_token_idx ON share_links(token);
CREATE INDEX share_links_object_idx ON share_links(object_type, object_id);
CREATE INDEX share_links_circle_id_idx ON share_links(circle_id);
CREATE INDEX share_links_expires_at_idx ON share_links(expires_at) WHERE revoked_at IS NULL;

COMMENT ON TABLE share_links IS 'Tokenized share links for secure external access';

-- ============================================================================
-- TABLE: share_link_access_log
-- ============================================================================

CREATE TABLE share_link_access_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    share_link_id uuid NOT NULL REFERENCES share_links(id) ON DELETE CASCADE,
    accessed_at timestamptz DEFAULT now() NOT NULL,
    ip_hash text,
    user_agent_hash text
);

CREATE INDEX share_link_access_log_link_idx ON share_link_access_log(share_link_id);
CREATE INDEX share_link_access_log_time_idx ON share_link_access_log(accessed_at);

COMMENT ON TABLE share_link_access_log IS 'Audit log for share link access';

-- ============================================================================
-- TABLE: visit_questions
-- ============================================================================

CREATE TABLE visit_questions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    appointment_pack_id uuid REFERENCES appointment_packs(id) ON DELETE SET NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    question text NOT NULL,
    priority text DEFAULT 'MEDIUM' CHECK (priority IN ('LOW', 'MEDIUM', 'HIGH')),
    answered boolean DEFAULT false NOT NULL,
    answer text,
    answered_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX visit_questions_pack_idx ON visit_questions(appointment_pack_id) WHERE appointment_pack_id IS NOT NULL;
CREATE INDEX visit_questions_patient_idx ON visit_questions(patient_id);
CREATE INDEX visit_questions_unanswered_idx ON visit_questions(patient_id) WHERE answered = false;

COMMENT ON TABLE visit_questions IS 'Questions to ask during clinician visits';

-- ============================================================================
-- FUNCTION: generate_share_token
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_share_token()
RETURNS text AS $$
DECLARE
    v_token text;
BEGIN
    -- Generate a URL-safe random token
    v_token := encode(gen_random_bytes(24), 'base64');
    v_token := replace(v_token, '+', '-');
    v_token := replace(v_token, '/', '_');
    v_token := replace(v_token, '=', '');
    RETURN v_token;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: create_share_link
-- ============================================================================

CREATE OR REPLACE FUNCTION create_share_link(
    p_circle_id uuid,
    p_user_id uuid,
    p_object_type text,
    p_object_id uuid,
    p_ttl_hours int DEFAULT 24
)
RETURNS jsonb AS $$
DECLARE
    v_token text;
    v_link_id uuid;
    v_expires_at timestamptz;
BEGIN
    -- Check membership
    IF NOT is_circle_member(p_circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;
    
    -- Generate token and expiry
    v_token := generate_share_token();
    v_expires_at := now() + (p_ttl_hours || ' hours')::interval;
    
    -- Create link
    INSERT INTO share_links (
        circle_id,
        object_type,
        object_id,
        token,
        expires_at,
        created_by
    ) VALUES (
        p_circle_id,
        p_object_type,
        p_object_id,
        v_token,
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
        'SHARE_LINK_CREATED',
        p_object_type,
        p_object_id,
        jsonb_build_object('link_id', v_link_id, 'ttl_hours', p_ttl_hours)
    );
    
    RETURN jsonb_build_object(
        'link_id', v_link_id,
        'token', v_token,
        'expires_at', v_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: resolve_share_link
-- ============================================================================

CREATE OR REPLACE FUNCTION resolve_share_link(
    p_token text,
    p_ip_hash text DEFAULT NULL,
    p_user_agent_hash text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_link share_links%ROWTYPE;
BEGIN
    -- Get link
    SELECT * INTO v_link FROM share_links WHERE token = p_token;
    
    IF v_link IS NULL THEN
        RETURN jsonb_build_object('error', 'Link not found');
    END IF;
    
    -- Check expiry
    IF v_link.expires_at < now() THEN
        RETURN jsonb_build_object('error', 'Link expired');
    END IF;
    
    -- Check revocation
    IF v_link.revoked_at IS NOT NULL THEN
        RETURN jsonb_build_object('error', 'Link revoked');
    END IF;

    -- Check max access count (single-use or limited access)
    IF v_link.max_access_count IS NOT NULL AND v_link.access_count >= v_link.max_access_count THEN
        RETURN jsonb_build_object('error', 'Link access limit reached');
    END IF;

    -- Update access count
    UPDATE share_links
    SET
        access_count = access_count + 1,
        last_accessed_at = now()
    WHERE id = v_link.id;
    
    -- Log access
    INSERT INTO share_link_access_log (share_link_id, ip_hash, user_agent_hash)
    VALUES (v_link.id, p_ip_hash, p_user_agent_hash);
    
    RETURN jsonb_build_object(
        'valid', true,
        'link_id', v_link.id,
        'object_type', v_link.object_type,
        'object_id', v_link.object_id,
        'circle_id', v_link.circle_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: revoke_share_link
-- ============================================================================

CREATE OR REPLACE FUNCTION revoke_share_link(
    p_link_id uuid,
    p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_link share_links%ROWTYPE;
BEGIN
    SELECT * INTO v_link FROM share_links WHERE id = p_link_id;
    
    IF v_link IS NULL THEN
        RETURN jsonb_build_object('error', 'Link not found');
    END IF;
    
    -- Check membership
    IF NOT is_circle_member(v_link.circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;
    
    -- Revoke
    UPDATE share_links SET revoked_at = now() WHERE id = p_link_id;
    
    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_link.circle_id,
        p_user_id,
        'SHARE_LINK_REVOKED',
        'share_link',
        p_link_id,
        jsonb_build_object('original_object_type', v_link.object_type, 'original_object_id', v_link.object_id)
    );
    
    RETURN jsonb_build_object('revoked', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: compose_appointment_pack_content
-- ============================================================================

CREATE OR REPLACE FUNCTION compose_appointment_pack_content(
    p_circle_id uuid,
    p_patient_id uuid,
    p_range_start timestamptz,
    p_range_end timestamptz
)
RETURNS jsonb AS $$
DECLARE
    v_content jsonb;
    v_handoffs jsonb;
    v_med_changes jsonb;
    v_tasks jsonb;
    v_questions jsonb;
    v_patient patients%ROWTYPE;
BEGIN
    -- Get patient info
    SELECT * INTO v_patient FROM patients WHERE id = p_patient_id;
    
    -- Get handoff summaries in range
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', h.id,
        'type', h.type,
        'title', h.title,
        'summary', h.summary,
        'created_at', h.created_at
    ) ORDER BY h.created_at DESC), '[]'::jsonb)
    INTO v_handoffs
    FROM handoffs h
    WHERE h.circle_id = p_circle_id
      AND h.patient_id = p_patient_id
      AND h.status = 'PUBLISHED'
      AND h.created_at >= p_range_start
      AND h.created_at <= p_range_end;
    
    -- Get medication changes from binder revisions
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'name', bi.title,
        'content', bi.content_json,
        'updated_at', bi.updated_at
    ) ORDER BY bi.updated_at DESC), '[]'::jsonb)
    INTO v_med_changes
    FROM binder_items bi
    WHERE bi.circle_id = p_circle_id
      AND bi.patient_id = p_patient_id
      AND bi.type = 'MED'
      AND bi.updated_at >= p_range_start
      AND bi.updated_at <= p_range_end;
    
    -- Get open tasks
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'priority', t.priority,
        'due_at', t.due_at
    ) ORDER BY t.priority DESC, t.due_at), '[]'::jsonb)
    INTO v_tasks
    FROM tasks t
    WHERE t.circle_id = p_circle_id
      AND t.patient_id = p_patient_id
      AND t.status = 'OPEN';
    
    -- Get unanswered questions
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', q.id,
        'question', q.question,
        'priority', q.priority,
        'created_by', q.created_by
    ) ORDER BY 
        CASE q.priority WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
        q.created_at
    ), '[]'::jsonb)
    INTO v_questions
    FROM visit_questions q
    WHERE q.circle_id = p_circle_id
      AND q.patient_id = p_patient_id
      AND q.answered = false;
    
    -- Compose content
    v_content := jsonb_build_object(
        'patient', jsonb_build_object(
            'id', v_patient.id,
            'name', v_patient.display_name,
            'initials', v_patient.initials
        ),
        'range', jsonb_build_object(
            'start', p_range_start,
            'end', p_range_end
        ),
        'generated_at', now(),
        'handoffs', v_handoffs,
        'med_changes', v_med_changes,
        'open_tasks', v_tasks,
        'questions', v_questions,
        'counts', jsonb_build_object(
            'handoffs', jsonb_array_length(v_handoffs),
            'med_changes', jsonb_array_length(v_med_changes),
            'open_tasks', jsonb_array_length(v_tasks),
            'questions', jsonb_array_length(v_questions)
        )
    );
    
    RETURN v_content;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE appointment_packs ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_link_access_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_questions ENABLE ROW LEVEL SECURITY;

-- appointment_packs: Circle members can read
CREATE POLICY appointment_packs_select ON appointment_packs
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- appointment_packs: Contributors+ can create
CREATE POLICY appointment_packs_insert ON appointment_packs
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- share_links: Circle members can read their circle's links
CREATE POLICY share_links_select ON share_links
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- share_links: Circle members can create
CREATE POLICY share_links_insert ON share_links
    FOR INSERT WITH CHECK (is_circle_member(circle_id, auth.uid()));

-- share_links: Creator or admin can update (revoke)
CREATE POLICY share_links_update ON share_links
    FOR UPDATE USING (
        created_by = auth.uid() OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

-- share_link_access_log: Admin+ can view
CREATE POLICY share_link_access_log_select ON share_link_access_log
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM share_links sl
            WHERE sl.id = share_link_access_log.share_link_id
            AND has_circle_role(sl.circle_id, auth.uid(), 'ADMIN')
        )
    );

-- visit_questions: Circle members can read
CREATE POLICY visit_questions_select ON visit_questions
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- visit_questions: Contributors+ can create
CREATE POLICY visit_questions_insert ON visit_questions
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- visit_questions: Contributors+ can update
CREATE POLICY visit_questions_update ON visit_questions
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
