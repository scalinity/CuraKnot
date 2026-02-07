-- Migration: 0008_billing
-- Description: Billing & Claims Organizer - financial items tracking
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: financial_items
-- ============================================================================

CREATE TABLE financial_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    kind text NOT NULL CHECK (kind IN ('BILL', 'CLAIM', 'EOB', 'AUTH', 'RECEIPT')),
    vendor text,
    amount_cents int,
    currency text DEFAULT 'USD' NOT NULL,
    due_at timestamptz,
    status text DEFAULT 'OPEN' NOT NULL CHECK (status IN ('OPEN', 'SUBMITTED', 'PAID', 'DENIED', 'CLOSED')),
    reference_id text,
    notes text,
    attachment_ids uuid[] DEFAULT '{}',
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX financial_items_circle_id_idx ON financial_items(circle_id);
CREATE INDEX financial_items_patient_id_idx ON financial_items(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX financial_items_status_idx ON financial_items(status);
CREATE INDEX financial_items_due_at_idx ON financial_items(due_at) WHERE due_at IS NOT NULL AND status = 'OPEN';
CREATE INDEX financial_items_kind_idx ON financial_items(kind);
CREATE INDEX financial_items_updated_at_idx ON financial_items(updated_at);

CREATE TRIGGER financial_items_updated_at
    BEFORE UPDATE ON financial_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE financial_items IS 'Bills, claims, EOBs, and other financial items for care management';

-- ============================================================================
-- TABLE: financial_item_tasks
-- ============================================================================

CREATE TABLE financial_item_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    financial_item_id uuid NOT NULL REFERENCES financial_items(id) ON DELETE CASCADE,
    task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT financial_item_tasks_unique UNIQUE (financial_item_id, task_id)
);

CREATE INDEX financial_item_tasks_item_idx ON financial_item_tasks(financial_item_id);
CREATE INDEX financial_item_tasks_task_idx ON financial_item_tasks(task_id);

COMMENT ON TABLE financial_item_tasks IS 'Junction table linking financial items to follow-up tasks';

-- ============================================================================
-- VIEW: financial_items_with_status
-- ============================================================================

CREATE OR REPLACE VIEW financial_items_with_status AS
SELECT 
    f.*,
    CASE 
        WHEN f.status IN ('PAID', 'DENIED', 'CLOSED') THEN 'resolved'
        WHEN f.due_at IS NOT NULL AND f.due_at < now() THEN 'overdue'
        WHEN f.due_at IS NOT NULL AND f.due_at < now() + interval '7 days' THEN 'due_soon'
        ELSE 'pending'
    END as computed_status,
    COALESCE(f.amount_cents, 0) / 100.0 as amount_dollars
FROM financial_items f;

COMMENT ON VIEW financial_items_with_status IS 'Financial items with computed due status';

-- ============================================================================
-- FUNCTION: get_financial_summary
-- ============================================================================

