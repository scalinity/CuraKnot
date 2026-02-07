-- Migration: Round 9 fixes for respite care feature
-- Addresses: DB1 (FK mismatch), SA2 (UPDATE policy), CA1 (composite index), SA1 (rate limiting)

-- =============================================================================
-- 1. Fix FK mismatch: respite_reviews.reviewer_id should reference public.users
--    so PostgREST embedding (users!reviewer_id) resolves correctly.
-- =============================================================================

-- Drop the existing FK to auth.users and add one to public.users
DO $$
BEGIN
  -- Find and drop existing FK on reviewer_id
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public'
      AND tc.table_name = 'respite_reviews'
      AND tc.constraint_type = 'FOREIGN KEY'
      AND ccu.column_name = 'id'
      AND ccu.table_name = 'users'
      AND ccu.table_schema = 'auth'
  ) THEN
    -- Get the constraint name dynamically and drop it
    EXECUTE (
      SELECT 'ALTER TABLE public.respite_reviews DROP CONSTRAINT ' || quote_ident(tc.constraint_name)
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
      WHERE tc.table_schema = 'public'
        AND tc.table_name = 'respite_reviews'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND kcu.column_name = 'reviewer_id'
      LIMIT 1
    );
  END IF;
END $$;

-- Add FK to public.users(id) instead
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public'
      AND tc.table_name = 'respite_reviews'
      AND tc.constraint_type = 'FOREIGN KEY'
      AND kcu.column_name = 'reviewer_id'
      AND ccu.table_name = 'users'
      AND ccu.table_schema = 'public'
  ) THEN
    ALTER TABLE public.respite_reviews
      ADD CONSTRAINT respite_reviews_reviewer_id_fkey
      FOREIGN KEY (reviewer_id) REFERENCES public.users(id);
  END IF;
END $$;

-- =============================================================================
-- 2. Add UPDATE policy on respite_reviews (reviewer can update own review)
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'respite_reviews'
      AND policyname = 'Reviewers update own reviews'
  ) THEN
    CREATE POLICY "Reviewers update own reviews"
      ON public.respite_reviews
      FOR UPDATE
      USING (reviewer_id = auth.uid())
      WITH CHECK (
        reviewer_id = auth.uid()
        -- Prevent changing reviewer_id or provider_id on update
        AND reviewer_id = (SELECT rr.reviewer_id FROM public.respite_reviews rr WHERE rr.id = respite_reviews.id)
        AND provider_id = (SELECT rr.provider_id FROM public.respite_reviews rr WHERE rr.id = respite_reviews.id)
      );
  END IF;
END $$;

-- =============================================================================
-- 3. Add composite index for reminder query performance (CA1)
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_respite_log_recent_lookup
  ON public.respite_log (circle_id, start_date, end_date);

-- =============================================================================
-- 4. Rate limiting table and function (SA1)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.api_rate_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  endpoint text NOT NULL,
  window_start timestamptz NOT NULL DEFAULT now(),
  request_count int NOT NULL DEFAULT 1,
  UNIQUE (user_id, endpoint, window_start)
);

-- RLS: only service role should access this table
ALTER TABLE public.api_rate_limits ENABLE ROW LEVEL SECURITY;

-- No policies = only service role key can read/write (which is what we want)

-- Rate limit check function: returns true if within limit, false if exceeded
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_user_id uuid,
  p_endpoint text,
  p_max_requests int DEFAULT 60,
  p_window_seconds int DEFAULT 60
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_start timestamptz;
  v_count int;
BEGIN
  -- Calculate the start of the current window
  v_window_start := date_trunc('minute', now());

  -- Try to increment existing counter
  UPDATE api_rate_limits
  SET request_count = request_count + 1
  WHERE user_id = p_user_id
    AND endpoint = p_endpoint
    AND window_start = v_window_start
  RETURNING request_count INTO v_count;

  IF v_count IS NOT NULL THEN
    RETURN v_count <= p_max_requests;
  END IF;

  -- No existing record for this window — insert one
  INSERT INTO api_rate_limits (user_id, endpoint, window_start, request_count)
  VALUES (p_user_id, p_endpoint, v_window_start, 1)
  ON CONFLICT (user_id, endpoint, window_start)
  DO UPDATE SET request_count = api_rate_limits.request_count + 1
  RETURNING request_count INTO v_count;

  RETURN v_count <= p_max_requests;
END;
$$;

-- Cleanup old rate limit records (run periodically via cron or trigger)
CREATE OR REPLACE FUNCTION public.cleanup_rate_limits()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM api_rate_limits
  WHERE window_start < now() - interval '5 minutes';
$$;
