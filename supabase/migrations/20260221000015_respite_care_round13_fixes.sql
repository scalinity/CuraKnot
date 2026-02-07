-- Migration: Round 13 fixes for respite care feature
-- Addresses: SA2 (subscription enforcement on respite_reviews UPDATE policy)

-- =============================================================================
-- 1. Add subscription enforcement to respite_reviews UPDATE policy (SA2)
--    Consistent with respite_requests and respite_log UPDATE policies from R12.
--    Prevents downgraded users from modifying reviews.
-- =============================================================================

-- Drop existing UPDATE policies on respite_reviews and recreate with subscription check
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'respite_reviews'
      AND cmd = 'UPDATE'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.respite_reviews', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "Reviewers update own reviews with subscription"
  ON public.respite_reviews
  FOR UPDATE
  USING (
    has_feature_access(auth.uid(), 'respite_reviews')
    AND reviewer_id = auth.uid()
  )
  WITH CHECK (
    reviewer_id = auth.uid()
    AND reviewer_id = (SELECT rr.reviewer_id FROM public.respite_reviews rr WHERE rr.id = respite_reviews.id)
    AND provider_id = (SELECT rr.provider_id FROM public.respite_reviews rr WHERE rr.id = respite_reviews.id)
  );
