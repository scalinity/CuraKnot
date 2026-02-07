-- ============================================================================
-- Migration: Communication Logs Performance Indexes
-- Description: Add missing indexes for foreign keys and common filters
-- ============================================================================

-- Foreign key indexes (CRITICAL for JOIN and CASCADE performance)
CREATE INDEX IF NOT EXISTS idx_communication_logs_facility_id
    ON communication_logs(facility_id)
    WHERE facility_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_communication_logs_task_id
    ON communication_logs(follow_up_task_id)
    WHERE follow_up_task_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_communication_logs_handoff_id
    ON communication_logs(linked_handoff_id)
    WHERE linked_handoff_id IS NOT NULL;

-- call_type filter (CRITICAL - primary filter in search_communication_logs)
CREATE INDEX IF NOT EXISTS idx_communication_logs_call_type
    ON communication_logs(circle_id, call_type, call_date DESC);

-- created_by filter ("My Communications" view pattern)
CREATE INDEX IF NOT EXISTS idx_communication_logs_created_by
    ON communication_logs(created_by, call_date DESC);

-- communication_type filter (UI filter pattern)
CREATE INDEX IF NOT EXISTS idx_communication_logs_comm_type
    ON communication_logs(circle_id, communication_type, call_date DESC);
