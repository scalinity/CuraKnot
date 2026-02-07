-- Migration: Calendar Security Enhancements
-- Description: Add HMAC checksum column for data integrity verification
-- Date: 2026-02-06
-- SECURITY: Part of SA3 Data Flow Security fixes

-- ============================================================================
-- Add data_checksum column to calendar_events
-- ============================================================================

-- SECURITY: HMAC-SHA256 checksum for integrity verification
-- Computed on write, verified on read to detect tampering
ALTER TABLE calendar_events
ADD COLUMN IF NOT EXISTS data_checksum text;

-- Add comment explaining security purpose
COMMENT ON COLUMN calendar_events.data_checksum IS
    'HMAC-SHA256 checksum for data integrity verification. Computed client-side before persist, verified on read.';

-- ============================================================================
-- Note: conflict_data_json encryption is handled client-side
-- ============================================================================
-- The conflict_data_json column stores encrypted data when written by iOS client.
-- Legacy unencrypted data is handled with fallback in the client code.
-- No server-side migration needed for encryption - it's transparent to the database.

COMMENT ON COLUMN calendar_events.conflict_data_json IS
    'Encrypted JSON containing conflict data (local and external versions). Encrypted client-side with AES-GCM.';
