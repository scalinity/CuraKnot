-- ============================================================================
-- Migration: Communication Logs (Facility Communication Log Feature)
-- Description: Track facility calls and communications with follow-up support
-- ============================================================================

-- ============================================================================
-- TABLE: communication_logs
-- ============================================================================

CREATE TABLE IF NOT EXISTS communication_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id),

    -- Contact info
    facility_name text NOT NULL,
    facility_id uuid REFERENCES binder_items(id),  -- Link to binder facility
    contact_name text NOT NULL,
    contact_role text[] DEFAULT '{}',  -- NURSE, SOCIAL_WORKER, ADMIN, BILLING, DOCTOR, OTHER
    contact_phone text,
    contact_email text,

    -- Call details
    communication_type text NOT NULL DEFAULT 'CALL',  -- CALL, MESSAGE, EMAIL, IN_PERSON
    call_type text NOT NULL,  -- STATUS_UPDATE, QUESTION, COMPLAINT, SCHEDULING, BILLING, DISCHARGE, OTHER
    call_date timestamptz NOT NULL DEFAULT now(),
    duration_minutes int,
    summary text NOT NULL,

    -- Follow-up
    follow_up_date date,
    follow_up_reason text,
    follow_up_status text DEFAULT 'NONE',  -- NONE, PENDING, COMPLETE, CANCELLED
    follow_up_completed_at timestamptz,
    follow_up_task_id uuid REFERENCES tasks(id),

    -- Linked entities
    linked_handoff_id uuid REFERENCES handoffs(id),

    -- AI suggestions (FAMILY tier)
    ai_suggested_tasks jsonb,  -- Array of suggested task objects
    ai_suggestions_accepted boolean DEFAULT false,

    -- Status
    resolution_status text DEFAULT 'OPEN',  -- OPEN, RESOLVED, ESCALATED

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Index for patient lookup (primary access pattern)
CREATE INDEX IF NOT EXISTS idx_communication_logs_patient
    ON communication_logs(patient_id, call_date DESC);

-- Index for facility lookup
CREATE INDEX IF NOT EXISTS idx_communication_logs_facility
    ON communication_logs(circle_id, facility_name, call_date DESC);

-- Index for pending follow-ups
CREATE INDEX IF NOT EXISTS idx_communication_logs_followup
    ON communication_logs(follow_up_date)
    WHERE follow_up_status = 'PENDING';

-- Index for circle membership filtering
CREATE INDEX IF NOT EXISTS idx_communication_logs_circle
    ON communication_logs(circle_id, call_date DESC);

-- Full-text search index
CREATE INDEX IF NOT EXISTS idx_communication_logs_search
    ON communication_logs USING gin(
        to_tsvector('english', summary || ' ' || COALESCE(contact_name, '') || ' ' || COALESCE(facility_name, ''))
    );

-- Composite index for common query patterns (circle + patient + date)
CREATE INDEX IF NOT EXISTS idx_communication_logs_composite
    ON communication_logs(circle_id, patient_id, call_date DESC)
    WHERE patient_id IS NOT NULL;

-- Index for resolution status filtering
CREATE INDEX IF NOT EXISTS idx_communication_logs_resolution
    ON communication_logs(circle_id, resolution_status, call_date DESC);

-- ============================================================================
-- TABLE: call_type_templates
-- ============================================================================

CREATE TABLE IF NOT EXISTS call_type_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    type_key text NOT NULL UNIQUE,
    display_name text NOT NULL,
    icon text,
    prompt_text text,
    default_follow_up_days int,
    is_active boolean NOT NULL DEFAULT true,
    sort_order int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Seed default templates
INSERT INTO call_type_templates (type_key, display_name, icon, prompt_text, default_follow_up_days, sort_order) VALUES
    ('STATUS_UPDATE', 'Status Update', 'info.circle', 'What was discussed? Any changes to care?', NULL, 1),
    ('QUESTION', 'Question', 'questionmark.circle', 'What did you ask? What was the answer?', 3, 2),
    ('COMPLAINT', 'Complaint', 'exclamationmark.triangle', 'What was the issue? What was their response?', 2, 3),
    ('SCHEDULING', 'Scheduling', 'calendar', 'What was scheduled? Confirmed date/time?', NULL, 4),
    ('BILLING', 'Billing', 'dollarsign.circle', 'Claim/account number? Amount? Resolution?', 7, 5),
    ('DISCHARGE', 'Discharge Planning', 'house', 'Discharge date? Requirements? Next steps?', 1, 6),
    ('OTHER', 'Other', 'ellipsis.circle', 'Describe the communication.', NULL, 7)
