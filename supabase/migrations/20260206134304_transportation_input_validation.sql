-- ============================================================================
-- Migration: Transportation Input Validation
-- Description: Add phone format, website scheme, and HTML tag prevention constraints
-- ============================================================================

-- ============================================================================
-- PHONE FORMAT VALIDATION: transport_services
-- Allow digits, spaces, dashes, parens, plus sign, and dots (common phone formats)
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_phone_format') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_phone_format
            CHECK (phone IS NULL OR phone ~ '^\+?[\d\s\-\.\(\)]+$');
    END IF;
END $$;

-- ============================================================================
-- WEBSITE SCHEME VALIDATION: transport_services
-- Only allow http:// or https:// schemes
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_website_scheme') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_website_scheme
            CHECK (website IS NULL OR website ~ '^https?://');
    END IF;
END $$;

-- ============================================================================
-- HTML TAG PREVENTION: scheduled_rides text fields
-- Reject strings containing HTML tags to prevent stored XSS
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_purpose_no_html') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_purpose_no_html
            CHECK (purpose !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_pickup_no_html') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_pickup_no_html
            CHECK (pickup_address !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_dest_address_no_html') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_dest_address_no_html
            CHECK (destination_address !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_dest_name_no_html') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_dest_name_no_html
            CHECK (destination_name IS NULL OR destination_name !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_other_needs_no_html') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_other_needs_no_html
            CHECK (other_needs IS NULL OR other_needs !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ext_service_no_html') THEN
        ALTER TABLE scheduled_rides ADD CONSTRAINT chk_ext_service_no_html
            CHECK (external_service_name IS NULL OR external_service_name !~ '<[^>]+>');
    END IF;
END $$;

-- ============================================================================
-- HTML TAG PREVENTION: transport_services text fields
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_name_no_html') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_name_no_html
            CHECK (name !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_notes_no_html') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_notes_no_html
            CHECK (notes IS NULL OR notes !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_hours_no_html') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_hours_no_html
            CHECK (hours IS NULL OR hours !~ '<[^>]+>');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ts_area_no_html') THEN
        ALTER TABLE transport_services ADD CONSTRAINT chk_ts_area_no_html
            CHECK (service_area IS NULL OR service_area !~ '<[^>]+>');
    END IF;
END $$;
