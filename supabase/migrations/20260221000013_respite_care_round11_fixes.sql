-- Migration: Round 11 fixes for respite care feature
-- Addresses: SA2 (UPDATE policy restrictions), CA1 (composite index), DB1 (immutability trigger)

-- =============================================================================
-- 1. Composite index on respite_log(circle_id, patient_id, start_date DESC)
--    for get_respite_days_this_year RPC performance (CA1)
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_respite_log_patient_year
  ON public.respite_log (circle_id, patient_id, start_date DESC);

-- =============================================================================
-- 2. Tighten respite_requests UPDATE policy to prevent FK mutation (SA2)
--    Only allow status changes, not provider_id/circle_id/patient_id/created_by.
-- =============================================================================

-- Drop existing UPDATE policy on respite_requests (if any) and recreate with restrictions
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'respite_requests'
      AND cmd = 'UPDATE'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.respite_requests', pol.policyname);
  END LOOP;
END $$;

-- Recreate UPDATE policy: creator or ADMIN/OWNER can update, but only status field
CREATE POLICY "Members update own or managed requests"
  ON public.respite_requests
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM circle_members cm
      WHERE cm.circle_id = respite_requests.circle_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'ACTIVE'
        AND (
          respite_requests.created_by = auth.uid()
          OR cm.role IN ('ADMIN', 'OWNER')
        )
    )
  )
  WITH CHECK (
    -- Immutable fields must not change
    circle_id = (SELECT rr.circle_id FROM public.respite_requests rr WHERE rr.id = respite_requests.id)
    AND patient_id = (SELECT rr.patient_id FROM public.respite_requests rr WHERE rr.id = respite_requests.id)
    AND provider_id = (SELECT rr.provider_id FROM public.respite_requests rr WHERE rr.id = respite_requests.id)
    AND created_by = (SELECT rr.created_by FROM public.respite_requests rr WHERE rr.id = respite_requests.id)
  );

-- =============================================================================
-- 3. Add immutability trigger for respite_requests critical fields (SA2)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.immutable_request_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.circle_id IS DISTINCT FROM OLD.circle_id THEN
    RAISE EXCEPTION 'circle_id cannot be modified' USING ERRCODE = '23514';
  END IF;
  IF NEW.patient_id IS DISTINCT FROM OLD.patient_id THEN
    RAISE EXCEPTION 'patient_id cannot be modified' USING ERRCODE = '23514';
  END IF;
  IF NEW.provider_id IS DISTINCT FROM OLD.provider_id THEN
    RAISE EXCEPTION 'provider_id cannot be modified' USING ERRCODE = '23514';
  END IF;
  IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'created_by cannot be modified' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_immutable_request_fields'
      AND tgrelid = 'public.respite_requests'::regclass
  ) THEN
    CREATE TRIGGER trg_immutable_request_fields
      BEFORE UPDATE ON public.respite_requests
      FOR EACH ROW
      WHEN (
        NEW.circle_id IS DISTINCT FROM OLD.circle_id
        OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
        OR NEW.provider_id IS DISTINCT FROM OLD.provider_id
        OR NEW.created_by IS DISTINCT FROM OLD.created_by
      )
      EXECUTE FUNCTION public.immutable_request_fields();
  END IF;
END $$;

-- =============================================================================
-- 4. Tighten respite_log UPDATE policy: only creator or ADMIN/OWNER (SA2)
-- =============================================================================

-- Drop existing UPDATE policies on respite_log
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'respite_log'
      AND cmd = 'UPDATE'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.respite_log', pol.policyname);
  END LOOP;
END $$;

-- Recreate UPDATE policy: only creator or circle ADMIN/OWNER can update entries
CREATE POLICY "Creator or admin updates respite log"
  ON public.respite_log
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM circle_members cm
      WHERE cm.circle_id = respite_log.circle_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'ACTIVE'
        AND (
          respite_log.created_by = auth.uid()
          OR cm.role IN ('ADMIN', 'OWNER')
        )
    )
  )
  WITH CHECK (
    -- created_by is immutable
    created_by = (SELECT rl.created_by FROM public.respite_log rl WHERE rl.id = respite_log.id)
    -- circle_id and patient_id are immutable
    AND circle_id = (SELECT rl.circle_id FROM public.respite_log rl WHERE rl.id = respite_log.id)
    AND patient_id = (SELECT rl.patient_id FROM public.respite_log rl WHERE rl.id = respite_log.id)
  );

-- =============================================================================
-- 5. Add immutability trigger for respite_log critical fields (SA2)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.immutable_log_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'created_by cannot be modified' USING ERRCODE = '23514';
  END IF;
  IF NEW.circle_id IS DISTINCT FROM OLD.circle_id THEN
    RAISE EXCEPTION 'circle_id cannot be modified' USING ERRCODE = '23514';
  END IF;
  IF NEW.patient_id IS DISTINCT FROM OLD.patient_id THEN
    RAISE EXCEPTION 'patient_id cannot be modified' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_immutable_log_fields'
      AND tgrelid = 'public.respite_log'::regclass
  ) THEN
    CREATE TRIGGER trg_immutable_log_fields
      BEFORE UPDATE ON public.respite_log
      FOR EACH ROW
      WHEN (
        NEW.created_by IS DISTINCT FROM OLD.created_by
        OR NEW.circle_id IS DISTINCT FROM OLD.circle_id
        OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
      )
      EXECUTE FUNCTION public.immutable_log_fields();
  END IF;
END $$;
