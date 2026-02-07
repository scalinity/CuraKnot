-- Migration: 0003_tasks
-- Description: tasks table with completion tracking
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: tasks
-- ============================================================================

CREATE TABLE tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    handoff_id uuid REFERENCES handoffs(id) ON DELETE SET NULL,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    owner_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title text NOT NULL,
    description text,
    due_at timestamptz,
    priority text DEFAULT 'MED' NOT NULL CHECK (priority IN ('LOW', 'MED', 'HIGH')),
    status text DEFAULT 'OPEN' NOT NULL CHECK (status IN ('OPEN', 'DONE', 'CANCELED')),
    completed_at timestamptz,
    completed_by uuid REFERENCES users(id) ON DELETE SET NULL,
    completion_note text,
    reminder_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX tasks_circle_id_idx ON tasks(circle_id);
CREATE INDEX tasks_owner_user_id_idx ON tasks(owner_user_id);
CREATE INDEX tasks_status_idx ON tasks(status);
CREATE INDEX tasks_due_at_idx ON tasks(due_at) WHERE due_at IS NOT NULL AND status = 'OPEN';
CREATE INDEX tasks_handoff_id_idx ON tasks(handoff_id) WHERE handoff_id IS NOT NULL;
CREATE INDEX tasks_patient_id_idx ON tasks(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX tasks_updated_at_idx ON tasks(updated_at);

CREATE TRIGGER tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE tasks IS 'Actionable items with assignments and reminders';

-- ============================================================================
-- FUNCTION: complete_task
-- ============================================================================

CREATE OR REPLACE FUNCTION complete_task(
    p_task_id uuid,
    p_user_id uuid,
    p_completion_note text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_task tasks%ROWTYPE;
BEGIN
    -- Get the task
    SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
    
    IF v_task IS NULL THEN
        RETURN jsonb_build_object('error', 'Task not found');
    END IF;
    
    -- Check if user can complete (must be assignee, creator, or admin+)
    IF v_task.owner_user_id != p_user_id 
       AND v_task.created_by != p_user_id
       AND NOT has_circle_role(v_task.circle_id, p_user_id, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Permission denied');
    END IF;
    
    -- Check if already completed
    IF v_task.status = 'DONE' THEN
        RETURN jsonb_build_object('error', 'Task already completed');
    END IF;
    
    -- Complete the task
    UPDATE tasks
    SET 
        status = 'DONE',
        completed_at = now(),
        completed_by = p_user_id,
        completion_note = p_completion_note,
        updated_at = now()
    WHERE id = p_task_id;
    
    RETURN jsonb_build_object(
        'task_id', p_task_id,
        'status', 'DONE',
        'completed_at', now(),
        'completed_by', p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION complete_task IS 'Mark a task as completed with immutable completion log';

-- ============================================================================
-- VIEW: tasks_with_overdue
-- ============================================================================

CREATE OR REPLACE VIEW tasks_with_status AS
SELECT 
    t.*,
    CASE 
        WHEN t.status = 'DONE' THEN 'done'
        WHEN t.status = 'CANCELED' THEN 'canceled'
        WHEN t.due_at < now() THEN 'overdue'
        WHEN t.due_at < now() + interval '24 hours' THEN 'due_soon'
        ELSE 'open'
    END as computed_status
FROM tasks t;

COMMENT ON VIEW tasks_with_status IS 'Tasks with computed overdue status';
