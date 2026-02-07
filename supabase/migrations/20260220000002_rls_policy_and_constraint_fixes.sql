-- ============================================================================
-- Migration: Security Hardening - RLS Policy Fixes, FK Constraints, ILIKE Escape
-- Description: Fix policy gaps, add auth checks to public-read tables,
--              escape ILIKE metacharacters, add FK constraints to transportation.
-- Date: 2026-02-20
-- ============================================================================


-- ============================================================================
-- H1: video_messages DELETE - requires circle membership
-- The existing policy allows created_by = auth.uid() without circle check.
-- Fix: creator DELETE branch must also verify circle membership.
-- ============================================================================

DROP POLICY IF EXISTS "Creator can delete own admins can delete any" ON video_messages;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Creator can delete own admins can delete any v2' AND tablename = 'video_messages') THEN
        CREATE POLICY "Creator can delete own admins can delete any v2" ON video_messages
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = video_messages.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND (
                          -- Creator can delete own
                          (video_messages.created_by = auth.uid())
                          OR
                          -- Admin/Owner can delete any
                          (circle_members.role IN ('ADMIN', 'OWNER'))
                      )
                )
            );
    END IF;
END $$;


-- ============================================================================
-- H2: provider_notes UPDATE - requires circle membership
-- The existing policy only checks created_by = auth.uid() without circle check.
-- ============================================================================

DROP POLICY IF EXISTS "provider_notes_update" ON provider_notes;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'provider_notes_update_v2' AND tablename = 'provider_notes') THEN
        CREATE POLICY provider_notes_update_v2 ON provider_notes
            FOR UPDATE USING (
                created_by = auth.uid()
                AND is_circle_member(circle_id, auth.uid())
            );
    END IF;
END $$;


-- ============================================================================
-- H3: photo_access_log INSERT - restrict to accessed_by = auth.uid()
-- and require circle membership
-- ============================================================================

DROP POLICY IF EXISTS "Authenticated users can insert access logs" ON photo_access_log;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members can insert own access logs' AND tablename = 'photo_access_log') THEN
        CREATE POLICY "Members can insert own access logs" ON photo_access_log
            FOR INSERT WITH CHECK (
                auth.uid() IS NOT NULL
                AND accessed_by = auth.uid()
                AND is_circle_member(circle_id, auth.uid())
            );
    END IF;
END $$;


-- ============================================================================
-- H4: tasks UPDATE/DELETE - creator branch must also check circle membership
-- The existing policies allow created_by = auth.uid() without circle check.
-- ============================================================================

DROP POLICY IF EXISTS "tasks_update" ON tasks;

CREATE POLICY tasks_update ON tasks
    FOR UPDATE
    USING (
        -- Assignee within the circle
        (owner_user_id = auth.uid() AND is_circle_member(circle_id, auth.uid()))
        -- Creator within the circle
        OR (created_by = auth.uid() AND is_circle_member(circle_id, auth.uid()))
        -- Admin+
        OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

DROP POLICY IF EXISTS "tasks_delete" ON tasks;

CREATE POLICY tasks_delete ON tasks
    FOR DELETE
    USING (
        -- Creator within the circle
        (created_by = auth.uid() AND is_circle_member(circle_id, auth.uid()))
        -- Admin+
        OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );


-- ============================================================================
-- M1-M4: Add auth.uid() IS NOT NULL to public-read reference table policies
-- These tables contain system/reference data. While the data itself isn't
-- sensitive, requiring authentication prevents unauthenticated access.
-- ============================================================================

-- discharge_templates: Require auth for read
DROP POLICY IF EXISTS "Anyone can read active templates" ON discharge_templates;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can read active templates' AND tablename = 'discharge_templates') THEN
        CREATE POLICY "Authenticated users can read active templates"
            ON discharge_templates FOR SELECT
            USING (is_active = true AND auth.uid() IS NOT NULL);
    END IF;
END $$;

-- question_templates: Require auth for read
DROP POLICY IF EXISTS "question_templates_select" ON question_templates;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'question_templates_select_v2' AND tablename = 'question_templates') THEN
        CREATE POLICY question_templates_select_v2 ON question_templates
            FOR SELECT USING (is_active = true AND auth.uid() IS NOT NULL);
    END IF;
