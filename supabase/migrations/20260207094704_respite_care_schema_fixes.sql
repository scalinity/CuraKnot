-- ============================================================================
-- Migration: Respite Care Schema Fixes
-- Fixes schema mismatches between database and iOS models:
--   1. Rename user_id -> reviewer_id in respite_reviews
--   2. Replace multi-rating columns with single rating column
--   3. Replace review_text with title + body + service_date
--   4. Add COMPLETED to request status constraint
--   5. Add SLIDING_SCALE and FREE to pricing_model constraint
--   6. Fix RLS policies to use reviewer_id and add circle membership check
--   7. Fix review stats trigger to use rating instead of overall_rating
--   8. Change get_respite_days_this_year to SECURITY INVOKER
--   9. Add spatial index for geo queries
-- ============================================================================

-- ============================================================================
-- 1. Fix respite_reviews table structure
-- ============================================================================

-- Drop dependent objects first
DROP TRIGGER IF EXISTS trg_update_provider_review_stats ON respite_reviews;
DROP TRIGGER IF EXISTS trg_respite_reviews_updated_at ON respite_reviews;

-- Drop existing RLS policies on respite_reviews
DO $$ BEGIN
    DROP POLICY IF EXISTS "Authenticated users read reviews" ON respite_reviews;
    DROP POLICY IF EXISTS "Subscribers create reviews" ON respite_reviews;
    DROP POLICY IF EXISTS "Users delete own reviews" ON respite_reviews;
END $$;

-- Drop the unique constraint on (provider_id, user_id)
ALTER TABLE respite_reviews DROP CONSTRAINT IF EXISTS respite_reviews_provider_id_user_id_key;

-- Drop old index
DROP INDEX IF EXISTS idx_respite_reviews_user;

-- Rename user_id to reviewer_id
ALTER TABLE respite_reviews RENAME COLUMN user_id TO reviewer_id;

-- Drop old rating columns
ALTER TABLE respite_reviews DROP COLUMN IF EXISTS overall_rating;
ALTER TABLE respite_reviews DROP COLUMN IF EXISTS staff_rating;
ALTER TABLE respite_reviews DROP COLUMN IF EXISTS cleanliness_rating;
ALTER TABLE respite_reviews DROP COLUMN IF EXISTS activities_rating;

-- Drop old review_text
ALTER TABLE respite_reviews DROP COLUMN IF EXISTS review_text;

-- Add new columns
ALTER TABLE respite_reviews ADD COLUMN IF NOT EXISTS rating int NOT NULL DEFAULT 3 CHECK (rating BETWEEN 1 AND 5);
ALTER TABLE respite_reviews ADD COLUMN IF NOT EXISTS title text CHECK (length(title) <= 200);
ALTER TABLE respite_reviews ADD COLUMN IF NOT EXISTS body text CHECK (length(body) <= 5000);
ALTER TABLE respite_reviews ADD COLUMN IF NOT EXISTS service_date date;

-- Remove the DEFAULT on rating (was just for the ALTER ADD)
ALTER TABLE respite_reviews ALTER COLUMN rating DROP DEFAULT;

-- Add unique constraint on (provider_id, reviewer_id)
ALTER TABLE respite_reviews ADD CONSTRAINT respite_reviews_provider_id_reviewer_id_key UNIQUE (provider_id, reviewer_id);

-- Create index on reviewer_id
CREATE INDEX IF NOT EXISTS idx_respite_reviews_reviewer ON respite_reviews(reviewer_id);

-- ============================================================================
-- 2. Fix request status constraint to include COMPLETED
-- ============================================================================

ALTER TABLE respite_requests DROP CONSTRAINT IF EXISTS respite_requests_status_check;
ALTER TABLE respite_requests ADD CONSTRAINT respite_requests_status_check
    CHECK (status IN ('PENDING', 'CONFIRMED', 'DECLINED', 'CANCELLED', 'COMPLETED'));

-- ============================================================================
-- 3. Fix pricing_model constraint to include SLIDING_SCALE and FREE
-- ============================================================================

ALTER TABLE respite_providers DROP CONSTRAINT IF EXISTS respite_providers_pricing_model_check;
ALTER TABLE respite_providers ADD CONSTRAINT respite_providers_pricing_model_check
    CHECK (pricing_model IN ('HOURLY', 'DAILY', 'WEEKLY', 'SLIDING_SCALE', 'FREE'));

-- ============================================================================
-- 4. Recreate RLS policies with reviewer_id and circle membership check
-- ============================================================================

CREATE POLICY "Authenticated users read reviews" ON respite_reviews
    FOR SELECT TO authenticated
    USING (status = 'PUBLISHED');

CREATE POLICY "Subscribers create reviews" ON respite_reviews
    FOR INSERT TO authenticated
    WITH CHECK (
        reviewer_id = auth.uid()
        AND has_feature_access(auth.uid(), 'respite_reviews')
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = respite_reviews.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
        )
    );

CREATE POLICY "Users delete own reviews" ON respite_reviews
    FOR DELETE TO authenticated
    USING (reviewer_id = auth.uid());

-- ============================================================================
-- 5. Recreate review stats trigger using rating column
-- ============================================================================

CREATE OR REPLACE FUNCTION update_provider_review_stats()
RETURNS TRIGGER AS $$
DECLARE
    v_provider_id uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_provider_id := OLD.provider_id;
    ELSE
        v_provider_id := NEW.provider_id;
    END IF;

    UPDATE respite_providers
    SET
        avg_rating = COALESCE(
            (SELECT ROUND(AVG(rating)::decimal, 1)
             FROM respite_reviews
             WHERE provider_id = v_provider_id AND status = 'PUBLISHED'),
            0
        ),
        review_count = (
            SELECT COUNT(*)
            FROM respite_reviews
            WHERE provider_id = v_provider_id AND status = 'PUBLISHED'
        ),
        updated_at = now()
    WHERE id = v_provider_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_update_provider_review_stats
    AFTER INSERT OR UPDATE OR DELETE ON respite_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_provider_review_stats();

-- Recreate updated_at trigger on reviews
CREATE TRIGGER trg_respite_reviews_updated_at
    BEFORE UPDATE ON respite_reviews
    FOR EACH ROW EXECUTE FUNCTION update_respite_updated_at();

-- ============================================================================
-- 6. Fix get_respite_days_this_year to SECURITY INVOKER
-- ============================================================================

CREATE OR REPLACE FUNCTION get_respite_days_this_year(
    p_circle_id uuid,
    p_patient_id uuid
)
RETURNS int AS $$
DECLARE
    v_total int;
BEGIN
    SELECT COALESCE(SUM(total_days), 0) INTO v_total
    FROM respite_log
    WHERE circle_id = p_circle_id
      AND patient_id = p_patient_id
      AND start_date >= date_trunc('year', now())::date;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE SECURITY INVOKER;

-- ============================================================================
-- 7. Add optimized spatial index for active providers
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_respite_providers_active_geo
    ON respite_providers(latitude, longitude) WHERE is_active = true;
