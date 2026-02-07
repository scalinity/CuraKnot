-- ============================================================================
-- Migration: Medical Transportation Coordinator
-- Description: Ride scheduling, driver coordination, transport directory,
--              ride statistics for fairness tracking
-- ============================================================================

-- ============================================================================
-- TABLE: scheduled_rides
-- ============================================================================

CREATE TABLE IF NOT EXISTS scheduled_rides (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Ride details
    purpose text NOT NULL CHECK (char_length(purpose) BETWEEN 1 AND 500),
    appointment_id uuid,  -- Link to binder appointment if exists
    pickup_address text NOT NULL CHECK (char_length(pickup_address) BETWEEN 1 AND 1000),
    pickup_time timestamptz NOT NULL,
    destination_address text NOT NULL CHECK (char_length(destination_address) BETWEEN 1 AND 1000),
    destination_name text CHECK (destination_name IS NULL OR char_length(destination_name) <= 500),

    -- Return ride
    needs_return boolean NOT NULL DEFAULT false,
    return_time timestamptz,

    -- Special needs
    wheelchair_accessible boolean NOT NULL DEFAULT false,
    stretcher_required boolean NOT NULL DEFAULT false,
    oxygen_required boolean NOT NULL DEFAULT false,
    other_needs text CHECK (other_needs IS NULL OR char_length(other_needs) <= 2000),

    -- Driver
    driver_type text NOT NULL DEFAULT 'FAMILY' CHECK (driver_type IN ('FAMILY', 'EXTERNAL_SERVICE')),
    driver_user_id uuid,
    external_service_name text CHECK (external_service_name IS NULL OR char_length(external_service_name) <= 500),
    confirmation_status text NOT NULL DEFAULT 'UNCONFIRMED' CHECK (confirmation_status IN ('UNCONFIRMED', 'CONFIRMED', 'DECLINED')),

    -- Status
    status text NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED', 'COMPLETED', 'CANCELLED', 'MISSED')),

    -- Recurrence
    recurrence_rule text,
    parent_ride_id uuid REFERENCES scheduled_rides(id) ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Ensure return_time is after pickup_time when set
    CONSTRAINT chk_return_after_pickup CHECK (return_time IS NULL OR return_time > pickup_time)
);

CREATE INDEX IF NOT EXISTS idx_scheduled_rides_circle ON scheduled_rides(circle_id, pickup_time);
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_patient ON scheduled_rides(patient_id, pickup_time);
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_driver ON scheduled_rides(driver_user_id, pickup_time);
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_status ON scheduled_rides(status, pickup_time);
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_confirmation ON scheduled_rides(confirmation_status, pickup_time)
    WHERE status = 'SCHEDULED';

-- Covering index for reminder cron query pattern
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_reminders
    ON scheduled_rides(status, pickup_time, confirmation_status)
    WHERE status = 'SCHEDULED';

-- ============================================================================
-- TABLE: transport_services
-- ============================================================================

CREATE TABLE IF NOT EXISTS transport_services (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid REFERENCES circles(id) ON DELETE CASCADE,  -- NULL for system-wide

    -- Service info
    name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 500),
    service_type text NOT NULL CHECK (service_type IN ('PARATRANSIT', 'MEDICAL_TRANSPORT', 'RIDESHARE', 'VOLUNTEER')),
    phone text CHECK (phone IS NULL OR char_length(phone) <= 50),
    website text CHECK (website IS NULL OR char_length(website) <= 2048),
    hours text CHECK (hours IS NULL OR char_length(hours) <= 500),
    service_area text CHECK (service_area IS NULL OR char_length(service_area) <= 1000),

    -- Capabilities
    wheelchair_accessible boolean NOT NULL DEFAULT false,
    stretcher_available boolean NOT NULL DEFAULT false,
    oxygen_allowed boolean NOT NULL DEFAULT false,

    -- Notes
    notes text CHECK (notes IS NULL OR char_length(notes) <= 5000),
    is_active boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transport_services_circle ON transport_services(circle_id)
    WHERE circle_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_transport_services_type ON transport_services(service_type)
    WHERE is_active = true;

-- ============================================================================
-- TABLE: ride_statistics
-- ============================================================================

CREATE TABLE IF NOT EXISTS ride_statistics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    month date NOT NULL,  -- First of month

    rides_given int NOT NULL DEFAULT 0,
    rides_scheduled int NOT NULL DEFAULT 0,
    rides_cancelled int NOT NULL DEFAULT 0,

    UNIQUE(circle_id, user_id, month)
);

CREATE INDEX IF NOT EXISTS idx_ride_statistics_circle ON ride_statistics(circle_id, month);

-- ============================================================================
-- RLS POLICIES: scheduled_rides
-- ============================================================================

ALTER TABLE scheduled_rides ENABLE ROW LEVEL SECURITY;

