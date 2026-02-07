-- ============================================================================
-- Migration: Care Cost Projection Fixes
-- Created: 2026-02-20
-- Description: Add expense reports storage bucket, audit triggers for
--              care_expenses, and composite index for query performance.
-- ============================================================================

-- ============================================================================
-- STORAGE: Create care-expense-reports bucket (private)
-- Used by generate-expense-report edge function for PDF/CSV exports
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'care-expense-reports',
    'care-expense-reports',
    false,
    52428800,  -- 50MB (reports with receipt images can be large)
    ARRAY['application/pdf', 'text/csv']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: Circle members can download their circle's reports
-- Path format: {circle_id}/{filename}
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle members read expense reports') THEN
        CREATE POLICY "Circle members read expense reports" ON storage.objects
            FOR SELECT USING (
                bucket_id = 'care-expense-reports'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 2
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = (string_to_array(name, '/'))[1]::uuid
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- Storage RLS: Admin/Owner can delete reports
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle admins delete expense reports') THEN
        CREATE POLICY "Circle admins delete expense reports" ON storage.objects
            FOR DELETE USING (
                bucket_id = 'care-expense-reports'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 2
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = (string_to_array(name, '/'))[1]::uuid
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

-- Note: INSERT handled by edge function using service_role (bypasses RLS)

-- ============================================================================
-- AUDIT: care_expenses audit trigger function
-- Logs expense INSERT, UPDATE, DELETE to audit_events
-- ============================================================================

CREATE OR REPLACE FUNCTION care_expenses_audit_fn()
RETURNS trigger AS $$
DECLARE
    v_circle_id uuid;
    v_actor_id uuid;
    v_object_id uuid;
    v_event_type text;
    v_metadata jsonb;
BEGIN
    v_actor_id := auth.uid();

    -- Skip if no authenticated user (e.g., system operations)
    IF v_actor_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_circle_id := OLD.circle_id;
        v_object_id := OLD.id;
        v_event_type := 'EXPENSE_DELETED';
        v_metadata := jsonb_build_object(
            'category', OLD.category,
            'amount', OLD.amount,
            'description', OLD.description
        );
    ELSIF TG_OP = 'UPDATE' THEN
        v_circle_id := NEW.circle_id;
        v_object_id := NEW.id;
        v_event_type := 'EXPENSE_UPDATED';
        v_metadata := jsonb_build_object(
            'category', NEW.category,
            'amount', NEW.amount,
            'old_amount', OLD.amount
        );
    ELSIF TG_OP = 'INSERT' THEN
        v_circle_id := NEW.circle_id;
        v_object_id := NEW.id;
        v_event_type := 'EXPENSE_CREATED';
        v_metadata := jsonb_build_object(
            'category', NEW.category,
            'amount', NEW.amount,
            'description', NEW.description
        );
    END IF;

    IF v_event_type IS NOT NULL AND v_circle_id IS NOT NULL THEN
        INSERT INTO audit_events (circle_id, actor_user_id, event_type, object_type, object_id, metadata_json)
        VALUES (v_circle_id, v_actor_id, v_event_type, 'care_expenses', v_object_id, v_metadata);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach audit trigger to care_expenses
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_care_expenses') THEN
        CREATE TRIGGER trg_audit_care_expenses
            AFTER INSERT OR UPDATE OR DELETE ON care_expenses
            FOR EACH ROW EXECUTE FUNCTION care_expenses_audit_fn();
    END IF;
END $$;

-- ============================================================================
-- INDEX: Composite index for expense queries by circle + patient + date
-- Optimizes the common query pattern in fetchExpenses and report generation
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_care_expenses_circle_patient_date
    ON care_expenses (circle_id, patient_id, expense_date DESC);
