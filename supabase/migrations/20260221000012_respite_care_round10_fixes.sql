-- Migration: Round 10 fixes for respite care feature
-- Addresses: DB1 (rate limit p_window_seconds ignored, review immutability trigger)

-- =============================================================================
-- 1. Fix check_rate_limit to honor p_window_seconds parameter
-- =============================================================================

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
  -- Calculate the start of the current window using the provided window size
  v_window_start := to_timestamp(
    floor(EXTRACT(EPOCH FROM now()) / p_window_seconds) * p_window_seconds
  );

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

-- =============================================================================
-- 2. Add immutability trigger for respite_reviews (defense-in-depth for SA2)
--    Prevents reviewer_id and provider_id from being changed on UPDATE.
--    The RLS WITH CHECK already prevents this at the policy level, but a
--    trigger provides belt-and-suspenders protection with clear error messages.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.immutable_review_identifiers()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.reviewer_id IS DISTINCT FROM OLD.reviewer_id THEN
    RAISE EXCEPTION 'reviewer_id cannot be modified' USING ERRCODE = '23514';
  END IF;
  IF NEW.provider_id IS DISTINCT FROM OLD.provider_id THEN
    RAISE EXCEPTION 'provider_id cannot be modified' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_immutable_review_identifiers'
      AND tgrelid = 'public.respite_reviews'::regclass
  ) THEN
    CREATE TRIGGER trg_immutable_review_identifiers
      BEFORE UPDATE ON public.respite_reviews
      FOR EACH ROW
      WHEN (NEW.reviewer_id IS DISTINCT FROM OLD.reviewer_id OR NEW.provider_id IS DISTINCT FROM OLD.provider_id)
      EXECUTE FUNCTION public.immutable_review_identifiers();
  END IF;
END $$;
