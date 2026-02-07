-- ============================================================================
-- Migration: Respite Care Hardening
-- Addresses review findings:
--   1. Tighten RLS policies with role checks on write operations
--   2. Add phone/email/website validation constraints on respite_providers
--   3. Add audit trigger for review, log, and request status changes
--   4. Re-verify circle membership on request UPDATE policy
-- ============================================================================

-- ============================================================================
-- 1. Tighten respite_requests UPDATE policy to re-verify circle membership
-- ============================================================================

DROP POLICY IF EXISTS "Requesters update own requests" ON respite_requests;
CREATE POLICY "Requesters update own requests" ON respite_requests
    FOR UPDATE TO authenticated
    USING (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = respite_requests.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
        )
    )
    WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = respite_requests.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
        )
    );

-- ============================================================================
-- 2. Tighten respite_log INSERT to require CONTRIBUTOR+ role
-- ============================================================================

DROP POLICY IF EXISTS "Family members create respite log" ON respite_log;
CREATE POLICY "Family members create respite log" ON respite_log
    FOR INSERT TO authenticated
    WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = respite_log.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
              AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
        )
        AND has_feature_access(auth.uid(), 'respite_tracking')
    );

-- ============================================================================
-- 3. Tighten respite_log UPDATE to require CONTRIBUTOR+ role
-- ============================================================================

DROP POLICY IF EXISTS "Family members update respite log" ON respite_log;
CREATE POLICY "Family members update respite log" ON respite_log
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = respite_log.circle_id
              AND circle_members.user_id = auth.uid()
              AND circle_members.status = 'ACTIVE'
              AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
        )
        AND has_feature_access(auth.uid(), 'respite_tracking')
    );

-- ============================================================================
-- 4. Add validation constraints on respite_providers contact fields
-- ============================================================================

-- Phone: E.164-ish format or common formats, max 30 chars
ALTER TABLE respite_providers
    ADD CONSTRAINT respite_providers_phone_length_check
    CHECK (phone IS NULL OR length(phone) <= 30);

-- Email: basic format check, max 254 chars
ALTER TABLE respite_providers
    ADD CONSTRAINT respite_providers_email_format_check
    CHECK (email IS NULL OR (length(email) <= 254 AND email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'));

-- Website: basic URL format, max 500 chars
ALTER TABLE respite_providers
    ADD CONSTRAINT respite_providers_website_length_check
    CHECK (website IS NULL OR length(website) <= 500);

-- Provider name length constraint
ALTER TABLE respite_providers
    ADD CONSTRAINT respite_providers_name_length_check
    CHECK (length(name) >= 1 AND length(name) <= 200);

-- ============================================================================
-- 5. Audit trigger for respite_reviews changes
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_respite_review_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_events (circle_id, actor_user_id, event_type, object_type, object_id, metadata_json)
        VALUES (
            NEW.circle_id,
            NEW.reviewer_id,
            'RESPITE_REVIEW_CREATED',
            'respite_review',
            NEW.id,
            jsonb_build_object('provider_id', NEW.provider_id, 'rating', NEW.rating)
        );
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_events (circle_id, actor_user_id, event_type, object_type, object_id, metadata_json)
        VALUES (
            OLD.circle_id,
            OLD.reviewer_id,
            'RESPITE_REVIEW_DELETED',
            'respite_review',
            OLD.id,
            jsonb_build_object('provider_id', OLD.provider_id, 'rating', OLD.rating)
        );
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_audit_respite_review ON respite_reviews;
CREATE TRIGGER trg_audit_respite_review
    AFTER INSERT OR DELETE ON respite_reviews
    FOR EACH ROW
    EXECUTE FUNCTION audit_respite_review_change();

-- ============================================================================
-- 6. Audit trigger for respite_log changes
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_respite_log_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_events (circle_id, actor_user_id, event_type, object_type, object_id, metadata_json)
        VALUES (
            NEW.circle_id,
            NEW.created_by,
            'RESPITE_LOG_CREATED',
            'respite_log',
            NEW.id,
            jsonb_build_object('provider_type', NEW.provider_type, 'start_date', NEW.start_date, 'end_date', NEW.end_date)
        );
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_audit_respite_log ON respite_log;
CREATE TRIGGER trg_audit_respite_log
    AFTER INSERT ON respite_log
    FOR EACH ROW
    EXECUTE FUNCTION audit_respite_log_change();

-- ============================================================================
-- 7. Audit trigger for respite_requests status changes
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_respite_request_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO audit_events (circle_id, actor_user_id, event_type, object_type, object_id, metadata_json)
        VALUES (
            NEW.circle_id,
            NEW.created_by,
            'RESPITE_REQUEST_STATUS_CHANGED',
            'respite_request',
            NEW.id,
            jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status, 'provider_id', NEW.provider_id)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_audit_respite_request_status ON respite_requests;
CREATE TRIGGER trg_audit_respite_request_status
    AFTER UPDATE ON respite_requests
    FOR EACH ROW
    EXECUTE FUNCTION audit_respite_request_status_change();
