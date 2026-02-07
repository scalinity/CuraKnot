-- Round 7 fixes: SQL-layer filters, RLS policy corrections
-- ============================================================================

-- 1. Replace search_providers_by_radius with filter-aware version
-- Moves providerType, minRating, maxPrice, verifiedOnly, services filters
-- from application layer to SQL for accurate pagination
-- ============================================================================

CREATE OR REPLACE FUNCTION search_providers_by_radius(
    p_latitude decimal,
    p_longitude decimal,
    p_radius_miles decimal,
    p_limit int DEFAULT 20,
    p_offset int DEFAULT 0,
    p_provider_type text DEFAULT NULL,
    p_min_rating decimal DEFAULT NULL,
    p_max_price decimal DEFAULT NULL,
    p_verified_only boolean DEFAULT false,
    p_services jsonb DEFAULT NULL
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
      -- Bounding box pre-filter
      AND rp.latitude BETWEEN (p_latitude - (p_radius_miles / 69.0))
                            AND (p_latitude + (p_radius_miles / 69.0))
      AND rp.longitude BETWEEN (p_longitude - (p_radius_miles / (69.0 * cos(radians(p_latitude)))))
                             AND (p_longitude + (p_radius_miles / (69.0 * cos(radians(p_latitude)))))
      -- Haversine distance filter
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
      -- Provider type filter
      AND (p_provider_type IS NULL OR rp.provider_type = p_provider_type)
      -- Minimum rating filter
      AND (p_min_rating IS NULL OR rp.avg_rating >= p_min_rating)
      -- Max price filter (provider's minimum price must be at or below budget)
      AND (p_max_price IS NULL OR (rp.price_min IS NOT NULL AND rp.price_min <= p_max_price))
      -- Verified only filter
      AND (NOT p_verified_only OR rp.verification_status IN ('VERIFIED', 'FEATURED'))
      -- Services filter (at least one requested service must match)
      AND (p_services IS NULL OR rp.services_json ?| ARRAY(SELECT jsonb_array_elements_text(p_services)))
    ORDER BY distance_miles ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 2. Fix RLS: respite_requests UPDATE - allow circle admins/owners to update
-- ============================================================================

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Requesters update own requests' AND tablename = 'respite_requests') THEN
        DROP POLICY "Requesters update own requests" ON respite_requests;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members update requests' AND tablename = 'respite_requests') THEN
        CREATE POLICY "Circle members update requests" ON respite_requests
            FOR UPDATE TO authenticated
            USING (
                created_by = auth.uid()
                OR
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = respite_requests.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            )
            WITH CHECK (
                created_by = auth.uid()
                OR
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = respite_requests.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- 3. Fix RLS: respite_log UPDATE - restrict to creator only
-- ============================================================================

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Family members update respite log' AND tablename = 'respite_log') THEN
        DROP POLICY "Family members update respite log" ON respite_log;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Creators update own respite log' AND tablename = 'respite_log') THEN
        CREATE POLICY "Creators update own respite log" ON respite_log
            FOR UPDATE TO authenticated
            USING (
                created_by = auth.uid()
                AND has_feature_access(auth.uid(), 'respite_tracking')
            )
            WITH CHECK (
                created_by = auth.uid()
                AND has_feature_access(auth.uid(), 'respite_tracking')
            );
    END IF;
END $$;
