-- ============================================================================
-- Migration: Hospital Discharge Planning Wizard
-- Description: Tables for discharge wizard, templates, and checklist tracking
-- Date: 2026-02-09
-- ============================================================================

-- ============================================================================
-- TABLE: discharge_templates (System templates for discharge checklists)
-- ============================================================================

CREATE TABLE IF NOT EXISTS discharge_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name text NOT NULL,
    discharge_type text NOT NULL,  -- GENERAL | SURGERY | STROKE | CARDIAC | FALL | PSYCHIATRIC | OTHER
    description text,
    items jsonb NOT NULL DEFAULT '[]'::jsonb,  -- Array of {category, item_text, sort_order, is_required, task_template, resource_links}
    is_system boolean NOT NULL DEFAULT false,  -- System templates are read-only
    is_active boolean NOT NULL DEFAULT true,
    sort_order int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_discharge_templates_type
    ON discharge_templates(discharge_type)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_discharge_templates_system
    ON discharge_templates(is_system, is_active);

CREATE TRIGGER discharge_templates_updated_at
    BEFORE UPDATE ON discharge_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE discharge_templates IS 'Pre-built checklist templates for different discharge scenarios';

-- ============================================================================
-- TABLE: discharge_records (Wizard state for each discharge)
-- ============================================================================

CREATE TABLE IF NOT EXISTS discharge_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,

    -- Discharge info
    facility_name text NOT NULL,
    discharge_date date NOT NULL,
    admission_date date,
    reason_for_stay text NOT NULL,
    discharge_type text NOT NULL DEFAULT 'OTHER',  -- GENERAL | SURGERY | STROKE | CARDIAC | FALL | PSYCHIATRIC | OTHER
    template_id uuid REFERENCES discharge_templates(id),

    -- Status tracking
    status text NOT NULL DEFAULT 'IN_PROGRESS',  -- IN_PROGRESS | COMPLETED | CANCELLED
    current_step int NOT NULL DEFAULT 1,  -- 1-7 wizard steps

    -- Completion tracking
    completed_at timestamptz,
    completed_by uuid REFERENCES auth.users(id),

    -- Generated outputs
    generated_tasks uuid[] DEFAULT '{}',
    generated_handoff_id uuid REFERENCES handoffs(id),
    generated_shifts uuid[] DEFAULT '{}',
    generated_binder_items uuid[] DEFAULT '{}',

    -- Wizard state (for resume capability)
    checklist_state_json jsonb NOT NULL DEFAULT '{}'::jsonb,  -- Full checklist state
    shift_assignments_json jsonb DEFAULT '{}'::jsonb,  -- First week shift assignments
    medication_changes_json jsonb DEFAULT '[]'::jsonb,  -- Scanned/entered med changes

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_discharge_records_circle
    ON discharge_records(circle_id, status);

CREATE INDEX IF NOT EXISTS idx_discharge_records_patient
    ON discharge_records(patient_id, status);

CREATE INDEX IF NOT EXISTS idx_discharge_records_status
    ON discharge_records(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_discharge_records_user
    ON discharge_records(created_by, status);

CREATE TRIGGER discharge_records_updated_at
    BEFORE UPDATE ON discharge_records
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE discharge_records IS 'Discharge wizard state and generated outputs tracking';

-- ============================================================================
-- TABLE: discharge_checklist_items (Individual checklist item progress)
-- ============================================================================

CREATE TABLE IF NOT EXISTS discharge_checklist_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    discharge_record_id uuid NOT NULL REFERENCES discharge_records(id) ON DELETE CASCADE,
    template_item_id text NOT NULL,  -- Reference to item in template JSON
    category text NOT NULL,  -- BEFORE_LEAVING | MEDICATIONS | EQUIPMENT | HOME_PREP | FIRST_WEEK
    item_text text NOT NULL,
    sort_order int NOT NULL DEFAULT 0,

    -- Status
    is_completed boolean NOT NULL DEFAULT false,
    completed_at timestamptz,
    completed_by uuid REFERENCES auth.users(id),

    -- Task linkage (optional)
    create_task boolean NOT NULL DEFAULT false,
    task_id uuid REFERENCES tasks(id),
    assigned_to uuid REFERENCES auth.users(id),
    due_date date,

    -- Notes
    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(discharge_record_id, template_item_id)
);

CREATE INDEX IF NOT EXISTS idx_discharge_checklist_record
    ON discharge_checklist_items(discharge_record_id);

CREATE INDEX IF NOT EXISTS idx_discharge_checklist_category
    ON discharge_checklist_items(discharge_record_id, category);

CREATE INDEX IF NOT EXISTS idx_discharge_checklist_task
    ON discharge_checklist_items(task_id)
    WHERE task_id IS NOT NULL;

CREATE TRIGGER discharge_checklist_items_updated_at
    BEFORE UPDATE ON discharge_checklist_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE discharge_checklist_items IS 'Progress tracking for individual checklist items in discharge wizard';

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE discharge_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE discharge_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE discharge_checklist_items ENABLE ROW LEVEL SECURITY;

