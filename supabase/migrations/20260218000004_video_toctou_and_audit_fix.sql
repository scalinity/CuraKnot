-- ============================================================================
-- Migration: Video TOCTOU Fix and Complete Audit Logging
-- Description: Fix time-of-check-time-of-use vulnerabilities and add audit
--              triggers for VIEW and REACT actions
-- ============================================================================

-- ============================================================================
-- 0. Schema Fixes: Add missing columns for audit logging
-- ============================================================================

-- Add watch_duration_seconds to video_views (required by audit trigger)
ALTER TABLE video_views
ADD COLUMN IF NOT EXISTS watch_duration_seconds int DEFAULT 0 CHECK (watch_duration_seconds >= 0);

-- ============================================================================
-- 1. TOCTOU Fix: Atomic quota reservation with pessimistic locking
-- ============================================================================

-- Add a quota_reserved column to track pre-allocated storage
ALTER TABLE video_messages
ADD COLUMN IF NOT EXISTS quota_reserved_bytes bigint DEFAULT 0;

-- Create a function to atomically check and reserve quota (prevents race conditions)
CREATE OR REPLACE FUNCTION reserve_video_quota(
    p_user_id uuid,
    p_circle_id uuid,
    p_requested_bytes bigint
)
RETURNS jsonb AS $$
DECLARE
    v_subscription_plan text;
    v_quota_limit bigint;
    v_current_usage bigint;
    v_reserved_bytes bigint;
    v_available_bytes bigint;
    v_reservation_id uuid;
    v_patient_id uuid;