ON CONFLICT (type_key) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    icon = EXCLUDED.icon,
    prompt_text = EXCLUDED.prompt_text,
    default_follow_up_days = EXCLUDED.default_follow_up_days,
    sort_order = EXCLUDED.sort_order;

-- ============================================================================
-- TABLE: contact_role_types
-- ============================================================================

CREATE TABLE IF NOT EXISTS contact_role_types (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    role_key text NOT NULL UNIQUE,
    display_name text NOT NULL,
    icon text,
    sort_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true
);

-- Seed contact roles
INSERT INTO contact_role_types (role_key, display_name, icon, sort_order) VALUES
    ('NURSE', 'Nurse', 'heart.text.square', 1),
    ('DOCTOR', 'Doctor', 'stethoscope', 2),
    ('SOCIAL_WORKER', 'Social Worker', 'person.2', 3),
    ('ADMIN', 'Administrator', 'building.2', 4),
    ('BILLING', 'Billing', 'dollarsign.circle', 5),
    ('RECEPTIONIST', 'Receptionist', 'phone', 6),
    ('THERAPIST', 'Therapist', 'figure.walk', 7),
    ('OTHER', 'Other', 'person.crop.circle', 8)
ON CONFLICT (role_key) DO NOTHING;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE communication_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE call_type_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_role_types ENABLE ROW LEVEL SECURITY;

-- communication_logs: Members can read logs from their circles
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members read circle communication logs') THEN
        CREATE POLICY "Members read circle communication logs" ON communication_logs
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = communication_logs.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- communication_logs: Contributors+ can create logs
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create communication logs') THEN
        CREATE POLICY "Contributors create communication logs" ON communication_logs
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = communication_logs.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

-- communication_logs: Contributors+ can update their own or any (admin+)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors update communication logs') THEN
        CREATE POLICY "Contributors update communication logs" ON communication_logs
            FOR UPDATE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = communication_logs.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND (
                          circle_members.role IN ('OWNER', 'ADMIN')
                          OR communication_logs.created_by = auth.uid()
                      )
                )
            );
    END IF;
END $$;

-- communication_logs: Admins+ can delete logs
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins delete communication logs') THEN
        CREATE POLICY "Admins delete communication logs" ON communication_logs
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = communication_logs.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- Templates: Everyone can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can read call type templates') THEN
        CREATE POLICY "Anyone can read call type templates" ON call_type_templates
            FOR SELECT USING (true);
    END IF;
END $$;

-- Contact roles: Everyone can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can read contact role types') THEN
        CREATE POLICY "Anyone can read contact role types" ON contact_role_types
            FOR SELECT USING (true);
    END IF;
END $$;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to search communication logs with full-text and filters
CREATE OR REPLACE FUNCTION search_communication_logs(
    p_circle_id uuid,
    p_patient_id uuid DEFAULT NULL,
    p_query text DEFAULT NULL,
    p_facility_name text DEFAULT NULL,
    p_call_type text DEFAULT NULL,
    p_date_from timestamptz DEFAULT NULL,
    p_date_to timestamptz DEFAULT NULL,
    p_follow_up_status text DEFAULT NULL,
    p_limit int DEFAULT 50,
    p_offset int DEFAULT 0
)
RETURNS TABLE (
    id uuid,
    circle_id uuid,
    patient_id uuid,
    created_by uuid,
    facility_name text,
    facility_id uuid,
    contact_name text,
    contact_role text[],
    contact_phone text,
    contact_email text,
    communication_type text,
    call_type text,
    call_date timestamptz,
    duration_minutes int,
    summary text,
    follow_up_date date,
    follow_up_reason text,
    follow_up_status text,
    follow_up_completed_at timestamptz,
    follow_up_task_id uuid,
    linked_handoff_id uuid,
    ai_suggested_tasks jsonb,
    ai_suggestions_accepted boolean,
    resolution_status text,
    created_at timestamptz,
    updated_at timestamptz,
    total_count bigint
) AS $$
DECLARE
    v_total bigint;
