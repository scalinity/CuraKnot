-- Migration: 0005_audit
-- Description: audit_events, notification_outbox tables
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: audit_events
-- ============================================================================

CREATE TABLE audit_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    actor_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    event_type text NOT NULL,
    object_type text NOT NULL,
    object_id uuid,
    ip_hash text,
    user_agent_hash text,
    metadata_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX audit_events_circle_id_idx ON audit_events(circle_id);
CREATE INDEX audit_events_created_at_idx ON audit_events(created_at DESC);
CREATE INDEX audit_events_event_type_idx ON audit_events(event_type);
CREATE INDEX audit_events_object_type_idx ON audit_events(object_type);
CREATE INDEX audit_events_actor_user_id_idx ON audit_events(actor_user_id);

COMMENT ON TABLE audit_events IS 'Immutable audit log for sensitive actions';

-- Event types reference
COMMENT ON COLUMN audit_events.event_type IS 'Event types:
- MEMBER_INVITED
- MEMBER_JOINED
- MEMBER_REMOVED
- ROLE_CHANGED
- CIRCLE_CREATED
- CIRCLE_UPDATED
- CIRCLE_DELETED
- PATIENT_CREATED
- PATIENT_ARCHIVED
- HANDOFF_PUBLISHED
- HANDOFF_REVISED
- TRANSCRIPT_ACCESSED
- EXPORT_GENERATED
- INVITE_CREATED
- INVITE_REVOKED
- SETTINGS_CHANGED
';

-- ============================================================================
-- TABLE: notification_outbox
-- ============================================================================

CREATE TABLE notification_outbox (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    notification_type text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    data_json jsonb DEFAULT '{}'::jsonb,
    status text DEFAULT 'PENDING' NOT NULL CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
    attempts int DEFAULT 0 NOT NULL,
    last_attempt_at timestamptz,
    sent_at timestamptz,
    error_message text,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX notification_outbox_status_idx ON notification_outbox(status) WHERE status = 'PENDING';
CREATE INDEX notification_outbox_user_id_idx ON notification_outbox(user_id);
CREATE INDEX notification_outbox_created_at_idx ON notification_outbox(created_at DESC);

COMMENT ON TABLE notification_outbox IS 'Queue for push notifications';

-- Notification types reference
COMMENT ON COLUMN notification_outbox.notification_type IS 'Notification types:
- HANDOFF_PUBLISHED
- TASK_ASSIGNED
- TASK_DUE_SOON
- TASK_OVERDUE
- MEMBER_JOINED
- EXPORT_READY
';

-- ============================================================================
-- FUNCTION: create_audit_event
-- ============================================================================

CREATE OR REPLACE FUNCTION create_audit_event(
    p_circle_id uuid,
    p_actor_user_id uuid,
    p_event_type text,
    p_object_type text,
    p_object_id uuid DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid AS $$
DECLARE
    v_event_id uuid;
BEGIN
    INSERT INTO audit_events (circle_id, actor_user_id, event_type, object_type, object_id, metadata_json)
    VALUES (p_circle_id, p_actor_user_id, p_event_type, p_object_type, p_object_id, p_metadata)
    RETURNING id INTO v_event_id;
    
    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: queue_notification
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_notification(
    p_user_id uuid,
    p_circle_id uuid,
    p_notification_type text,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid AS $$
DECLARE
    v_notification_id uuid;
BEGIN
    INSERT INTO notification_outbox (user_id, circle_id, notification_type, title, body, data_json)
    VALUES (p_user_id, p_circle_id, p_notification_type, p_title, p_body, p_data)
    RETURNING id INTO v_notification_id;
    
    RETURN v_notification_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: notify_circle_members
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_circle_members(
    p_circle_id uuid,
    p_exclude_user_id uuid,
    p_notification_type text,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS int AS $$
DECLARE
    v_count int := 0;
    v_member RECORD;
BEGIN
    FOR v_member IN 
        SELECT user_id 
        FROM circle_members 
        WHERE circle_id = p_circle_id 
        AND status = 'ACTIVE'
        AND user_id != p_exclude_user_id
    LOOP
        PERFORM queue_notification(
            v_member.user_id,
            p_circle_id,
            p_notification_type,
            p_title,
            p_body,
            p_data
        );
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGERS FOR AUDIT EVENTS
-- ============================================================================

-- Audit member role changes
CREATE OR REPLACE FUNCTION audit_member_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.role IS DISTINCT FROM NEW.role THEN
        PERFORM create_audit_event(
            NEW.circle_id,
            NEW.user_id, -- This should be the actor, but we don't have it here
            'ROLE_CHANGED',
            'circle_member',
            NEW.id,
            jsonb_build_object('old_role', OLD.role, 'new_role', NEW.role)
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Note: This trigger has a limitation - it uses the member's user_id as actor
-- In production, the actor should be passed from the application layer

-- ============================================================================
-- CLEANUP FUNCTIONS
-- ============================================================================

-- Clean up old notifications
CREATE OR REPLACE FUNCTION cleanup_old_notifications(p_days int DEFAULT 30)
RETURNS int AS $$
DECLARE
    v_count int;
BEGIN
    DELETE FROM notification_outbox
    WHERE created_at < now() - (p_days || ' days')::interval
    AND status IN ('SENT', 'FAILED');
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- Clean up expired invites
CREATE OR REPLACE FUNCTION cleanup_expired_invites()
RETURNS int AS $$
DECLARE
    v_count int;
BEGIN
    DELETE FROM circle_invites
    WHERE expires_at < now()
    AND used_at IS NULL
    AND revoked_at IS NULL;
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;
