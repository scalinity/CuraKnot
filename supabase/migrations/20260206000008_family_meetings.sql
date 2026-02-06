-- ============================================================================
-- Migration: Family Meeting Mode
-- Description: Structured coordination for family care meetings
-- Date: 2026-02-06
-- ============================================================================

-- ============================================================================
-- TABLE: family_meetings
-- ============================================================================

CREATE TABLE IF NOT EXISTS family_meetings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Meeting details
    title text NOT NULL,
    scheduled_at timestamptz NOT NULL,
    format text NOT NULL DEFAULT 'IN_PERSON' CHECK (format IN ('IN_PERSON', 'VIDEO')),
    meeting_link text,

    -- Status tracking
    status text NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN (
        'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'
    )),
    started_at timestamptz,
    ended_at timestamptz,

    -- Summary output
    summary_handoff_id uuid REFERENCES handoffs(id) ON DELETE SET NULL,

    -- Recurrence (FAMILY tier only)
    recurrence_rule text,
    parent_meeting_id uuid REFERENCES family_meetings(id) ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_family_meetings_circle ON family_meetings(circle_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_family_meetings_patient ON family_meetings(patient_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_family_meetings_status ON family_meetings(status, scheduled_at)
    WHERE status IN ('SCHEDULED', 'IN_PROGRESS');
CREATE INDEX IF NOT EXISTS idx_family_meetings_created_by ON family_meetings(created_by);
CREATE INDEX IF NOT EXISTS idx_family_meetings_parent ON family_meetings(parent_meeting_id)
    WHERE parent_meeting_id IS NOT NULL;

CREATE TRIGGER family_meetings_updated_at
    BEFORE UPDATE ON family_meetings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE family_meetings IS 'Structured family care meetings with agenda, decisions, and action items';

-- ============================================================================
-- TABLE: meeting_attendees
-- ============================================================================

CREATE TABLE IF NOT EXISTS meeting_attendees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id uuid NOT NULL REFERENCES family_meetings(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    status text NOT NULL DEFAULT 'INVITED' CHECK (status IN (
        'INVITED', 'ACCEPTED', 'DECLINED', 'ATTENDED'
    )),
    invited_at timestamptz NOT NULL DEFAULT now(),
    responded_at timestamptz,

    UNIQUE(meeting_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_meeting_attendees_meeting ON meeting_attendees(meeting_id);
CREATE INDEX IF NOT EXISTS idx_meeting_attendees_user ON meeting_attendees(user_id, invited_at DESC);

COMMENT ON TABLE meeting_attendees IS 'Meeting attendance tracking and RSVP status';

-- ============================================================================
-- TABLE: meeting_agenda_items
-- ============================================================================

CREATE TABLE IF NOT EXISTS meeting_agenda_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id uuid NOT NULL REFERENCES family_meetings(id) ON DELETE CASCADE,
    added_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Content
    title text NOT NULL,
    description text,
    sort_order int NOT NULL,

    -- During meeting
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN (
        'PENDING', 'IN_PROGRESS', 'COMPLETED', 'SKIPPED'
    )),
    notes text,
    decision text,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meeting_agenda_items_meeting ON meeting_agenda_items(meeting_id, sort_order);

COMMENT ON TABLE meeting_agenda_items IS 'Agenda items for family meetings with notes and decisions';

-- ============================================================================
-- TABLE: meeting_action_items
-- ============================================================================

CREATE TABLE IF NOT EXISTS meeting_action_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id uuid NOT NULL REFERENCES family_meetings(id) ON DELETE CASCADE,
    agenda_item_id uuid REFERENCES meeting_agenda_items(id) ON DELETE SET NULL,

    -- Action details
    description text NOT NULL,
    assigned_to uuid REFERENCES users(id) ON DELETE SET NULL,
    due_date date,

    -- Task linkage
    task_id uuid REFERENCES tasks(id) ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meeting_action_items_meeting ON meeting_action_items(meeting_id);
CREATE INDEX IF NOT EXISTS idx_meeting_action_items_agenda ON meeting_action_items(agenda_item_id)
    WHERE agenda_item_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_meeting_action_items_assigned ON meeting_action_items(assigned_to)
    WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_meeting_action_items_task ON meeting_action_items(task_id)
    WHERE task_id IS NOT NULL;

COMMENT ON TABLE meeting_action_items IS 'Action items from meetings that can be converted to tasks';

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE family_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_agenda_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_action_items ENABLE ROW LEVEL SECURITY;

-- family_meetings: Circle members can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'family_meetings_select') THEN
        CREATE POLICY family_meetings_select ON family_meetings
            FOR SELECT USING (is_circle_member(circle_id, auth.uid()));
    END IF;
END $$;

-- family_meetings: Contributors+ can create
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'family_meetings_insert') THEN
        CREATE POLICY family_meetings_insert ON family_meetings
            FOR INSERT WITH CHECK (
                has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR')
                AND created_by = auth.uid()
            );
    END IF;
END $$;

-- family_meetings: Creator or admin can update
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'family_meetings_update') THEN
        CREATE POLICY family_meetings_update ON family_meetings
            FOR UPDATE USING (
                created_by = auth.uid()
                OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
            );
    END IF;
END $$;

-- family_meetings: Creator or admin can delete
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'family_meetings_delete') THEN
        CREATE POLICY family_meetings_delete ON family_meetings
            FOR DELETE USING (
                created_by = auth.uid()
                OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
            );
    END IF;
END $$;