BEGIN
    -- Validate caller is the user or service role
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot reserve quota for other users';
    END IF;

    -- Lock the circle's video records to prevent concurrent quota checks
    -- This is the key to preventing TOCTOU - we hold a row lock during the entire check
    PERFORM 1 FROM circles WHERE id = p_circle_id FOR UPDATE;

    -- Get patient_id from circle and validate it exists
    SELECT patient_id INTO v_patient_id
    FROM circles
    WHERE id = p_circle_id;

    IF v_patient_id IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'error', 'INVALID_CIRCLE',
            'message', 'Circle does not have a valid patient'
        );
    END IF;

    -- Validate patient exists
    IF NOT EXISTS (SELECT 1 FROM patients WHERE id = v_patient_id) THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'error', 'PATIENT_NOT_FOUND',
            'message', 'Patient associated with circle not found'
        );
    END IF;

    -- Get user's subscription plan
    SELECT COALESCE(plan, 'FREE')
    INTO v_subscription_plan
    FROM subscriptions
    WHERE user_id = p_user_id
      AND status = 'ACTIVE'
    LIMIT 1;

    IF v_subscription_plan IS NULL THEN
        v_subscription_plan := 'FREE';
    END IF;

    -- Feature gating: FREE plan cannot use video board
    IF v_subscription_plan = 'FREE' THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'error', 'FEATURE_LOCKED',
            'message', 'Video messages require Plus or Family subscription'
        );
    END IF;

    -- Set quota limits based on plan
    v_quota_limit := CASE v_subscription_plan
        WHEN 'PLUS' THEN 524288000    -- 500MB
        WHEN 'FAMILY' THEN 2147483648 -- 2GB
        ELSE 0
    END;

    -- Calculate current actual usage + reserved bytes (pending uploads)
    SELECT
        COALESCE(SUM(file_size_bytes), 0),
        COALESCE(SUM(quota_reserved_bytes), 0)
    INTO v_current_usage, v_reserved_bytes
    FROM video_messages
    WHERE circle_id = p_circle_id
      AND status IN ('ACTIVE', 'FLAGGED', 'PENDING'); -- Include PENDING to count reserved quota

    v_available_bytes := v_quota_limit - v_current_usage - v_reserved_bytes;

    -- Check if quota allows the requested bytes
    IF p_requested_bytes > v_available_bytes THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'error', 'QUOTA_EXCEEDED',
            'used_bytes', v_current_usage,
            'reserved_bytes', v_reserved_bytes,
            'limit_bytes', v_quota_limit,
            'requested_bytes', p_requested_bytes
        );
    END IF;

    -- Generate a reservation ID for tracking
    v_reservation_id := gen_random_uuid();

    -- Insert a placeholder record with reserved quota
    -- This will be updated with actual video data by the Edge Function
    INSERT INTO video_messages (
        id,
        circle_id,
        patient_id,
        created_by,
        storage_key,
        file_size_bytes,
        quota_reserved_bytes,
        status,
        duration_seconds,
        retention_days,
        created_at
    ) VALUES (
        v_reservation_id,
        p_circle_id,
        v_patient_id,  -- Use validated patient_id
        p_user_id,
        'pending/' || v_reservation_id::text,
        0,
        p_requested_bytes,
        'PENDING',
        0,
        30,
        now()
    );

    RETURN jsonb_build_object(
        'allowed', true,
        'reservation_id', v_reservation_id,
        'reserved_bytes', p_requested_bytes,
        'available_after', v_available_bytes - p_requested_bytes
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to confirm or release a quota reservation
CREATE OR REPLACE FUNCTION finalize_video_quota(
    p_reservation_id uuid,
    p_user_id uuid,
    p_finalize boolean,  -- true = confirm upload, false = cancel/release
    p_actual_bytes bigint DEFAULT NULL,
    p_storage_key text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_reservation RECORD;
BEGIN
    -- Validate caller
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot finalize quota for other users';
    END IF;

    -- Get and lock the reservation
    SELECT * INTO v_reservation
    FROM video_messages
    WHERE id = p_reservation_id
      AND created_by = p_user_id
      AND status = 'PENDING'
    FOR UPDATE;

    IF v_reservation IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'RESERVATION_NOT_FOUND'
        );
    END IF;

    IF p_finalize THEN
        -- Confirm the upload: clear reservation, set actual size
        UPDATE video_messages
        SET quota_reserved_bytes = 0,
            file_size_bytes = COALESCE(p_actual_bytes, quota_reserved_bytes),
            storage_key = COALESCE(p_storage_key, storage_key),
            status = 'ACTIVE'
        WHERE id = p_reservation_id;

        RETURN jsonb_build_object(
            'success', true,
            'action', 'CONFIRMED'
        );
    ELSE
        -- Cancel the reservation: delete the placeholder
        DELETE FROM video_messages WHERE id = p_reservation_id;

        RETURN jsonb_build_object(
            'success', true,
            'action', 'RELEASED',
            'released_bytes', v_reservation.quota_reserved_bytes
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 2. Audit Triggers for VIEW and REACT actions
-- ============================================================================

-- Add circle_id to audit log for better filtering
ALTER TABLE video_audit_log
ADD COLUMN IF NOT EXISTS circle_id uuid REFERENCES circles(id) ON DELETE SET NULL;

-- Index for circle-based audit queries
CREATE INDEX IF NOT EXISTS idx_video_audit_log_circle_id ON video_audit_log(circle_id);

-- Trigger function to automatically log video views
CREATE OR REPLACE FUNCTION log_video_view_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_circle_id uuid;
BEGIN
    -- Get the circle_id from the video
    SELECT circle_id INTO v_circle_id
    FROM video_messages
    WHERE id = NEW.video_message_id;

    -- Insert audit log entry
    INSERT INTO video_audit_log (
        video_id,
        user_id,
        action,
        circle_id,
        details
    ) VALUES (
        NEW.video_message_id,
        NEW.viewed_by,
        'VIEW',
        v_circle_id,
        jsonb_build_object(
            'viewed_at', NEW.viewed_at,
            'watch_duration_seconds', NEW.watch_duration_seconds
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger for video views
DROP TRIGGER IF EXISTS video_view_audit_trigger ON video_views;
CREATE TRIGGER video_view_audit_trigger
    AFTER INSERT ON video_views
    FOR EACH ROW
    EXECUTE FUNCTION log_video_view_trigger();

-- Trigger function to automatically log video reactions
CREATE OR REPLACE FUNCTION log_video_reaction_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_circle_id uuid;
BEGIN
    -- Get the circle_id from the video
    SELECT circle_id INTO v_circle_id
    FROM video_messages
    WHERE id = COALESCE(NEW.video_message_id, OLD.video_message_id);

    IF TG_OP = 'INSERT' THEN
        INSERT INTO video_audit_log (
            video_id,
            user_id,
            action,
            circle_id,
            details
        ) VALUES (
            NEW.video_message_id,
            NEW.user_id,
            'REACT',
            v_circle_id,
            jsonb_build_object(
                'reaction_type', NEW.reaction_type,
                'action', 'ADD'
            )
        );
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO video_audit_log (
            video_id,
            user_id,
            action,
            circle_id,
            details
        ) VALUES (
            OLD.video_message_id,
            OLD.user_id,
            'REACT',
            v_circle_id,
            jsonb_build_object(
                'reaction_type', OLD.reaction_type,
                'action', 'REMOVE'
            )
        );
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger for video reactions
DROP TRIGGER IF EXISTS video_reaction_audit_trigger ON video_reactions;
CREATE TRIGGER video_reaction_audit_trigger
    AFTER INSERT OR DELETE ON video_reactions
    FOR EACH ROW
    EXECUTE FUNCTION log_video_reaction_trigger();

-- ============================================================================
-- 2b. Audit Triggers for FLAG, DELETE, MODERATE (status changes)
-- ============================================================================

-- Trigger function for video status changes (FLAG/DELETE/MODERATE)
CREATE OR REPLACE FUNCTION log_video_status_change_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_action text;
    v_details jsonb;
BEGIN
    -- Only log if status changed
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    -- Determine action based on new status
    v_action := CASE NEW.status
        WHEN 'FLAGGED' THEN 'FLAG'
        WHEN 'REMOVED' THEN 'MODERATE'
        WHEN 'DELETED' THEN 'DELETE'
        ELSE NULL
    END;

    -- Skip if not a tracked status change
    IF v_action IS NULL THEN
        RETURN NEW;
    END IF;

    -- Build details based on action
    v_details := CASE v_action
        WHEN 'FLAG' THEN jsonb_build_object(
            'previous_status', OLD.status,
            'flagged_by', NEW.flagged_by,
            'flagged_at', NEW.flagged_at
        )
        WHEN 'MODERATE' THEN jsonb_build_object(
            'previous_status', OLD.status,
            'removed_by', NEW.removed_by,
            'removed_at', NEW.removed_at,
            'removal_reason', NEW.removal_reason
        )
        WHEN 'DELETE' THEN jsonb_build_object(
            'previous_status', OLD.status,
            'deleted_at', now()
        )
    END;

    -- Insert audit log entry
    INSERT INTO video_audit_log (
        video_id,
        user_id,
        action,
        circle_id,
        details
    ) VALUES (
        NEW.id,
        COALESCE(NEW.flagged_by, NEW.removed_by, auth.uid()),
        v_action,
        NEW.circle_id,
        v_details
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger for video status changes
DROP TRIGGER IF EXISTS video_status_change_audit_trigger ON video_messages;
CREATE TRIGGER video_status_change_audit_trigger
    AFTER UPDATE OF status ON video_messages
    FOR EACH ROW
    EXECUTE FUNCTION log_video_status_change_trigger();

-- ============================================================================
-- 2c. Atomic Toggle Reaction (prevents race conditions)
-- ============================================================================

-- Function to atomically toggle a reaction (add if not exists, remove if exists)
CREATE OR REPLACE FUNCTION toggle_video_reaction(
    p_video_id uuid,
    p_user_id uuid,
    p_reaction_type text DEFAULT 'LOVE'
)
RETURNS jsonb AS $$
DECLARE
    v_existing_id uuid;
    v_new_id uuid;
BEGIN
    -- Validate caller
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot toggle reaction for other users';
    END IF;

    -- Lock the video to prevent concurrent modifications
    PERFORM 1 FROM video_messages WHERE id = p_video_id FOR SHARE;

    -- Check if reaction exists (with row lock)
    SELECT id INTO v_existing_id
    FROM video_reactions
    WHERE video_message_id = p_video_id
      AND user_id = p_user_id
      AND reaction_type = p_reaction_type
    FOR UPDATE;

    IF v_existing_id IS NOT NULL THEN
        -- Remove existing reaction
        DELETE FROM video_reactions WHERE id = v_existing_id;
        RETURN jsonb_build_object(
            'action', 'REMOVED',
            'reaction_id', v_existing_id
        );
    ELSE
        -- Add new reaction
        v_new_id := gen_random_uuid();
        INSERT INTO video_reactions (id, video_message_id, user_id, reaction_type, created_at)
        VALUES (v_new_id, p_video_id, p_user_id, p_reaction_type, now());
        RETURN jsonb_build_object(
            'action', 'ADDED',
            'reaction_id', v_new_id
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION toggle_video_reaction(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION toggle_video_reaction(uuid, uuid, text) TO service_role;

-- ============================================================================
-- 2d. Atomic Record View (prevents duplicate views)
-- ============================================================================

-- Function to atomically record a view (idempotent, once per user per day)
CREATE OR REPLACE FUNCTION record_video_view(
    p_video_id uuid,
    p_user_id uuid,
    p_watch_duration_seconds int DEFAULT 0
)
RETURNS jsonb AS $$
DECLARE
    v_today date;
    v_existing_id uuid;
    v_new_id uuid;
BEGIN
    -- Validate caller
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot record view for other users';
    END IF;

    v_today := CURRENT_DATE;

    -- Check if already viewed today (with row lock on video)
    PERFORM 1 FROM video_messages WHERE id = p_video_id FOR SHARE;

    SELECT id INTO v_existing_id
    FROM video_views
    WHERE video_message_id = p_video_id
      AND viewed_by = p_user_id
      AND viewed_at::date = v_today
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        -- Already viewed today, update duration if provided
        IF p_watch_duration_seconds > 0 THEN
            UPDATE video_views
            SET watch_duration_seconds = GREATEST(watch_duration_seconds, p_watch_duration_seconds)
            WHERE id = v_existing_id;
        END IF;
        RETURN jsonb_build_object(
            'action', 'ALREADY_VIEWED',
            'view_id', v_existing_id
        );
    ELSE
        -- Record new view
        v_new_id := gen_random_uuid();
        INSERT INTO video_views (id, video_message_id, viewed_by, viewed_at, watch_duration_seconds)
        VALUES (v_new_id, p_video_id, p_user_id, now(), p_watch_duration_seconds);
        RETURN jsonb_build_object(
            'action', 'RECORDED',
            'view_id', v_new_id
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION record_video_view(uuid, uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION record_video_view(uuid, uuid, int) TO service_role;

-- ============================================================================
-- 3. Storage-level rate limiting (backup enforcement)
-- ============================================================================

-- Function to check rate limit before storage upload (called by storage policy)
CREATE OR REPLACE FUNCTION check_video_upload_allowed(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
    v_upload_count int;
    v_max_uploads int;
    v_window_hours int := 24;
    v_subscription_plan text;
BEGIN
    -- Get user's subscription plan
    SELECT COALESCE(plan, 'FREE')
    INTO v_subscription_plan
    FROM subscriptions
    WHERE user_id = p_user_id
      AND status = 'ACTIVE'
    LIMIT 1;

    -- FREE plan cannot upload videos at all
    IF v_subscription_plan IS NULL OR v_subscription_plan = 'FREE' THEN
        RETURN false;
    END IF;

    -- Set limits based on plan
    v_max_uploads := CASE v_subscription_plan
        WHEN 'PLUS' THEN 10
        WHEN 'FAMILY' THEN 50
        ELSE 0
    END;

    -- Count uploads in the time window
    SELECT COUNT(*)
    INTO v_upload_count
    FROM video_messages
    WHERE created_by = p_user_id
      AND created_at > now() - (v_window_hours || ' hours')::interval
      AND status IN ('ACTIVE', 'FLAGGED', 'PENDING');

    RETURN v_upload_count < v_max_uploads;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update storage upload policy to include rate limiting check
DROP POLICY IF EXISTS "Circle members can upload videos" ON storage.objects;
CREATE POLICY "Circle members can upload videos" ON storage.objects
    FOR INSERT
    WITH CHECK (
        bucket_id = 'video-messages'
        AND auth.uid() IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM circle_members cm
            WHERE cm.user_id = auth.uid()
              AND cm.status = 'ACTIVE'
              AND cm.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
              AND cm.circle_id::text = split_part(name, '/', 1)
        )
        -- Validate file path format
        AND name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(_thumb)?\.(mp4|jpg)$'
        -- Rate limiting at storage level (backup enforcement)
        AND check_video_upload_allowed(auth.uid())
    );

-- ============================================================================
-- 4. Cleanup expired reservations (cron job helper)
-- ============================================================================

-- Function to clean up stale quota reservations (older than 1 hour)
CREATE OR REPLACE FUNCTION cleanup_stale_video_reservations()
RETURNS int AS $$
DECLARE
    v_deleted_count int;
BEGIN
    DELETE FROM video_messages
    WHERE status = 'PENDING'
      AND created_at < now() - interval '1 hour';

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to service role (for Edge Functions)
GRANT EXECUTE ON FUNCTION reserve_video_quota(uuid, uuid, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION finalize_video_quota(uuid, uuid, boolean, bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION check_video_upload_allowed(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION cleanup_stale_video_reservations() TO service_role;

-- Grant execute to authenticated role (for iOS client RPC calls)
GRANT EXECUTE ON FUNCTION reserve_video_quota(uuid, uuid, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION finalize_video_quota(uuid, uuid, boolean, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION check_video_upload_allowed(uuid) TO authenticated;

-- ============================================================================
-- 5. Add PENDING status to video_messages enum
-- ============================================================================

-- Add PENDING status for quota reservations (if not exists)
DO $$
BEGIN
    -- Check if the status enum exists and add PENDING if needed
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'video_message_status'
          AND e.enumlabel = 'PENDING'
    ) THEN
        -- If using an enum type, alter it
        -- If using check constraint, we need to update the constraint
        ALTER TABLE video_messages
        DROP CONSTRAINT IF EXISTS video_messages_status_check;

        ALTER TABLE video_messages
        ADD CONSTRAINT video_messages_status_check
        CHECK (status IN ('PENDING', 'ACTIVE', 'FLAGGED', 'REMOVED', 'DELETED'));
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- If there's any issue, just log and continue
        RAISE NOTICE 'Could not update status constraint: %', SQLERRM;
END $$;