-- Templates: Anyone can read system templates; users can read/write their own custom templates
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'discharge_templates'
        AND policyname = 'Anyone can read active templates'
    ) THEN
        CREATE POLICY "Anyone can read active templates"
            ON discharge_templates FOR SELECT
            USING (is_active = true);
    END IF;
END $$;

-- Discharge Records: Circle members can access
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'discharge_records'
        AND policyname = 'Circle members can read discharge records'
    ) THEN
        CREATE POLICY "Circle members can read discharge records"
            ON discharge_records FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = discharge_records.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'discharge_records'
        AND policyname = 'Contributors can create discharge records'
    ) THEN
        CREATE POLICY "Contributors can create discharge records"
            ON discharge_records FOR INSERT
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = discharge_records.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                    AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'discharge_records'
        AND policyname = 'Contributors can update discharge records'
    ) THEN
        CREATE POLICY "Contributors can update discharge records"
            ON discharge_records FOR UPDATE
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = discharge_records.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                    AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'discharge_records'
        AND policyname = 'Admins can delete discharge records'
    ) THEN
        CREATE POLICY "Admins can delete discharge records"
            ON discharge_records FOR DELETE
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = discharge_records.circle_id
                    AND circle_members.user_id = auth.uid()
                    AND circle_members.status = 'ACTIVE'
                    AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- Checklist Items: Access through discharge record
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'discharge_checklist_items'
        AND policyname = 'Circle members can read checklist items'
    ) THEN
        CREATE POLICY "Circle members can read checklist items"
            ON discharge_checklist_items FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM discharge_records dr
                    JOIN circle_members cm ON cm.circle_id = dr.circle_id
                    WHERE dr.id = discharge_checklist_items.discharge_record_id
                    AND cm.user_id = auth.uid()
                    AND cm.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'discharge_checklist_items'
        AND policyname = 'Contributors can modify checklist items'
    ) THEN
        CREATE POLICY "Contributors can modify checklist items"
            ON discharge_checklist_items FOR ALL
            USING (
                EXISTS (
                    SELECT 1 FROM discharge_records dr
                    JOIN circle_members cm ON cm.circle_id = dr.circle_id
                    WHERE dr.id = discharge_checklist_items.discharge_record_id
                    AND cm.user_id = auth.uid()
                    AND cm.status = 'ACTIVE'
                    AND cm.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- SEED DATA: System Discharge Templates
-- ============================================================================

INSERT INTO discharge_templates (template_name, discharge_type, description, items, is_system, sort_order) VALUES
('General Discharge', 'OTHER', 'Standard discharge checklist for general hospital stays', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Review medication list with nurse", "sort_order": 2, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule follow-up appointments", "sort_order": 3, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Ask about warning signs to watch for", "sort_order": 4, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Fill new prescriptions", "sort_order": 1, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Set up medication organizer", "sort_order": 2, "is_required": false},
  {"category": "MEDICATIONS", "item_text": "Reconcile with existing medications", "sort_order": 3, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Prepare bedroom for easy access", "sort_order": 1, "is_required": false},
  {"category": "HOME_PREP", "item_text": "Install grab bars in bathroom", "sort_order": 2, "is_required": false},
  {"category": "FIRST_WEEK", "item_text": "Watch for warning signs listed in discharge papers", "sort_order": 1, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Keep discharge papers accessible", "sort_order": 2, "is_required": true}
]'::jsonb, true, 1),

('Post-Surgery', 'SURGERY', 'Comprehensive checklist for surgical discharge including wound care and pain management', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Review wound care instructions", "sort_order": 2, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule follow-up with surgeon", "sort_order": 3, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Get pain management plan", "sort_order": 4, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Fill pain medication prescription", "sort_order": 1, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Fill antibiotics if prescribed", "sort_order": 2, "is_required": false},
  {"category": "MEDICATIONS", "item_text": "Get stool softeners if needed", "sort_order": 3, "is_required": false},
  {"category": "EQUIPMENT", "item_text": "Obtain wound care supplies", "sort_order": 1, "is_required": true},
  {"category": "EQUIPMENT", "item_text": "Get mobility aids (walker, crutches)", "sort_order": 2, "is_required": false},
  {"category": "HOME_PREP", "item_text": "Set up recovery area (bed, supplies within reach)", "sort_order": 1, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Install grab bars in bathroom", "sort_order": 2, "is_required": false},
  {"category": "HOME_PREP", "item_text": "Move bedroom to first floor if needed", "sort_order": 3, "is_required": false},
  {"category": "HOME_PREP", "item_text": "Remove area rugs and tripping hazards", "sort_order": 4, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Monitor incision for signs of infection", "sort_order": 1, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Track pain levels and medication effectiveness", "sort_order": 2, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Follow activity restrictions", "sort_order": 3, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Report any fever, increased pain, or drainage", "sort_order": 4, "is_required": true}
]'::jsonb, true, 2),

('Stroke Recovery', 'STROKE', 'Specialized checklist for stroke patients including rehabilitation and monitoring', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule rehabilitation therapy (PT/OT/Speech)", "sort_order": 2, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule neurology follow-up", "sort_order": 3, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Review stroke warning signs (FAST)", "sort_order": 4, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Fill blood thinner prescription", "sort_order": 1, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Fill blood pressure medications", "sort_order": 2, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Set up pill organizer with clear labeling", "sort_order": 3, "is_required": true},
  {"category": "EQUIPMENT", "item_text": "Get mobility aids (wheelchair, walker)", "sort_order": 1, "is_required": false},
  {"category": "EQUIPMENT", "item_text": "Get adaptive equipment (utensils, dressing aids)", "sort_order": 2, "is_required": false},
  {"category": "EQUIPMENT", "item_text": "Get blood pressure monitor", "sort_order": 3, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Install grab bars in bathroom", "sort_order": 1, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Move bedroom to first floor if needed", "sort_order": 2, "is_required": false},
  {"category": "HOME_PREP", "item_text": "Remove area rugs and tripping hazards", "sort_order": 3, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Arrange furniture for wheelchair/walker access", "sort_order": 4, "is_required": false},
  {"category": "FIRST_WEEK", "item_text": "Begin home therapy exercises", "sort_order": 1, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Monitor blood pressure twice daily", "sort_order": 2, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Watch for stroke symptoms (FAST: Face, Arms, Speech, Time)", "sort_order": 3, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Report any new weakness, confusion, or vision changes", "sort_order": 4, "is_required": true}
]'::jsonb, true, 3),

('Cardiac', 'CARDIAC', 'Heart-focused discharge checklist including monitoring and cardiac rehabilitation', '[
  {"category": "BEFORE_LEAVING", "item_text": "Get written discharge instructions", "sort_order": 1, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Schedule cardiology follow-up", "sort_order": 2, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Enroll in cardiac rehabilitation program", "sort_order": 3, "is_required": true},
  {"category": "BEFORE_LEAVING", "item_text": "Review heart attack warning signs", "sort_order": 4, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Fill heart medications (beta blockers, ACE inhibitors)", "sort_order": 1, "is_required": true},
  {"category": "MEDICATIONS", "item_text": "Fill blood thinners if prescribed", "sort_order": 2, "is_required": false},
  {"category": "MEDICATIONS", "item_text": "Get nitroglycerin if prescribed", "sort_order": 3, "is_required": false},
  {"category": "MEDICATIONS", "item_text": "Fill cholesterol medications", "sort_order": 4, "is_required": false},
  {"category": "EQUIPMENT", "item_text": "Get blood pressure monitor", "sort_order": 1, "is_required": true},
  {"category": "EQUIPMENT", "item_text": "Get pulse oximeter if recommended", "sort_order": 2, "is_required": false},
  {"category": "EQUIPMENT", "item_text": "Get digital scale for daily weights", "sort_order": 3, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Prepare heart-healthy meals", "sort_order": 1, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Set up medication reminder system", "sort_order": 2, "is_required": true},
  {"category": "HOME_PREP", "item_text": "Create low-sodium grocery list", "sort_order": 3, "is_required": false},
  {"category": "FIRST_WEEK", "item_text": "Monitor blood pressure twice daily", "sort_order": 1, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Weigh daily (watch for fluid retention)", "sort_order": 2, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Follow activity restrictions", "sort_order": 3, "is_required": true},
  {"category": "FIRST_WEEK", "item_text": "Report any chest pain, shortness of breath, or swelling immediately", "sort_order": 4, "is_required": true}
]'::jsonb, true, 4)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to check if user has access to discharge_wizard feature
CREATE OR REPLACE FUNCTION has_discharge_wizard_access(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
    v_plan text;
    v_features jsonb;
BEGIN
    -- Get user's subscription plan
    SELECT plan INTO v_plan
    FROM subscriptions
    WHERE user_id = p_user_id
    AND status = 'ACTIVE';

    IF v_plan IS NULL THEN
        v_plan := 'FREE';
    END IF;

    -- Check if plan includes discharge_wizard feature
    SELECT features_json INTO v_features
    FROM plan_limits
    WHERE plan = v_plan;

    RETURN v_features ? 'discharge_wizard';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION has_discharge_wizard_access IS 'Check if user has premium access to discharge wizard feature';

-- Function to get active discharge record for a patient
CREATE OR REPLACE FUNCTION get_active_discharge_record(
    p_circle_id uuid,
    p_patient_id uuid
)
RETURNS uuid AS $$
    SELECT id
    FROM discharge_records
    WHERE circle_id = p_circle_id
    AND patient_id = p_patient_id
    AND status = 'IN_PROGRESS'
    ORDER BY created_at DESC
    LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_active_discharge_record IS 'Get the most recent in-progress discharge record for a patient';
