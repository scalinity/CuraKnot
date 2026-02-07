-- ============================================================================
-- Migration: Communication Logs Sync Index
-- Description: Add updated_at index for sync cursor pattern
-- ============================================================================

-- Index for sync operations (cursor-based incremental sync)
CREATE INDEX IF NOT EXISTS idx_communication_logs_updated_at
    ON communication_logs(updated_at);
