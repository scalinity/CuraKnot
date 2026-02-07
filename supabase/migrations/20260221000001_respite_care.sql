-- ============================================================================
-- Migration: Respite Care Finder & Booking
-- Description: Provider directory, reviews, availability requests, respite log
-- ============================================================================

-- ============================================================================
-- TABLE: respite_providers
-- ============================================================================

CREATE TABLE IF NOT EXISTS respite_providers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Provider info
    name text NOT NULL CHECK (length(name) >= 2 AND length(name) <= 200),
    provider_type text NOT NULL CHECK (provider_type IN ('ADULT_DAY', 'IN_HOME', 'OVERNIGHT', 'VOLUNTEER', 'EMERGENCY')),
    description text CHECK (length(description) <= 2000),

    -- Location
    address text,
    city text NOT NULL CHECK (length(city) <= 100),
    state text NOT NULL CHECK (length(state) = 2),
    zip_code text CHECK (zip_code ~ '^\d{5}(-\d{4})?$'),
    latitude decimal(10, 8) NOT NULL CHECK (latitude >= -90 AND latitude <= 90),
    longitude decimal(11, 8) NOT NULL CHECK (longitude >= -180 AND longitude <= 180),
    service_radius_miles int,

    -- Contact
    phone text,
    email text,
    website text,

    -- Hours
    hours_json jsonb,

    -- Pricing
    pricing_model text CHECK (pricing_model IN ('HOURLY', 'DAILY', 'WEEKLY', 'SLIDING_SCALE', 'FREE')),
    price_min decimal(10, 2) CHECK (price_min >= 0),
    price_max decimal(10, 2) CHECK (price_max >= price_min),
    accepts_medicaid boolean DEFAULT false,
    accepts_medicare boolean DEFAULT false,
    scholarships_available boolean DEFAULT false,

    -- Services
    services_json jsonb NOT NULL DEFAULT '[]'::jsonb,

    -- Verification
    verification_status text NOT NULL DEFAULT 'UNVERIFIED' CHECK (verification_status IN ('UNVERIFIED', 'VERIFIED', 'FEATURED')),
    verified_at timestamptz,

    -- Metrics (denormalized, updated by trigger)
    avg_rating decimal(2, 1) NOT NULL DEFAULT 0 CHECK (avg_rating >= 0 AND avg_rating <= 5),
    review_count int NOT NULL DEFAULT 0 CHECK (review_count >= 0),

    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_respite_providers_location ON respite_providers(city, state);