-- Members can read rides in their circles
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members read circle rides' AND tablename = 'scheduled_rides') THEN
CREATE POLICY "Members read circle rides"
    ON scheduled_rides FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = scheduled_rides.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- Contributors+ can create rides (must be the creator)
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create rides' AND tablename = 'scheduled_rides') THEN
CREATE POLICY "Contributors create rides"
    ON scheduled_rides FOR INSERT
    WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = scheduled_rides.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- Contributors+ can update rides (immutable field protection via trigger)
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors update rides' AND tablename = 'scheduled_rides') THEN
CREATE POLICY "Contributors update rides"
    ON scheduled_rides FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = scheduled_rides.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- Admins+ can delete rides
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins delete rides' AND tablename = 'scheduled_rides') THEN
CREATE POLICY "Admins delete rides"
    ON scheduled_rides FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = scheduled_rides.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.role IN ('ADMIN', 'OWNER')
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: transport_services
-- ============================================================================

ALTER TABLE transport_services ENABLE ROW LEVEL SECURITY;

-- System services (circle_id IS NULL) readable by all authenticated users
-- Circle services readable by circle members
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Read transport services' AND tablename = 'transport_services') THEN
CREATE POLICY "Read transport services"
    ON transport_services FOR SELECT
    USING (
        circle_id IS NULL  -- System-wide services
        OR EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = transport_services.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- Contributors+ can add circle-specific services
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors add transport services' AND tablename = 'transport_services') THEN
CREATE POLICY "Contributors add transport services"
    ON transport_services FOR INSERT
    WITH CHECK (
        circle_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = transport_services.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- Contributors+ can update circle-specific services
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors update transport services' AND tablename = 'transport_services') THEN
CREATE POLICY "Contributors update transport services"
    ON transport_services FOR UPDATE
    USING (
        circle_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = transport_services.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- Admins+ can delete circle-specific services
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins delete transport services' AND tablename = 'transport_services') THEN
CREATE POLICY "Admins delete transport services"
    ON transport_services FOR DELETE
    USING (
        circle_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = transport_services.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.role IN ('ADMIN', 'OWNER')
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: ride_statistics
-- ============================================================================

ALTER TABLE ride_statistics ENABLE ROW LEVEL SECURITY;

-- Members can read statistics for their circles
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members read ride statistics' AND tablename = 'ride_statistics') THEN
CREATE POLICY "Members read ride statistics"
    ON ride_statistics FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = ride_statistics.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
        )
    );
END IF;
END $$;

-- Service role can manage statistics (cron functions)
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages ride statistics' AND tablename = 'ride_statistics') THEN
CREATE POLICY "Service role manages ride statistics"
    ON ride_statistics FOR ALL
    USING (auth.role() = 'service_role');
END IF;
END $$;

-- ============================================================================
-- UPDATE plan_limits: Add transportation feature flags
-- ============================================================================

UPDATE plan_limits
SET features_json = features_json || '["transportation"]'::jsonb,
    updated_at = now()
WHERE plan = 'PLUS'
  AND NOT (features_json ? 'transportation');

UPDATE plan_limits
SET features_json = features_json || '["transportation", "transportation_analytics"]'::jsonb,
    updated_at = now()
WHERE plan = 'FAMILY'
  AND NOT (features_json ? 'transportation');

-- ============================================================================
-- SEED: Sample system-wide transport services
-- ============================================================================

INSERT INTO transport_services (circle_id, name, service_type, phone, website, hours, service_area, wheelchair_accessible, stretcher_available, oxygen_allowed, notes)
VALUES
    (NULL, 'Non-Emergency Medical Transport', 'MEDICAL_TRANSPORT', NULL, NULL, 'Mon-Fri 6AM-8PM', 'Contact your insurance for local providers', true, true, true, 'Most insurance plans cover non-emergency medical transportation. Call your insurance to find approved providers in your area.'),
    (NULL, 'Local Paratransit / Dial-a-Ride', 'PARATRANSIT', NULL, NULL, 'Varies by city', 'Contact your city or county transit authority', true, false, true, 'ADA-mandated paratransit services are available in areas with fixed-route public transit. Eligibility certification may be required.'),
    (NULL, 'Volunteer Driver Programs', 'VOLUNTEER', NULL, NULL, 'Varies', 'Contact your local Area Agency on Aging', false, false, false, 'Many communities have volunteer driver programs through senior centers, faith organizations, or nonprofits. Often free or donation-based.')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- TRIGGER: Auto-update updated_at on scheduled_rides
-- ============================================================================

CREATE OR REPLACE FUNCTION update_scheduled_rides_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_scheduled_rides_updated_at') THEN
CREATE TRIGGER trg_scheduled_rides_updated_at
    BEFORE UPDATE ON scheduled_rides
    FOR EACH ROW
    EXECUTE FUNCTION update_scheduled_rides_updated_at();
END IF;
END $$;
