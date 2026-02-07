-- Migration: 0015_delegation
-- Description: Delegation Intelligence - task suggestions and workload balancing
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: member_stats
-- ============================================================================

CREATE TABLE member_stats (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stats_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    computed_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT member_stats_unique UNIQUE (circle_id, user_id)
);

CREATE INDEX member_stats_circle_idx ON member_stats(circle_id);
CREATE INDEX member_stats_computed_idx ON member_stats(computed_at);

COMMENT ON TABLE member_stats IS 'Aggregated member statistics for delegation suggestions';

-- ============================================================================
-- TABLE: task_tags
-- ============================================================================

CREATE TABLE task_tags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    tag text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT task_tags_unique UNIQUE (task_id, tag)
);

CREATE INDEX task_tags_task_idx ON task_tags(task_id);
CREATE INDEX task_tags_tag_idx ON task_tags(tag);

COMMENT ON TABLE task_tags IS 'Tags for categorizing tasks for delegation analysis';

-- ============================================================================
-- FUNCTION: compute_member_stats
-- ============================================================================

CREATE OR REPLACE FUNCTION compute_member_stats(p_circle_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_member RECORD;
    v_stats jsonb;
    v_members_updated int := 0;
BEGIN
    FOR v_member IN 
        SELECT cm.user_id, u.display_name
        FROM circle_members cm
        JOIN users u ON cm.user_id = u.id
        WHERE cm.circle_id = p_circle_id AND cm.status = 'ACTIVE'
    LOOP
        SELECT jsonb_build_object(
            'tasks_completed_7d', COUNT(*) FILTER (WHERE status = 'DONE' AND completed_at > now() - interval '7 days'),
            'tasks_completed_30d', COUNT(*) FILTER (WHERE status = 'DONE' AND completed_at > now() - interval '30 days'),
            'tasks_assigned_open', COUNT(*) FILTER (WHERE status = 'OPEN'),
            'tasks_created_7d', COUNT(*) FILTER (WHERE created_by = v_member.user_id AND created_at > now() - interval '7 days'),
            'avg_completion_time_hours', EXTRACT(EPOCH FROM AVG(completed_at - created_at) FILTER (WHERE status = 'DONE')) / 3600,
            'overdue_rate', ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'DONE' AND completed_at > due_at) / NULLIF(COUNT(*) FILTER (WHERE status = 'DONE' AND due_at IS NOT NULL), 0), 1)
        )
        INTO v_stats
        FROM tasks
        WHERE circle_id = p_circle_id AND owner_user_id = v_member.user_id;
        
        -- Add handoff stats
        v_stats := v_stats || (
            SELECT jsonb_build_object(
                'handoffs_created_7d', COUNT(*) FILTER (WHERE created_at > now() - interval '7 days'),
                'handoffs_created_30d', COUNT(*) FILTER (WHERE created_at > now() - interval '30 days')
            )
            FROM handoffs
            WHERE circle_id = p_circle_id AND created_by = v_member.user_id AND status = 'PUBLISHED'
        );
        
        -- Upsert stats
        INSERT INTO member_stats (circle_id, user_id, stats_json, computed_at)
        VALUES (p_circle_id, v_member.user_id, v_stats, now())
        ON CONFLICT (circle_id, user_id) DO UPDATE
        SET stats_json = v_stats, computed_at = now();
        
        v_members_updated := v_members_updated + 1;
    END LOOP;
    
    RETURN jsonb_build_object('members_updated', v_members_updated);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: suggest_task_owner
-- ============================================================================

CREATE OR REPLACE FUNCTION suggest_task_owner(
    p_circle_id uuid,
    p_task_type text DEFAULT NULL,
    p_priority text DEFAULT 'MED'
)
RETURNS jsonb AS $$
DECLARE
    v_suggestions jsonb := '[]'::jsonb;
    v_member RECORD;
    v_score numeric;
BEGIN
    FOR v_member IN
        SELECT 
            ms.user_id,
            u.display_name,
            ms.stats_json,
            COALESCE((ms.stats_json->>'tasks_assigned_open')::int, 0) as open_tasks,
            COALESCE((ms.stats_json->>'tasks_completed_7d')::int, 0) as completed_recent,
            COALESCE((ms.stats_json->>'overdue_rate')::numeric, 0) as overdue_rate
        FROM member_stats ms
        JOIN users u ON ms.user_id = u.id
        JOIN circle_members cm ON cm.circle_id = ms.circle_id AND cm.user_id = ms.user_id
        WHERE ms.circle_id = p_circle_id
          AND cm.status = 'ACTIVE'
          AND cm.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
    LOOP
        -- Calculate score (lower is better for assignment)
        -- Factors: current workload, reliability, activity
        v_score := v_member.open_tasks * 10  -- Penalize heavy workload
                 + v_member.overdue_rate * 0.5  -- Penalize overdue history
                 - v_member.completed_recent * 2;  -- Reward recent activity
        
        v_suggestions := v_suggestions || jsonb_build_array(jsonb_build_object(
            'user_id', v_member.user_id,
            'display_name', v_member.display_name,
            'score', v_score,
            'reasons', jsonb_build_array(
                CASE WHEN v_member.open_tasks < 3 THEN 'Low current workload' END,
                CASE WHEN v_member.completed_recent > 5 THEN 'Active recently' END,
                CASE WHEN v_member.overdue_rate < 10 THEN 'Reliable completion' END
            ) - 'null'
        ));
    END LOOP;
    
    -- Sort by score (ascending = better)
    SELECT jsonb_agg(elem ORDER BY (elem->>'score')::numeric ASC)
    INTO v_suggestions
    FROM jsonb_array_elements(v_suggestions) elem;
    
    RETURN COALESCE(v_suggestions, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: get_workload_dashboard
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workload_dashboard(
    p_circle_id uuid,
    p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb;
BEGIN
    -- Check admin permission
    IF NOT has_circle_role(p_circle_id, p_user_id, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Admin role required');
    END IF;
    
    SELECT jsonb_build_object(
        'members', (
            SELECT jsonb_agg(jsonb_build_object(
                'user_id', ms.user_id,
                'display_name', u.display_name,
                'stats', ms.stats_json,
                'computed_at', ms.computed_at
            ))
            FROM member_stats ms
            JOIN users u ON ms.user_id = u.id
            WHERE ms.circle_id = p_circle_id
        ),
        'circle_totals', jsonb_build_object(
            'open_tasks', (SELECT COUNT(*) FROM tasks WHERE circle_id = p_circle_id AND status = 'OPEN'),
            'completed_7d', (SELECT COUNT(*) FROM tasks WHERE circle_id = p_circle_id AND status = 'DONE' AND completed_at > now() - interval '7 days'),
            'handoffs_7d', (SELECT COUNT(*) FROM handoffs WHERE circle_id = p_circle_id AND status = 'PUBLISHED' AND created_at > now() - interval '7 days')
        )
    ) INTO v_result;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE member_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_tags ENABLE ROW LEVEL SECURITY;

-- member_stats: Own stats or admin can see all
CREATE POLICY member_stats_select ON member_stats
    FOR SELECT USING (
        user_id = auth.uid() OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

-- task_tags: Based on task access
CREATE POLICY task_tags_select ON task_tags
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_tags.task_id AND is_circle_member(t.circle_id, auth.uid()))
    );

CREATE POLICY task_tags_insert ON task_tags
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_tags.task_id AND has_circle_role(t.circle_id, auth.uid(), 'CONTRIBUTOR'))
    );