CREATE INDEX IF NOT EXISTS idx_respite_providers_type ON respite_providers(provider_type);
CREATE INDEX IF NOT EXISTS idx_respite_providers_geo ON respite_providers(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_respite_providers_rating ON respite_providers(avg_rating DESC);
CREATE INDEX IF NOT EXISTS idx_respite_providers_active ON respite_providers(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_respite_providers_active_geo ON respite_providers(latitude, longitude) WHERE is_active = true;

-- ============================================================================
-- TABLE: respite_reviews
-- ============================================================================

CREATE TABLE IF NOT EXISTS respite_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id uuid NOT NULL REFERENCES respite_providers(id) ON DELETE CASCADE,
    reviewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,

    -- Rating
    rating int NOT NULL CHECK (rating BETWEEN 1 AND 5),

    -- Review content
    title text CHECK (length(title) <= 200),
    body text CHECK (length(body) <= 5000),
    service_date date,

    -- Status
    status text NOT NULL DEFAULT 'PUBLISHED' CHECK (status IN ('PUBLISHED', 'FLAGGED', 'REMOVED')),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(provider_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_respite_reviews_provider ON respite_reviews(provider_id);
CREATE INDEX IF NOT EXISTS idx_respite_reviews_reviewer ON respite_reviews(reviewer_id);

-- ============================================================================
-- TABLE: respite_requests
-- ============================================================================

CREATE TABLE IF NOT EXISTS respite_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    provider_id uuid NOT NULL REFERENCES respite_providers(id),
    created_by uuid NOT NULL REFERENCES auth.users(id),

    -- Request details
    start_date date NOT NULL,
    end_date date NOT NULL CHECK (end_date >= start_date),
    special_considerations text CHECK (length(special_considerations) <= 2000),

    -- Shared info consent flags
    share_medications boolean NOT NULL DEFAULT false,
    share_contacts boolean NOT NULL DEFAULT false,
    share_dietary boolean NOT NULL DEFAULT false,
    share_full_summary boolean NOT NULL DEFAULT false,

    -- Contact preference
    contact_method text NOT NULL CHECK (contact_method IN ('PHONE', 'EMAIL')),
    contact_value text NOT NULL CHECK (length(contact_value) <= 200),

    -- Status
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'CONFIRMED', 'DECLINED', 'CANCELLED', 'COMPLETED')),
    provider_response text CHECK (length(provider_response) <= 2000),
    responded_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_respite_requests_circle ON respite_requests(circle_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_respite_requests_provider ON respite_requests(provider_id);
CREATE INDEX IF NOT EXISTS idx_respite_requests_status ON respite_requests(status);

-- ============================================================================
-- TABLE: respite_log
-- ============================================================================

CREATE TABLE IF NOT EXISTS respite_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    provider_id uuid REFERENCES respite_providers(id) ON DELETE SET NULL,

    -- Log entry
    start_date date NOT NULL,
    end_date date NOT NULL CHECK (end_date >= start_date),
    provider_name text NOT NULL CHECK (length(provider_name) <= 200),
    provider_type text NOT NULL CHECK (provider_type IN ('ADULT_DAY', 'IN_HOME', 'OVERNIGHT', 'VOLUNTEER', 'EMERGENCY')),
    total_days int GENERATED ALWAYS AS ((end_date - start_date) + 1) STORED,

    -- Notes
    notes text CHECK (length(notes) <= 2000),

    -- Review prompt
    review_prompted boolean NOT NULL DEFAULT false,

    created_by uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_respite_log_circle ON respite_log(circle_id, start_date DESC);
CREATE INDEX IF NOT EXISTS idx_respite_log_patient ON respite_log(patient_id);

-- ============================================================================
-- FUNCTION: Haversine distance search
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
-- FUNCTION: Get respite days for a year
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
-- TRIGGER: Update provider avg_rating and review_count
-- ============================================================================

CREATE OR REPLACE FUNCTION update_provider_review_stats()
RETURNS TRIGGER AS $$
DECLARE
    v_provider_id uuid;
BEGIN
    -- Get the provider_id from the affected row
    IF TG_OP = 'DELETE' THEN
        v_provider_id := OLD.provider_id;
    ELSE
        v_provider_id := NEW.provider_id;
    END IF;

    -- Recalculate stats
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

-- ============================================================================
-- TRIGGER: Auto-update updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION update_respite_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_respite_providers_updated_at
    BEFORE UPDATE ON respite_providers
    FOR EACH ROW EXECUTE FUNCTION update_respite_updated_at();

CREATE TRIGGER trg_respite_reviews_updated_at
    BEFORE UPDATE ON respite_reviews
    FOR EACH ROW EXECUTE FUNCTION update_respite_updated_at();

CREATE TRIGGER trg_respite_requests_updated_at
    BEFORE UPDATE ON respite_requests
    FOR EACH ROW EXECUTE FUNCTION update_respite_updated_at();

CREATE TRIGGER trg_respite_log_updated_at
    BEFORE UPDATE ON respite_log
    FOR EACH ROW EXECUTE FUNCTION update_respite_updated_at();

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE respite_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE respite_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE respite_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE respite_log ENABLE ROW LEVEL SECURITY;

-- respite_providers: All authenticated users can read active providers
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users read providers') THEN
        CREATE POLICY "Authenticated users read providers" ON respite_providers
            FOR SELECT TO authenticated
            USING (is_active = true);
    END IF;
END $$;

-- respite_reviews: All authenticated users can read published reviews
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users read reviews') THEN
        CREATE POLICY "Authenticated users read reviews" ON respite_reviews
            FOR SELECT TO authenticated
            USING (status = 'PUBLISHED');
    END IF;
END $$;

-- respite_reviews: PLUS and FAMILY users can create reviews (must be circle member)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Subscribers create reviews') THEN
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
    END IF;
END $$;

-- respite_reviews: Users can delete their own reviews
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users delete own reviews') THEN
        CREATE POLICY "Users delete own reviews" ON respite_reviews
            FOR DELETE TO authenticated
            USING (reviewer_id = auth.uid());
    END IF;
END $$;

-- respite_requests: Circle members can read their circle's requests
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members read requests') THEN
        CREATE POLICY "Circle members read requests" ON respite_requests
            FOR SELECT TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = respite_requests.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- respite_requests: PLUS/FAMILY circle members can create requests
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Subscribers create requests') THEN
        CREATE POLICY "Subscribers create requests" ON respite_requests
            FOR INSERT TO authenticated
            WITH CHECK (
                created_by = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = respite_requests.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
                AND has_feature_access(auth.uid(), 'respite_requests')
            );
    END IF;
END $$;

-- respite_requests: Requesters can update their own requests
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Requesters update own requests') THEN
        CREATE POLICY "Requesters update own requests" ON respite_requests
            FOR UPDATE TO authenticated
            USING (created_by = auth.uid())
            WITH CHECK (created_by = auth.uid());
    END IF;
END $$;

-- respite_log: Circle members with FAMILY tier can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Family members read respite log') THEN
        CREATE POLICY "Family members read respite log" ON respite_log
            FOR SELECT TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = respite_log.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
                AND has_feature_access(auth.uid(), 'respite_tracking')
            );
    END IF;
END $$;

-- respite_log: FAMILY circle members can create log entries
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Family members create respite log') THEN
        CREATE POLICY "Family members create respite log" ON respite_log
            FOR INSERT TO authenticated
            WITH CHECK (
                created_by = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = respite_log.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
                AND has_feature_access(auth.uid(), 'respite_tracking')
            );
    END IF;
END $$;

-- respite_log: FAMILY circle members can update log entries
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Family members update respite log') THEN
        CREATE POLICY "Family members update respite log" ON respite_log
            FOR UPDATE TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = respite_log.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
                AND has_feature_access(auth.uid(), 'respite_tracking')
            );
    END IF;
