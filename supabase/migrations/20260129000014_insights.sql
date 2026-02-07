-- Migration: 0014_insights
-- Description: Operational Insights & Alerts - digests and proactive alerts
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: insight_digests
-- ============================================================================

CREATE TABLE insight_digests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE CASCADE,
    period_start date NOT NULL,
    period_end date NOT NULL,
    digest_json jsonb NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX insight_digests_circle_idx ON insight_digests(circle_id);
CREATE INDEX insight_digests_patient_idx ON insight_digests(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX insight_digests_period_idx ON insight_digests(period_end DESC);

COMMENT ON TABLE insight_digests IS 'Weekly/periodic insight digests for circles';

-- ============================================================================
-- TABLE: alert_rules
-- ============================================================================

CREATE TABLE alert_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE CASCADE,
    rule_key text NOT NULL,
    params_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    enabled boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX alert_rules_circle_idx ON alert_rules(circle_id);
CREATE INDEX alert_rules_enabled_idx ON alert_rules(circle_id, enabled) WHERE enabled = true;

CREATE TRIGGER alert_rules_updated_at
    BEFORE UPDATE ON alert_rules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE alert_rules IS 'Configurable alert rules for operational monitoring';
COMMENT ON COLUMN alert_rules.rule_key IS 'Rule types: OVERDUE_TASKS, UNCONFIRMED_MEDS, STALENESS, REPEATED_EDITS';

-- ============================================================================
-- TABLE: alert_events
-- ============================================================================

CREATE TABLE alert_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL,
    patient_id uuid,
    rule_key text NOT NULL,
    fired_at timestamptz DEFAULT now() NOT NULL,
    payload_json jsonb NOT NULL,
    status text DEFAULT 'OPEN' NOT NULL CHECK (status IN ('OPEN', 'ACKNOWLEDGED', 'DISMISSED')),
    acknowledged_by uuid REFERENCES users(id) ON DELETE SET NULL,
    acknowledged_at timestamptz,
    dismissed_by uuid REFERENCES users(id) ON DELETE SET NULL,
    dismissed_at timestamptz
);

CREATE INDEX alert_events_circle_idx ON alert_events(circle_id);
CREATE INDEX alert_events_status_idx ON alert_events(status) WHERE status = 'OPEN';
CREATE INDEX alert_events_fired_idx ON alert_events(fired_at DESC);

COMMENT ON TABLE alert_events IS 'Fired alerts from rule evaluations';

-- ============================================================================
-- FUNCTION: generate_weekly_digest
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_weekly_digest(p_circle_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_digest jsonb;
    v_period_start date;
    v_period_end date;
    v_handoff_count int;
    v_task_completed int;
    v_task_created int;
    v_task_overdue int;
    v_med_changes int;
    v_highlights jsonb;
BEGIN
    v_period_end := current_date;
    v_period_start := v_period_end - 7;
    
    -- Count handoffs
    SELECT COUNT(*) INTO v_handoff_count
    FROM handoffs
    WHERE circle_id = p_circle_id
      AND status = 'PUBLISHED'
      AND created_at >= v_period_start
      AND created_at < v_period_end + 1;
    
    -- Count tasks
    SELECT 
        COUNT(*) FILTER (WHERE status = 'DONE' AND completed_at >= v_period_start),
        COUNT(*) FILTER (WHERE created_at >= v_period_start),
        COUNT(*) FILTER (WHERE status = 'OPEN' AND due_at < now())
    INTO v_task_completed, v_task_created, v_task_overdue
    FROM tasks
    WHERE circle_id = p_circle_id;
    
    -- Count med changes
    SELECT COUNT(*) INTO v_med_changes
    FROM binder_items
    WHERE circle_id = p_circle_id
      AND type = 'MED'
      AND updated_at >= v_period_start
      AND updated_at < v_period_end + 1;
    
    -- Build highlights
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'title', h.title,
        'type', h.type,
        'created_at', h.created_at
    ) ORDER BY h.created_at DESC), '[]'::jsonb)
    INTO v_highlights
    FROM handoffs h
    WHERE h.circle_id = p_circle_id
      AND h.status = 'PUBLISHED'
      AND h.created_at >= v_period_start
    LIMIT 5;
    
    v_digest := jsonb_build_object(
        'period', jsonb_build_object('start', v_period_start, 'end', v_period_end),
        'summary', jsonb_build_object(
            'handoffs', v_handoff_count,
            'tasks_completed', v_task_completed,
            'tasks_created', v_task_created,
            'tasks_overdue', v_task_overdue,
            'med_changes', v_med_changes
        ),
        'highlights', v_highlights,
        'generated_at', now()
    );
    
    -- Store digest
    INSERT INTO insight_digests (circle_id, period_start, period_end, digest_json)
    VALUES (p_circle_id, v_period_start, v_period_end, v_digest);
    
    RETURN v_digest;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: evaluate_alerts