-- meeting_attendees: Circle members can read (via meeting's circle)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_attendees_select') THEN
        CREATE POLICY meeting_attendees_select ON meeting_attendees
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_attendees.meeting_id
                    AND is_circle_member(fm.circle_id, auth.uid())
                )
            );
    END IF;
END $$;

-- meeting_attendees: Meeting creator or admin can insert
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_attendees_insert') THEN
        CREATE POLICY meeting_attendees_insert ON meeting_attendees
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_attendees.meeting_id
                    AND (
                        fm.created_by = auth.uid()
                        OR has_circle_role(fm.circle_id, auth.uid(), 'ADMIN')
                    )
                )
            );
    END IF;
END $$;

-- meeting_attendees: User can update own status, or creator/admin can update
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_attendees_update') THEN
        CREATE POLICY meeting_attendees_update ON meeting_attendees
            FOR UPDATE USING (
                user_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_attendees.meeting_id
                    AND (
                        fm.created_by = auth.uid()
                        OR has_circle_role(fm.circle_id, auth.uid(), 'ADMIN')
                    )
                )
            );
    END IF;
END $$;

-- meeting_agenda_items: Circle members can read (via meeting's circle)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_agenda_items_select') THEN
        CREATE POLICY meeting_agenda_items_select ON meeting_agenda_items
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_agenda_items.meeting_id
                    AND is_circle_member(fm.circle_id, auth.uid())
                )
            );
    END IF;
END $$;

-- meeting_agenda_items: Contributors+ who are in the circle can insert
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_agenda_items_insert') THEN
        CREATE POLICY meeting_agenda_items_insert ON meeting_agenda_items
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_agenda_items.meeting_id
                    AND has_circle_role(fm.circle_id, auth.uid(), 'CONTRIBUTOR')
                )
                AND added_by = auth.uid()
            );
    END IF;
END $$;

-- meeting_agenda_items: Creator of item or admin can update
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_agenda_items_update') THEN
        CREATE POLICY meeting_agenda_items_update ON meeting_agenda_items
            FOR UPDATE USING (
                added_by = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_agenda_items.meeting_id
                    AND has_circle_role(fm.circle_id, auth.uid(), 'ADMIN')
                )
            );
    END IF;
END $$;

-- meeting_agenda_items: Creator of item or admin can delete
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_agenda_items_delete') THEN
        CREATE POLICY meeting_agenda_items_delete ON meeting_agenda_items
            FOR DELETE USING (
                added_by = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_agenda_items.meeting_id
                    AND has_circle_role(fm.circle_id, auth.uid(), 'ADMIN')
                )
            );
    END IF;
END $$;

-- meeting_action_items: Circle members can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_action_items_select') THEN
        CREATE POLICY meeting_action_items_select ON meeting_action_items
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_action_items.meeting_id
                    AND is_circle_member(fm.circle_id, auth.uid())
                )
            );
    END IF;
END $$;

-- meeting_action_items: Contributors+ can insert
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_action_items_insert') THEN
        CREATE POLICY meeting_action_items_insert ON meeting_action_items
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_action_items.meeting_id
                    AND has_circle_role(fm.circle_id, auth.uid(), 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

-- meeting_action_items: Contributors+ can update
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_action_items_update') THEN
        CREATE POLICY meeting_action_items_update ON meeting_action_items
            FOR UPDATE USING (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_action_items.meeting_id
                    AND has_circle_role(fm.circle_id, auth.uid(), 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

-- meeting_action_items: Contributors+ can delete
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'meeting_action_items_delete') THEN
        CREATE POLICY meeting_action_items_delete ON meeting_action_items
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM family_meetings fm
                    WHERE fm.id = meeting_action_items.meeting_id
                    AND has_circle_role(fm.circle_id, auth.uid(), 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- FUNCTION: get_suggested_meeting_topics
-- ============================================================================

CREATE OR REPLACE FUNCTION get_suggested_meeting_topics(
    p_circle_id uuid,
    p_patient_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_topics jsonb := '[]'::jsonb;
    v_overdue jsonb;
    v_binder jsonb;
BEGIN
    -- Check membership
    IF NOT is_circle_member(p_circle_id, auth.uid()) THEN
        RETURN '[]'::jsonb;
    END IF;

    -- Overdue tasks
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'topic_type', 'OVERDUE_TASK',
        'title', 'Overdue: ' || t.title,
        'description', 'Due ' || to_char(t.due_at, 'Mon DD'),
        'priority', 3,
        'source_id', t.id
    ) ORDER BY t.due_at), '[]'::jsonb)
    INTO v_overdue
    FROM tasks t
    WHERE t.circle_id = p_circle_id
      AND t.patient_id = p_patient_id
      AND t.status = 'OPEN'
      AND t.due_at < now()
    LIMIT 5;

    -- Recent binder changes (last 7 days)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'topic_type', 'BINDER_CHANGE',
        'title', CASE
            WHEN b.type = 'MED' THEN 'Medication update: ' || b.title
            ELSE 'Binder update: ' || b.title
        END,
        'description', 'Updated ' || to_char(b.updated_at, 'Mon DD'),
        'priority', 2,
        'source_id', b.id
    ) ORDER BY b.updated_at DESC), '[]'::jsonb)
    INTO v_binder
    FROM binder_items b
    WHERE b.circle_id = p_circle_id
      AND b.patient_id = p_patient_id
      AND b.updated_at > now() - interval '7 days'
      AND b.is_active = true
    LIMIT 3;

    -- Combine results
    v_topics := v_overdue || v_binder;

    RETURN v_topics;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_suggested_meeting_topics IS 'Get suggested meeting agenda topics from overdue tasks and recent binder changes';