END $$;

-- ============================================================================
-- UPDATE plan_limits: Add respite features
-- ============================================================================

-- Add respite_finder to PLUS tier features
UPDATE plan_limits
SET features_json = features_json || '["respite_finder", "respite_reviews", "respite_requests"]'::jsonb,
    updated_at = now()
WHERE plan = 'PLUS'
  AND NOT features_json ? 'respite_finder';

-- Add respite_finder + tracking to FAMILY tier features (respite_finder may already exist)
UPDATE plan_limits
SET features_json = features_json || '["respite_reviews", "respite_requests", "respite_tracking", "respite_reminders"]'::jsonb,
    updated_at = now()
WHERE plan = 'FAMILY'
  AND NOT features_json ? 'respite_tracking';

-- Add respite_finder to FREE tier (browse only)
UPDATE plan_limits
SET features_json = features_json || '["respite_finder"]'::jsonb,
    updated_at = now()
WHERE plan = 'FREE'
  AND NOT features_json ? 'respite_finder';

-- ============================================================================
-- SEED: Sample providers for development
-- ============================================================================

INSERT INTO respite_providers (name, provider_type, description, address, city, state, zip_code, latitude, longitude, phone, email, website, pricing_model, price_min, price_max, services_json, verification_status) VALUES
('Comfort Care Adult Day Center', 'ADULT_DAY', 'Full-service adult day program with activities, meals, and medication management. Specialized dementia care program available.', '456 Care Center Drive', 'San Francisco', 'CA', '94102', 37.7749, -122.4194, '(415) 555-0100', 'info@comfortcareadult.example', 'https://comfortcareadult.example', 'DAILY', 85.00, 120.00, '["meals", "transportation", "dementia_care", "medication_management", "activities"]'::jsonb, 'VERIFIED'),
('Home Instead Senior Care', 'IN_HOME', 'Personalized in-home respite care. Trained caregivers provide companionship, meal preparation, and light housekeeping.', '789 Home Care Lane', 'San Francisco', 'CA', '94110', 37.7499, -122.4148, '(415) 555-0200', 'care@homeinstead.example', 'https://homeinstead.example', 'HOURLY', 28.00, 45.00, '["companionship", "meal_prep", "light_housekeeping", "medication_reminders"]'::jsonb, 'VERIFIED'),
('Golden Gate Respite House', 'OVERNIGHT', 'Short-term residential respite stays in a home-like setting. 24/7 nursing staff on site.', '321 Respite Way', 'Daly City', 'CA', '94015', 37.6879, -122.4702, '(650) 555-0300', 'info@ggrespite.example', 'https://ggrespite.example', 'DAILY', 250.00, 350.00, '["24hr_nursing", "meals", "activities", "medication_management", "mobility_assistance"]'::jsonb, 'FEATURED'),
('Community Cares Volunteer Respite', 'VOLUNTEER', 'Faith-based volunteer respite program. Trained volunteers provide companionship and supervision for a few hours.', '100 Community Blvd', 'Oakland', 'CA', '94612', 37.8044, -122.2712, '(510) 555-0400', 'volunteer@communitycares.example', NULL, 'HOURLY', 0.00, 0.00, '["companionship", "activities", "supervision"]'::jsonb, 'VERIFIED'),
('Bay Area Crisis Respite', 'EMERGENCY', 'Emergency respite care available 24/7 for urgent caregiver needs. Same-day placement when available.', '555 Emergency Ave', 'San Jose', 'CA', '95112', 37.3382, -121.8863, '(408) 555-0500', 'urgent@bayareacrisis.example', 'https://bayareacrisis.example', 'DAILY', 150.00, 200.00, '["24hr_care", "meals", "medication_management", "crisis_support"]'::jsonb, 'VERIFIED')
ON CONFLICT DO NOTHING;
