-- ============================================================================
-- Migration: Tighten Translation RLS Policies
-- Description: Restrict overly-permissive INSERT/UPDATE policies on
--              handoff_translations and translation_cache to service role only
-- Date: 2026-02-21
-- ============================================================================

-- Drop the overly permissive policies
DROP POLICY IF EXISTS "Service can insert handoff translations" ON handoff_translations;
DROP POLICY IF EXISTS "Service can update handoff translations" ON handoff_translations;
DROP POLICY IF EXISTS "Service manages translation cache" ON translation_cache;

-- Recreate with proper service-role-only checks.
-- Service role key bypasses RLS by default in Supabase, so these tables
-- should have NO INSERT/UPDATE/DELETE policies for normal users.
-- Only the SELECT policy for circle members remains for handoff_translations.
-- translation_cache is fully service-managed (no user-facing policies needed).

-- The service role bypasses RLS, so we don't need explicit INSERT/UPDATE
-- policies for it. Removing the permissive policies prevents any
-- authenticated user from inserting/updating these tables directly.

-- For translation_cache: remove the ALL policy and replace with
-- service-role-only access (which is implicit via RLS bypass)
-- No user should directly read the cache either - it's backend only.
