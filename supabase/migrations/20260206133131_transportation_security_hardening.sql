-- ============================================================================
-- Migration: Transportation Security Hardening
-- Description: Add CHECK constraints, tighten RLS policies, add indexes
-- ============================================================================

-- ============================================================================
-- CHECK CONSTRAINTS: scheduled_rides
-- ============================================================================

DO $$ BEGIN
    -- Text length constraints
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_purpose_length') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_purpose_length
            CHECK (char_length(purpose) BETWEEN 1 AND 500);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_pickup_address_length') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_pickup_address_length
            CHECK (char_length(pickup_address) BETWEEN 1 AND 1000);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_destination_address_length') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_destination_address_length
            CHECK (char_length(destination_address) BETWEEN 1 AND 1000);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_destination_name_length') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_destination_name_length
            CHECK (destination_name IS NULL OR char_length(destination_name) <= 500);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_other_needs_length') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_other_needs_length
            CHECK (other_needs IS NULL OR char_length(other_needs) <= 2000);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_external_service_name_length') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_external_service_name_length
            CHECK (external_service_name IS NULL OR char_length(external_service_name) <= 500);
    END IF;

    -- Enum constraints
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_driver_type_enum') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_driver_type_enum
            CHECK (driver_type IN ('FAMILY', 'EXTERNAL_SERVICE'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_confirmation_status_enum') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_confirmation_status_enum
            CHECK (confirmation_status IN ('UNCONFIRMED', 'CONFIRMED', 'DECLINED'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_status_enum') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_status_enum
            CHECK (status IN ('SCHEDULED', 'COMPLETED', 'CANCELLED', 'MISSED'));
    END IF;

    -- Return time must be after pickup time
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_return_after_pickup') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_return_after_pickup
            CHECK (return_time IS NULL OR return_time > pickup_time);
    END IF;
END $$;

-- ============================================================================
-- CHECK CONSTRAINTS: transport_services
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_name_length') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_name_length
            CHECK (char_length(name) BETWEEN 1 AND 500);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_type_enum') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_type_enum
            CHECK (service_type IN ('PARATRANSIT', 'MEDICAL_TRANSPORT', 'RIDESHARE', 'VOLUNTEER'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_phone_length') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_phone_length
            CHECK (phone IS NULL OR char_length(phone) <= 50);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_website_length') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_website_length
            CHECK (website IS NULL OR char_length(website) <= 2048);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_hours_length') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_hours_length
            CHECK (hours IS NULL OR char_length(hours) <= 500);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_service_area_length') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_service_area_length
            CHECK (service_area IS NULL OR char_length(service_area) <= 1000);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_notes_length') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_notes_length
            CHECK (notes IS NULL OR char_length(notes) <= 5000);
    END IF;
END $$;

-- ============================================================================
-- TRIGGER: Prevent changing immutable fields on scheduled_rides
-- ============================================================================

CREATE OR REPLACE FUNCTION prevent_immutable_ride_field_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.circle_id IS DISTINCT FROM OLD.circle_id THEN
        RAISE EXCEPTION 'Cannot change circle_id on a scheduled ride';
    END IF;
    IF NEW.patient_id IS DISTINCT FROM OLD.patient_id THEN
        RAISE EXCEPTION 'Cannot change patient_id on a scheduled ride';
    END IF;
    IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
        RAISE EXCEPTION 'Cannot change created_by on a scheduled ride';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Cannot change created_at on a scheduled ride';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_prevent_immutable_ride_changes') THEN
    CREATE TRIGGER trg_prevent_immutable_ride_changes
        BEFORE UPDATE ON scheduled_rides
        FOR EACH ROW
        EXECUTE FUNCTION prevent_immutable_ride_field_changes();
END IF;
END $$;

-- ============================================================================
-- RLS POLICY: Tighten INSERT to enforce created_by = auth.uid()
-- ============================================================================

DO $$ BEGIN
IF EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create rides' AND tablename = 'scheduled_rides') THEN
    DROP POLICY "Contributors create rides" ON scheduled_rides;
END IF;

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
END $$;

-- ============================================================================
-- INDEX: Covering index for reminder cron query
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_scheduled_rides_reminders
    ON scheduled_rides(status, pickup_time, confirmation_status)
    WHERE status = 'SCHEDULED';