BEGIN
    -- Verify caller is a member of this circle (security check)
    IF NOT EXISTS (
        SELECT 1 FROM circle_members
        WHERE circle_members.circle_id = p_circle_id
          AND circle_members.user_id = auth.uid()
          AND circle_members.status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'Access denied: Not a member of this circle';
    END IF;

    -- Sanitize limit and offset
    p_limit := LEAST(GREATEST(p_limit, 1), 100);
    p_offset := GREATEST(p_offset, 0);

    -- Get total count first
    SELECT COUNT(*) INTO v_total
    FROM communication_logs cl
    WHERE cl.circle_id = p_circle_id
      AND (p_patient_id IS NULL OR cl.patient_id = p_patient_id)
      AND (p_facility_name IS NULL OR cl.facility_name ILIKE '%' || p_facility_name || '%')
      AND (p_call_type IS NULL OR cl.call_type = p_call_type)
      AND (p_date_from IS NULL OR cl.call_date >= p_date_from)
      AND (p_date_to IS NULL OR cl.call_date <= p_date_to)
      AND (p_follow_up_status IS NULL OR cl.follow_up_status = p_follow_up_status)
      AND (p_query IS NULL OR to_tsvector('english', cl.summary || ' ' || COALESCE(cl.contact_name, '') || ' ' || COALESCE(cl.facility_name, '')) @@ plainto_tsquery('english', p_query));

    RETURN QUERY
    SELECT
        cl.id,
        cl.circle_id,
        cl.patient_id,
        cl.created_by,
        cl.facility_name,
        cl.facility_id,
        cl.contact_name,
        cl.contact_role,
        cl.contact_phone,
        cl.contact_email,
        cl.communication_type,
        cl.call_type,
        cl.call_date,
        cl.duration_minutes,
        cl.summary,
        cl.follow_up_date,
        cl.follow_up_reason,
        cl.follow_up_status,
        cl.follow_up_completed_at,
        cl.follow_up_task_id,
        cl.linked_handoff_id,
        cl.ai_suggested_tasks,
        cl.ai_suggestions_accepted,
        cl.resolution_status,
        cl.created_at,
        cl.updated_at,
        v_total
    FROM communication_logs cl
    WHERE cl.circle_id = p_circle_id
      AND (p_patient_id IS NULL OR cl.patient_id = p_patient_id)
      AND (p_facility_name IS NULL OR cl.facility_name ILIKE '%' || p_facility_name || '%')
      AND (p_call_type IS NULL OR cl.call_type = p_call_type)
      AND (p_date_from IS NULL OR cl.call_date >= p_date_from)
      AND (p_date_to IS NULL OR cl.call_date <= p_date_to)
      AND (p_follow_up_status IS NULL OR cl.follow_up_status = p_follow_up_status)
      AND (p_query IS NULL OR to_tsvector('english', cl.summary || ' ' || COALESCE(cl.contact_name, '') || ' ' || COALESCE(cl.facility_name, '')) @@ plainto_tsquery('english', p_query))
    ORDER BY cl.call_date DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to create follow-up task from communication log
CREATE OR REPLACE FUNCTION create_follow_up_task_from_log(
    p_log_id uuid,
    p_user_id uuid
)
RETURNS uuid AS $$
DECLARE
    v_log communication_logs%ROWTYPE;
    v_task_id uuid;
BEGIN
    -- Get the log
    SELECT * INTO v_log FROM communication_logs WHERE id = p_log_id;

    IF v_log IS NULL THEN
        RAISE EXCEPTION 'Communication log not found';
    END IF;

    -- Verify caller is a member of this circle with contributor+ role (security check)
    IF NOT EXISTS (
        SELECT 1 FROM circle_members
        WHERE circle_members.circle_id = v_log.circle_id
          AND circle_members.user_id = auth.uid()
          AND circle_members.status = 'ACTIVE'
          AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
    ) THEN
        RAISE EXCEPTION 'Access denied: Requires contributor role or higher';
    END IF;

    IF v_log.follow_up_date IS NULL THEN
        RAISE EXCEPTION 'No follow-up date specified';
    END IF;

    -- Create the task
    INSERT INTO tasks (
        circle_id,
        patient_id,
        created_by,
        owner_user_id,
        title,
        description,
        due_at,
        priority,
        status
    ) VALUES (
        v_log.circle_id,
        v_log.patient_id,
        p_user_id,
        p_user_id,
        'Follow up: ' || v_log.facility_name,
        COALESCE(v_log.follow_up_reason, 'Follow up on call from ' || to_char(v_log.call_date, 'Mon DD, YYYY')),
        v_log.follow_up_date::timestamptz,
        'MED',
        'OPEN'
    )
    RETURNING id INTO v_task_id;

    -- Update the log with task reference
    UPDATE communication_logs
    SET follow_up_task_id = v_task_id,
        follow_up_status = 'PENDING',
        updated_at = now()
    WHERE id = p_log_id;

    RETURN v_task_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to mark follow-up complete
CREATE OR REPLACE FUNCTION complete_follow_up(
    p_log_id uuid
)
RETURNS void AS $$
DECLARE
    v_circle_id uuid;
BEGIN
    -- Get the circle ID for the log
    SELECT circle_id INTO v_circle_id FROM communication_logs WHERE id = p_log_id;

    IF v_circle_id IS NULL THEN
        RAISE EXCEPTION 'Communication log not found';
    END IF;

    -- Verify caller is a member of this circle (security check)
    IF NOT EXISTS (
        SELECT 1 FROM circle_members
        WHERE circle_members.circle_id = v_circle_id
          AND circle_members.user_id = auth.uid()
          AND circle_members.status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'Access denied: Not a member of this circle';
    END IF;

    UPDATE communication_logs
    SET follow_up_status = 'COMPLETE',
        follow_up_completed_at = now(),
        updated_at = now()
    WHERE id = p_log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_communication_log_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS communication_logs_updated_at ON communication_logs;
CREATE TRIGGER communication_logs_updated_at
    BEFORE UPDATE ON communication_logs
    FOR EACH ROW
    EXECUTE FUNCTION update_communication_log_timestamp();

-- ============================================================================
-- UPDATE plan_limits to include facility_communication_log feature
-- ============================================================================

UPDATE plan_limits
SET features_json = features_json || '["facility_communication_log"]'::jsonb
WHERE plan IN ('PLUS', 'FAMILY')
  AND NOT (features_json ? 'facility_communication_log');

-- Add ai_task_suggestions feature to FAMILY only
UPDATE plan_limits
SET features_json = features_json || '["facility_log_ai_suggestions"]'::jsonb
WHERE plan = 'FAMILY'
  AND NOT (features_json ? 'facility_log_ai_suggestions');

-- ============================================================================
-- AUDIT TRIGGER for PHI access tracking
-- ============================================================================

-- Function to log communication log access for audit trail
CREATE OR REPLACE FUNCTION log_communication_log_access()
RETURNS TRIGGER AS $$
BEGIN
    -- Only log significant operations (INSERT, UPDATE, DELETE)
    -- For SELECT, RLS handles access control
    INSERT INTO audit_events (
        event_type,
        entity_type,
        entity_id,
        user_id,
        circle_id,
        metadata,
        created_at
    ) VALUES (
        TG_OP,
        'communication_log',
        COALESCE(NEW.id, OLD.id),
        auth.uid(),
        COALESCE(NEW.circle_id, OLD.circle_id),
        jsonb_build_object(
            'facility_name', COALESCE(NEW.facility_name, OLD.facility_name),
            'call_type', COALESCE(NEW.call_type, OLD.call_type)
        ),
        now()
    );
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Audit trigger for communication logs
DROP TRIGGER IF EXISTS communication_logs_audit ON communication_logs;
CREATE TRIGGER communication_logs_audit
    AFTER INSERT OR UPDATE OR DELETE ON communication_logs
    FOR EACH ROW
    EXECUTE FUNCTION log_communication_log_access();