-- ============================================================================

CREATE OR REPLACE FUNCTION evaluate_alerts(p_circle_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_rule alert_rules%ROWTYPE;
    v_alerts_fired int := 0;
    v_overdue_count int;
    v_staleness_days int;
BEGIN
    FOR v_rule IN SELECT * FROM alert_rules WHERE circle_id = p_circle_id AND enabled = true
    LOOP
        CASE v_rule.rule_key
            WHEN 'OVERDUE_TASKS' THEN
                SELECT COUNT(*) INTO v_overdue_count
                FROM tasks
                WHERE circle_id = p_circle_id
                  AND (v_rule.patient_id IS NULL OR patient_id = v_rule.patient_id)
                  AND status = 'OPEN'
                  AND due_at < now();
                
                IF v_overdue_count >= COALESCE((v_rule.params_json->>'threshold')::int, 3) THEN
                    -- Check if already fired today
                    IF NOT EXISTS (
                        SELECT 1 FROM alert_events
                        WHERE circle_id = p_circle_id
                          AND rule_key = 'OVERDUE_TASKS'
                          AND fired_at > now() - interval '24 hours'
                          AND status = 'OPEN'
                    ) THEN
                        INSERT INTO alert_events (circle_id, patient_id, rule_key, payload_json)
                        VALUES (p_circle_id, v_rule.patient_id, 'OVERDUE_TASKS',
                            jsonb_build_object('count', v_overdue_count));
                        v_alerts_fired := v_alerts_fired + 1;
                    END IF;
                END IF;
                
            WHEN 'STALENESS' THEN
                SELECT EXTRACT(DAY FROM now() - MAX(created_at))::int INTO v_staleness_days
                FROM handoffs
                WHERE circle_id = p_circle_id
                  AND (v_rule.patient_id IS NULL OR patient_id = v_rule.patient_id)
                  AND status = 'PUBLISHED';
                
                IF v_staleness_days >= COALESCE((v_rule.params_json->>'days')::int, 7) THEN
                    IF NOT EXISTS (
                        SELECT 1 FROM alert_events
                        WHERE circle_id = p_circle_id
                          AND rule_key = 'STALENESS'
                          AND fired_at > now() - interval '24 hours'
                          AND status = 'OPEN'
                    ) THEN
                        INSERT INTO alert_events (circle_id, patient_id, rule_key, payload_json)
                        VALUES (p_circle_id, v_rule.patient_id, 'STALENESS',
                            jsonb_build_object('days_since_update', v_staleness_days));
                        v_alerts_fired := v_alerts_fired + 1;
                    END IF;
                END IF;
        END CASE;
    END LOOP;
    
    RETURN jsonb_build_object('alerts_fired', v_alerts_fired);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE insight_digests ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY insight_digests_select ON insight_digests
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

CREATE POLICY alert_rules_select ON alert_rules
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

CREATE POLICY alert_rules_insert ON alert_rules
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

CREATE POLICY alert_rules_update ON alert_rules
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

CREATE POLICY alert_events_select ON alert_events
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

CREATE POLICY alert_events_update ON alert_events
    FOR UPDATE USING (is_circle_member(circle_id, auth.uid()));
