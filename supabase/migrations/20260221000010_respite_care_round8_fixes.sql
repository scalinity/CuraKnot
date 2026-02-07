-- ============================================================================
-- Round 8 fixes: Policy cleanup, immutability trigger, performance indexes,
-- search function CTE optimization
-- ============================================================================

-- ============================================================================
-- 1. Remove redundant "Requesters update own requests" policy
--    (Created by hardening migration, superseded by "Circle members update
--     requests" from round7_fixes which correctly allows admin/owner updates)
-- ============================================================================

DROP POLICY IF EXISTS "Requesters update own requests" ON respite_requests;

-- ============================================================================
-- 2. Remove redundant "Family members update respite log" UPDATE policy
--    (Created by hardening migration, superseded by "Creators update own
--     respite log" from round7_fixes which correctly restricts to creator)
-- ============================================================================

DROP POLICY IF EXISTS "Family members update respite log" ON respite_log;

-- ============================================================================
-- 3. Immutability trigger: prevent created_by from being changed on UPDATE
--    (Fixes CA1 finding: RLS WITH CHECK allowed admin to mutate created_by)
-- ============================================================================

CREATE OR REPLACE FUNCTION immutable_created_by()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
        RAISE EXCEPTION 'created_by cannot be modified'
            USING ERRCODE = '23514'; -- check_violation
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_immutable_created_by_respite_requests'
    ) THEN
        CREATE TRIGGER trg_immutable_created_by_respite_requests
            BEFORE UPDATE ON respite_requests
            FOR EACH ROW
            WHEN (NEW.created_by IS DISTINCT FROM OLD.created_by)
            EXECUTE FUNCTION immutable_created_by();
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_immutable_created_by_respite_log'
    ) THEN
        CREATE TRIGGER trg_immutable_created_by_respite_log
            BEFORE UPDATE ON respite_log
            FOR EACH ROW
            WHEN (NEW.created_by IS DISTINCT FROM OLD.created_by)
            EXECUTE FUNCTION immutable_created_by();
    END IF;
END $$;

-- ============================================================================
-- 4. Add DELETE policy on respite_log (creator only + feature check)
--    (Fixes SA2 finding: no DELETE policy existed)
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE policyname = 'Creators delete own respite log'
          AND tablename = 'respite_log'
    ) THEN
        CREATE POLICY "Creators delete own respite log" ON respite_log
            FOR DELETE TO authenticated
            USING (
                created_by = auth.uid()
                AND has_feature_access(auth.uid(), 'respite_tracking')
            );
    END IF;
END $$;

-- ============================================================================
-- 5. GIN index on services_json for ?| operator performance
--    (Fixes CA3 finding: JSONB containment query needs GIN index)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_respite_providers_services_gin
    ON respite_providers USING GIN (services_json);

-- ============================================================================
-- 6. Composite index on circle_members for RLS policy performance
--    (Fixes CA3 finding: RLS subqueries do frequent lookups on this combo)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_circle_members_rls_lookup
    ON circle_members (circle_id, user_id, status, role);

-- ============================================================================
-- 7. Optimized search_providers_by_radius with CTE
--    (Fixes CA3 finding: Haversine was computed twice per row)
--    Keeps all filter parameters from round7_fixes version
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
    WITH candidates AS (
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
            ) AS dist_miles
        FROM respite_providers rp
        WHERE rp.is_active = true
          -- Bounding box pre-filter
          AND rp.latitude BETWEEN (p_latitude - (p_radius_miles / 69.0))
                                AND (p_latitude + (p_radius_miles / 69.0))
          AND rp.longitude BETWEEN (p_longitude - (p_radius_miles / (69.0 * cos(radians(p_latitude)))))
                                 AND (p_longitude + (p_radius_miles / (69.0 * cos(radians(p_latitude)))))
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
    )
    SELECT
        c.id, c.name, c.provider_type, c.description,
        c.address, c.city, c.state, c.zip_code,
        c.latitude, c.longitude, c.phone, c.email, c.website,
        c.hours_json, c.pricing_model, c.price_min, c.price_max,
        c.accepts_medicaid, c.accepts_medicare, c.scholarships_available,
        c.services_json, c.verification_status, c.avg_rating, c.review_count,
        c.dist_miles AS distance_miles
    FROM candidates c
    WHERE c.dist_miles <= p_radius_miles
    ORDER BY c.dist_miles ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;
