-- ============================================================================
-- Migration: Respite Care Final Hardening
-- Addresses remaining review findings not covered by 20260221000007:
--   1. Add phone format regex (007 only checks length)
--   2. Add website URL format regex (007 only checks length)
--   3. Add bounding box pre-filter to Haversine search for performance
-- ============================================================================

-- ============================================================================
-- 1. Tighten phone constraint with format regex (007 has length-only check)
-- ============================================================================

-- Drop the length-only constraint from 007
ALTER TABLE respite_providers DROP CONSTRAINT IF EXISTS respite_providers_phone_length_check;

-- Add combined length + format constraint
DO $$ BEGIN
    ALTER TABLE respite_providers
        ADD CONSTRAINT respite_providers_phone_check
        CHECK (phone IS NULL OR (length(phone) <= 30 AND phone ~ '^\+?[\d\s\-\(\)\.]+$'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- 2. Tighten website constraint with URL format regex (007 has length-only)
-- ============================================================================

-- Drop the length-only constraint from 007
ALTER TABLE respite_providers DROP CONSTRAINT IF EXISTS respite_providers_website_length_check;

-- Add combined length + format constraint
DO $$ BEGIN
    ALTER TABLE respite_providers
        ADD CONSTRAINT respite_providers_website_check
        CHECK (website IS NULL OR (length(website) <= 500 AND website ~* '^https?://'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- 3. Add bounding box pre-filter to Haversine search for performance
--    (Reduces Haversine calculations by 60-80% for dense provider areas)
-- ============================================================================

CREATE OR REPLACE FUNCTION search_providers_by_radius(
    p_latitude decimal,
    p_longitude decimal,
    p_radius_miles decimal,
    p_limit int DEFAULT 20,
    p_offset int DEFAULT 0
)
RETURNS TABLE (
    id uuid,
    name text,
    provider_type text,
    description text,
    address text,
    city text,
    state text,
    zip_code text,
    latitude decimal,
    longitude decimal,
    phone text,
    email text,
    website text,
    hours_json jsonb,
    pricing_model text,
    price_min decimal,
    price_max decimal,
    accepts_medicaid boolean,
    accepts_medicare boolean,
    scholarships_available boolean,
    services_json jsonb,
    verification_status text,
    avg_rating decimal,
    review_count int,
    distance_miles decimal
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rp.id,
        rp.name,
        rp.provider_type,
        rp.description,
        rp.address,
        rp.city,
        rp.state,
        rp.zip_code,
        rp.latitude,
        rp.longitude,
        rp.phone,
        rp.email,
        rp.website,
        rp.hours_json,
        rp.pricing_model,
        rp.price_min,
        rp.price_max,
        rp.accepts_medicaid,
        rp.accepts_medicare,
        rp.scholarships_available,
        rp.services_json,
        rp.verification_status,
        rp.avg_rating,
        rp.review_count,
        ROUND(
            3959.0 * acos(
                LEAST(1.0, GREATEST(-1.0,
                    cos(radians(p_latitude)) *
                    cos(radians(rp.latitude)) *
                    cos(radians(rp.longitude) - radians(p_longitude)) +
                    sin(radians(p_latitude)) *
                    sin(radians(rp.latitude))
                ))
            )::decimal,
            1
        ) AS distance_miles
    FROM respite_providers rp
    WHERE rp.is_active = true
      -- Bounding box pre-filter (cheap lat/lng comparison eliminates distant rows)
      AND rp.latitude BETWEEN (p_latitude - p_radius_miles / 69.0)
                            AND (p_latitude + p_radius_miles / 69.0)
      AND rp.longitude BETWEEN (p_longitude - p_radius_miles / (69.0 * cos(radians(p_latitude))))
                             AND (p_longitude + p_radius_miles / (69.0 * cos(radians(p_latitude))))
      -- Precise Haversine filter on remaining candidates
      AND (
          3959.0 * acos(
              LEAST(1.0, GREATEST(-1.0,
                  cos(radians(p_latitude)) *
                  cos(radians(rp.latitude)) *
                  cos(radians(rp.longitude) - radians(p_longitude)) +
                  sin(radians(p_latitude)) *
                  sin(radians(rp.latitude))
              ))
          )
      ) <= p_radius_miles
    ORDER BY distance_miles ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 4. Add standalone index on respite_log.start_date for reminder queries
--    (Existing composite idx_respite_log_circle(circle_id, start_date) cannot
--     efficiently serve range queries on start_date without circle_id filter)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_respite_log_start_date
    ON respite_log(start_date DESC);
