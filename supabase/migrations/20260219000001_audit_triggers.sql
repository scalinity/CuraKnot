-- Migration: audit_triggers
-- Description: Add audit logging triggers for sensitive operations:
--   binder_items modifications, tasks deletion, handoffs deletion, circle settings changes
-- Date: 2026-02-19

-- ============================================================================
-- GENERIC AUDIT TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_trigger_fn()
RETURNS trigger AS $$
DECLARE
    v_circle_id uuid;
    v_actor_id uuid;
    v_object_id uuid;
    v_event_type text;
    v_object_type text;
    v_metadata jsonb := '{}'::jsonb;
BEGIN
    v_actor_id := auth.uid();

    -- Skip if no authenticated user (e.g., system operations)
    IF v_actor_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    v_object_type := TG_TABLE_NAME;

    -- Determine circle_id and object_id based on table
    IF TG_TABLE_NAME = 'binder_items' THEN
        IF TG_OP = 'DELETE' THEN
            v_circle_id := OLD.circle_id;
            v_object_id := OLD.id;
            v_event_type := 'BINDER_ITEM_DELETED';
            v_metadata := jsonb_build_object('title', OLD.title, 'type', OLD.type);
        ELSIF TG_OP = 'UPDATE' THEN
            v_circle_id := NEW.circle_id;
            v_object_id := NEW.id;
            v_event_type := 'BINDER_ITEM_UPDATED';
            v_metadata := jsonb_build_object('title', NEW.title, 'type', NEW.type);
        ELSIF TG_OP = 'INSERT' THEN
            v_circle_id := NEW.circle_id;
            v_object_id := NEW.id;
            v_event_type := 'BINDER_ITEM_CREATED';
            v_metadata := jsonb_build_object('title', NEW.title, 'type', NEW.type);
        END IF;

    ELSIF TG_TABLE_NAME = 'tasks' THEN
        IF TG_OP = 'DELETE' THEN
            v_circle_id := OLD.circle_id;
            v_object_id := OLD.id;
            v_event_type := 'TASK_DELETED';
            v_metadata := jsonb_build_object('title', OLD.title, 'status', OLD.status);
        END IF;

    ELSIF TG_TABLE_NAME = 'handoffs' THEN
        IF TG_OP = 'DELETE' THEN
            v_circle_id := OLD.circle_id;
            v_object_id := OLD.id;
            v_event_type := 'HANDOFF_DELETED';
            v_metadata := jsonb_build_object('title', OLD.title, 'type', OLD.type, 'status', OLD.status);
        END IF;

    ELSIF TG_TABLE_NAME = 'circles' THEN
        IF TG_OP = 'UPDATE' THEN
            v_circle_id := NEW.id;
            v_object_id := NEW.id;
            v_event_type := 'CIRCLE_SETTINGS_CHANGED';
            -- Track which columns changed (without logging actual PHI values)
            v_metadata := jsonb_build_object(
                'name_changed', (OLD.name IS DISTINCT FROM NEW.name),
                'icon_changed', (OLD.icon IS DISTINCT FROM NEW.icon),
                'plan_changed', (OLD.plan IS DISTINCT FROM NEW.plan),
                'settings_changed', (OLD.settings_json IS DISTINCT FROM NEW.settings_json)
            );
        END IF;
    END IF;

    -- Only insert if we determined an event type
    IF v_event_type IS NOT NULL AND v_circle_id IS NOT NULL THEN
        INSERT INTO audit_events (circle_id, actor_user_id, event_type, object_type, object_id, metadata_json)
        VALUES (v_circle_id, v_actor_id, v_event_type, v_object_type, v_object_id, v_metadata);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- ATTACH TRIGGERS
-- ============================================================================

-- Binder items: audit INSERT, UPDATE, DELETE
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_binder_items') THEN
        CREATE TRIGGER trg_audit_binder_items
            AFTER INSERT OR UPDATE OR DELETE ON binder_items
            FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
    END IF;
END $$;

-- Tasks: audit DELETE only (creation/updates covered by app-level audit)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_tasks_delete') THEN
        CREATE TRIGGER trg_audit_tasks_delete
            AFTER DELETE ON tasks
            FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
    END IF;
END $$;

-- Handoffs: audit DELETE only
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_handoffs_delete') THEN
        CREATE TRIGGER trg_audit_handoffs_delete
            AFTER DELETE ON handoffs
            FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
    END IF;
END $$;

-- Circles: audit UPDATE (settings changes)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_circles_update') THEN
        CREATE TRIGGER trg_audit_circles_update
            AFTER UPDATE ON circles
            FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
    END IF;
END $$;