END $$;

-- document_type_definitions: Require auth for read
DROP POLICY IF EXISTS "Anyone can read document types" ON document_type_definitions;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can read document types' AND tablename = 'document_type_definitions') THEN
        CREATE POLICY "Authenticated users can read document types"
            ON document_type_definitions FOR SELECT
            USING (auth.uid() IS NOT NULL);
    END IF;
END $$;

-- call_type_templates: Require auth for read
DROP POLICY IF EXISTS "Anyone can read call type templates" ON call_type_templates;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can read call type templates' AND tablename = 'call_type_templates') THEN
        CREATE POLICY "Authenticated users can read call type templates" ON call_type_templates
            FOR SELECT USING (auth.uid() IS NOT NULL);
    END IF;
END $$;

-- contact_role_types: Require auth for read
DROP POLICY IF EXISTS "Anyone can read contact role types" ON contact_role_types;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can read contact role types' AND tablename = 'contact_role_types') THEN
        CREATE POLICY "Authenticated users can read contact role types" ON contact_role_types
            FOR SELECT USING (auth.uid() IS NOT NULL);
    END IF;
END $$;

-- plan_limits: Require auth for read
DROP POLICY IF EXISTS "Anyone can read plan limits" ON plan_limits;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can read plan limits' AND tablename = 'plan_limits') THEN
        CREATE POLICY "Authenticated users can read plan limits" ON plan_limits
            FOR SELECT USING (auth.uid() IS NOT NULL);
    END IF;
END $$;


-- ============================================================================
-- M5: Escape ILIKE metacharacters in search_communication_logs
-- The p_facility_name parameter is used in ILIKE without escaping %_\ chars.
-- ============================================================================

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
    v_escaped_facility text;
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

    -- Escape ILIKE metacharacters in facility name search
    v_escaped_facility := p_facility_name;
    IF v_escaped_facility IS NOT NULL THEN
        v_escaped_facility := replace(v_escaped_facility, '\', '\\');
        v_escaped_facility := replace(v_escaped_facility, '%', '\%');
        v_escaped_facility := replace(v_escaped_facility, '_', '\_');
    END IF;

    -- Get total count first
    SELECT COUNT(*) INTO v_total
    FROM communication_logs cl
    WHERE cl.circle_id = p_circle_id
      AND (p_patient_id IS NULL OR cl.patient_id = p_patient_id)
      AND (v_escaped_facility IS NULL OR cl.facility_name ILIKE '%' || v_escaped_facility || '%')
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
      AND (v_escaped_facility IS NULL OR cl.facility_name ILIKE '%' || v_escaped_facility || '%')
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


-- ============================================================================
-- M6: Add FK constraints to transportation tables
-- scheduled_rides.created_by and .driver_user_id, ride_statistics.user_id
-- ============================================================================

-- scheduled_rides.created_by -> auth.users(id)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'scheduled_rides_created_by_fkey'
          AND table_name = 'scheduled_rides'
    ) THEN
        ALTER TABLE scheduled_rides
            ADD CONSTRAINT scheduled_rides_created_by_fkey
            FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
    END IF;
END $$;

-- scheduled_rides.driver_user_id -> auth.users(id)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'scheduled_rides_driver_user_id_fkey'
          AND table_name = 'scheduled_rides'
    ) THEN
        ALTER TABLE scheduled_rides
            ADD CONSTRAINT scheduled_rides_driver_user_id_fkey
            FOREIGN KEY (driver_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
    END IF;
END $$;

-- ride_statistics.user_id -> auth.users(id)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'ride_statistics_user_id_fkey'
          AND table_name = 'ride_statistics'
    ) THEN
        ALTER TABLE ride_statistics
            ADD CONSTRAINT ride_statistics_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;
END $$;
