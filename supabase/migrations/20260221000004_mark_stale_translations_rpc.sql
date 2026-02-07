-- ============================================================================
-- Migration: Add mark_stale_translations RPC function
-- Description: Database function to mark handoff translations as stale
--              when the source handoff content has been updated.
-- Date: 2026-02-21
-- ============================================================================

-- This function compares handoff_translations.created_at against
-- handoffs.updated_at. If the handoff was updated AFTER the translation
-- was created, the translation is marked stale.

CREATE OR REPLACE FUNCTION mark_stale_translations()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rows_affected integer;
BEGIN
    UPDATE handoff_translations ht
    SET is_stale = true
    FROM handoffs h
    WHERE ht.handoff_id = h.id
      AND ht.is_stale = false
      AND h.updated_at > ht.created_at;

    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    RETURN rows_affected;
END;
$$;

-- Only allow service role to execute this function
REVOKE ALL ON FUNCTION mark_stale_translations() FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_stale_translations() FROM anon;
REVOKE ALL ON FUNCTION mark_stale_translations() FROM authenticated;
