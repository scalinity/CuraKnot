-- Migration: Round 12 fixes for respite care feature
-- Addresses: SA2 (RPC authorization, subscription enforcement in UPDATE policies),
--            DB1 (services_json CHECK constraint), SA2 (explicit DELETE deny)

-- =============================================================================
-- 1. Add authorization check to get_respite_days_this_year RPC (SA2-CRITICAL)
--    Prevents any authenticated user from querying respite days for arbitrary circles.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_respite_days_this_year(
    p_circle_id uuid,
    p_patient_id uuid
)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_total int;
BEGIN
    -- Authorization: caller must be an active member of the circle
    IF NOT EXISTS (
        SELECT 1 FROM circle_members
        WHERE circle_id = p_circle_id
          AND user_id = auth.uid()
          AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'Not a member of this circle' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(SUM(total_days), 0) INTO v_total
    FROM respite_log
    WHERE circle_id = p_circle_id
      AND patient_id = p_patient_id
      AND start_date >= date_trunc('year', now())::date;

    RETURN v_total;
END;
$$;

-- =============================================================================
-- 2. Add subscription enforcement to respite_requests UPDATE policy (SA2)
--    Prevents downgraded users from modifying requests.
-- =============================================================================

-- Drop existing UPDATE policies on respite_requests and recreate with subscription check
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

CREATE POLICY "Members update own or managed requests"
  ON public.respite_requests
  FOR UPDATE
  USING (
    has_feature_access(auth.uid(), 'respite_requests')
    AND EXISTS (
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
-- 3. Add subscription enforcement to respite_log UPDATE policy (SA2)
--    Prevents downgraded users from modifying log entries.
-- =============================================================================

-- Drop existing UPDATE policies on respite_log and recreate with subscription check
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

CREATE POLICY "Creator or admin updates respite log"
  ON public.respite_log
  FOR UPDATE
  USING (
    has_feature_access(auth.uid(), 'respite_tracking')
    AND EXISTS (
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
    -- created_by, circle_id, patient_id are immutable
    created_by = (SELECT rl.created_by FROM public.respite_log rl WHERE rl.id = respite_log.id)
    AND circle_id = (SELECT rl.circle_id FROM public.respite_log rl WHERE rl.id = respite_log.id)
    AND patient_id = (SELECT rl.patient_id FROM public.respite_log rl WHERE rl.id = respite_log.id)
  );

-- =============================================================================
-- 4. Explicit DELETE deny on respite_requests for audit trail preservation (SA2)
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'respite_requests'
      AND cmd = 'DELETE'
  ) THEN
    CREATE POLICY "Prevent deletion of requests for audit trail"
      ON public.respite_requests
      FOR DELETE
      USING (false);
  END IF;
END $$;

-- =============================================================================
-- 5. CHECK constraint on respite_providers.services_json array length (DB1)
--    Prevents unbounded growth of services array.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE table_schema = 'public'
      AND table_name = 'respite_providers'
      AND constraint_name = 'check_services_array_length'
  ) THEN
    ALTER TABLE public.respite_providers
      ADD CONSTRAINT check_services_array_length
      CHECK (jsonb_array_length(services_json) <= 50);
  END IF;
END $$;