CREATE OR REPLACE FUNCTION get_financial_summary(
    p_circle_id uuid,
    p_user_id uuid,
    p_start_date date DEFAULT NULL,
    p_end_date date DEFAULT NULL,
    p_patient_id uuid DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_summary jsonb;
BEGIN
    -- Check membership
    IF NOT is_circle_member(p_circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;
    
    SELECT jsonb_build_object(
        'total_open', COALESCE(SUM(CASE WHEN status = 'OPEN' THEN amount_cents ELSE 0 END), 0),
        'total_paid', COALESCE(SUM(CASE WHEN status = 'PAID' THEN amount_cents ELSE 0 END), 0),
        'total_denied', COALESCE(SUM(CASE WHEN status = 'DENIED' THEN amount_cents ELSE 0 END), 0),
        'count_by_status', jsonb_build_object(
            'open', COUNT(*) FILTER (WHERE status = 'OPEN'),
            'submitted', COUNT(*) FILTER (WHERE status = 'SUBMITTED'),
            'paid', COUNT(*) FILTER (WHERE status = 'PAID'),
            'denied', COUNT(*) FILTER (WHERE status = 'DENIED'),
            'closed', COUNT(*) FILTER (WHERE status = 'CLOSED')
        ),
        'count_by_kind', jsonb_build_object(
            'bill', COUNT(*) FILTER (WHERE kind = 'BILL'),
            'claim', COUNT(*) FILTER (WHERE kind = 'CLAIM'),
            'eob', COUNT(*) FILTER (WHERE kind = 'EOB'),
            'auth', COUNT(*) FILTER (WHERE kind = 'AUTH'),
            'receipt', COUNT(*) FILTER (WHERE kind = 'RECEIPT')
        ),
        'overdue_count', COUNT(*) FILTER (WHERE status = 'OPEN' AND due_at < now()),
        'due_soon_count', COUNT(*) FILTER (WHERE status = 'OPEN' AND due_at >= now() AND due_at < now() + interval '7 days')
    ) INTO v_summary
    FROM financial_items
    WHERE circle_id = p_circle_id
      AND (p_patient_id IS NULL OR patient_id = p_patient_id)
      AND (p_start_date IS NULL OR created_at >= p_start_date)
      AND (p_end_date IS NULL OR created_at <= p_end_date + interval '1 day');
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_financial_summary IS 'Get aggregated financial summary for a circle';

-- ============================================================================
-- FUNCTION: create_financial_reminder_task
-- ============================================================================

CREATE OR REPLACE FUNCTION create_financial_reminder_task(
    p_financial_item_id uuid,
    p_user_id uuid,
    p_title text DEFAULT NULL,
    p_due_at timestamptz DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_item financial_items%ROWTYPE;
    v_task_id uuid;
    v_task_title text;
BEGIN
    -- Get the financial item
    SELECT * INTO v_item FROM financial_items WHERE id = p_financial_item_id;
    
    IF v_item IS NULL THEN
        RETURN jsonb_build_object('error', 'Financial item not found');
    END IF;
    
    -- Check permissions
    IF NOT has_circle_role(v_item.circle_id, p_user_id, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;
    
    -- Build task title
    v_task_title := COALESCE(
        p_title,
        'Follow up: ' || v_item.kind || COALESCE(' - ' || v_item.vendor, '')
    );
    
    -- Create task
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
        p_user_id,
        v_task_title,
        'Related to ' || v_item.kind || CASE 
            WHEN v_item.reference_id IS NOT NULL THEN ' #' || v_item.reference_id
            ELSE ''
        END,
        COALESCE(p_due_at, v_item.due_at),
        CASE 
            WHEN v_item.due_at < now() THEN 'HIGH'
            ELSE 'MED'
        END
    )
    RETURNING id INTO v_task_id;
    
    -- Link task to financial item
    INSERT INTO financial_item_tasks (financial_item_id, task_id)
    VALUES (p_financial_item_id, v_task_id);
    
    RETURN jsonb_build_object(
        'task_id', v_task_id,
        'financial_item_id', p_financial_item_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_financial_reminder_task IS 'Create a reminder task linked to a financial item';

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE financial_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_item_tasks ENABLE ROW LEVEL SECURITY;

-- financial_items: Circle members can read
CREATE POLICY financial_items_select ON financial_items
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- financial_items: Contributors+ can insert
CREATE POLICY financial_items_insert ON financial_items
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- financial_items: Contributors+ can update
CREATE POLICY financial_items_update ON financial_items
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- financial_items: Admin+ can delete
CREATE POLICY financial_items_delete ON financial_items
    FOR DELETE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- financial_item_tasks: Based on financial_items access
CREATE POLICY financial_item_tasks_select ON financial_item_tasks
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM financial_items f 
            WHERE f.id = financial_item_tasks.financial_item_id 
            AND is_circle_member(f.circle_id, auth.uid())
        )
    );

CREATE POLICY financial_item_tasks_insert ON financial_item_tasks
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM financial_items f 
            WHERE f.id = financial_item_tasks.financial_item_id 
            AND has_circle_role(f.circle_id, auth.uid(), 'CONTRIBUTOR')
        )
    );
