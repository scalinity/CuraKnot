-- ============================================================================
-- Migration: Document Scans for Universal Document Scanner
-- Description: Tables, indexes, RLS, and functions for document scanning feature
-- ============================================================================

-- ============================================================================
-- TABLE: document_scans
-- ============================================================================

CREATE TABLE IF NOT EXISTS document_scans (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    created_by uuid NOT NULL REFERENCES users(id),

    -- Storage (array of Supabase Storage paths)
    storage_keys text[] NOT NULL,
    page_count int NOT NULL DEFAULT 1,

    -- OCR Results (from VisionKit or Cloud)
    ocr_text text,
    ocr_confidence float,
    ocr_provider text CHECK (ocr_provider IN ('VISION', 'CLOUD')),

    -- Classification
    document_type text CHECK (document_type IN (
        'PRESCRIPTION', 'LAB_RESULT', 'DISCHARGE', 'BILL', 'EOB',
        'APPOINTMENT', 'INSURANCE_CARD', 'MEDICATION_LIST', 'OTHER'
    )),
    classification_confidence float,
    classification_source text CHECK (classification_source IN ('AI', 'USER_OVERRIDE')),

    -- Extraction (FAMILY tier only)
    extracted_fields_json jsonb,
    extraction_confidence float,

    -- Routing
    routed_to_type text CHECK (routed_to_type IN ('BINDER', 'BILLING', 'HANDOFF', 'INBOX')),
    routed_to_id uuid,
    routed_at timestamptz,
    routed_by uuid REFERENCES users(id),

    -- Status tracking
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN (
        'PENDING', 'PROCESSING', 'READY', 'ROUTED', 'FAILED'
    )),
    error_message text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_document_scans_circle
    ON document_scans(circle_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_document_scans_status
    ON document_scans(status) WHERE status NOT IN ('ROUTED', 'FAILED');
CREATE INDEX IF NOT EXISTS idx_document_scans_patient
    ON document_scans(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_document_scans_created_by
    ON document_scans(created_by, created_at DESC);

-- Updated_at trigger
CREATE TRIGGER update_document_scans_updated_at
    BEFORE UPDATE ON document_scans
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE document_scans IS 'Scanned documents with AI classification and field extraction';

-- ============================================================================
-- TABLE: document_type_definitions
-- ============================================================================

CREATE TABLE IF NOT EXISTS document_type_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    type_key text NOT NULL UNIQUE,
    display_name text NOT NULL,
    route_to text NOT NULL CHECK (route_to IN ('BINDER_MEDS', 'BINDER_INSURANCE', 'BINDER_CONTACTS', 'BINDER_DOCS', 'BILLING', 'HANDOFF_DRAFT', 'INBOX')),
    extraction_schema_json jsonb NOT NULL DEFAULT '{"fields": []}'::jsonb,
    classification_keywords text[] DEFAULT '{}',
    icon text,
    sort_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true
);

-- Seed document type definitions
INSERT INTO document_type_definitions (type_key, display_name, route_to, extraction_schema_json, classification_keywords, icon, sort_order) VALUES
('PRESCRIPTION', 'Prescription', 'BINDER_MEDS',
 '{"fields": ["medication", "dosage", "frequency", "prescriber", "pharmacy", "rxNumber", "fillDate", "refills"]}'::jsonb,
 ARRAY['prescription', 'rx', 'refill', 'dispense', 'pharmacy', 'medication'],
 'pills.fill', 1),
('LAB_RESULT', 'Lab Results', 'HANDOFF_DRAFT',
 '{"fields": ["testName", "result", "normalRange", "performedDate", "orderedBy", "lab"]}'::jsonb,
 ARRAY['lab', 'laboratory', 'test', 'blood', 'urine', 'specimen', 'reference range'],
 'flask.fill', 2),
('DISCHARGE', 'Discharge Summary', 'HANDOFF_DRAFT',
 '{"fields": ["facility", "dischargeDate", "diagnosis", "followUpInstructions", "medications"]}'::jsonb,
 ARRAY['discharge', 'hospital', 'admitted', 'diagnosis', 'aftercare', 'follow-up'],
 'building.2.fill', 3),
('BILL', 'Bill/Invoice', 'BILLING',
 '{"fields": ["provider", "serviceDate", "totalAmount", "amountDue", "dueDate", "accountNumber"]}'::jsonb,
 ARRAY['bill', 'invoice', 'statement', 'amount due', 'pay by', 'balance'],
 'dollarsign.circle.fill', 4),
('EOB', 'Insurance EOB', 'BILLING',
 '{"fields": ["provider", "serviceDate", "claimNumber", "amountBilled", "amountAllowed", "patientResponsibility"]}'::jsonb,
 ARRAY['explanation of benefits', 'eob', 'claim', 'allowed amount', 'your responsibility'],
 'shield.fill', 5),
('APPOINTMENT', 'Appointment Notice', 'BINDER_CONTACTS',
 '{"fields": ["provider", "specialty", "appointmentDate", "appointmentTime", "location", "phone", "instructions"]}'::jsonb,
 ARRAY['appointment', 'schedule', 'visit', 'please arrive', 'reminder'],
 'calendar', 6),
('INSURANCE_CARD', 'Insurance Card', 'BINDER_INSURANCE',
 '{"fields": ["insuranceName", "memberId", "groupNumber", "rxBin", "rxPcn", "customerServicePhone"]}'::jsonb,
 ARRAY['member id', 'group', 'subscriber', 'plan', 'coverage', 'rx bin', 'pcn'],
 'creditcard.fill', 7),
('MEDICATION_LIST', 'Medication List', 'BINDER_MEDS',
 '{"fields": ["medications"]}'::jsonb,
 ARRAY['medication list', 'current medications', 'med list', 'prescriptions'],
 'list.bullet', 8),
('OTHER', 'Other Document', 'INBOX',
 '{"fields": []}'::jsonb,
 ARRAY[]::text[],
 'doc.fill', 99)
ON CONFLICT (type_key) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    route_to = EXCLUDED.route_to,
    extraction_schema_json = EXCLUDED.extraction_schema_json,
    classification_keywords = EXCLUDED.classification_keywords,
    icon = EXCLUDED.icon,
    sort_order = EXCLUDED.sort_order;

-- ============================================================================
-- ADD PROVENANCE COLUMNS TO EXISTING TABLES
-- ============================================================================

-- Link binder_items to scanned documents
ALTER TABLE binder_items
ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES document_scans(id) ON DELETE SET NULL;

-- Link financial_items to scanned documents
ALTER TABLE financial_items
ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES document_scans(id) ON DELETE SET NULL;

-- Link handoffs to scanned documents
ALTER TABLE handoffs
ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES document_scans(id) ON DELETE SET NULL;

-- Link inbox_items to scanned documents
ALTER TABLE inbox_items
ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES document_scans(id) ON DELETE SET NULL;

-- Indexes for provenance lookups
CREATE INDEX IF NOT EXISTS idx_binder_items_source_doc
    ON binder_items(source_document_id) WHERE source_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_financial_items_source_doc
    ON financial_items(source_document_id) WHERE source_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_handoffs_source_doc
    ON handoffs(source_document_id) WHERE source_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inbox_items_source_doc
    ON inbox_items(source_document_id) WHERE source_document_id IS NOT NULL;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE document_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_type_definitions ENABLE ROW LEVEL SECURITY;

-- document_scans: Members can read scans from their circles
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members can read circle scans') THEN
        CREATE POLICY "Members can read circle scans"
            ON document_scans FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = document_scans.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- document_scans: Contributors+ can create scans
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors can create scans') THEN
        CREATE POLICY "Contributors can create scans"
            ON document_scans FOR INSERT
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = document_scans.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                )
                AND created_by = auth.uid()
            );
    END IF;
END $$;

-- document_scans: Creators can update their own scans (before routing)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Creators can update own scans') THEN
        CREATE POLICY "Creators can update own scans"
            ON document_scans FOR UPDATE
            USING (created_by = auth.uid() AND status != 'ROUTED')
            WITH CHECK (created_by = auth.uid() AND status != 'ROUTED');
    END IF;
END $$;

-- document_scans: Owners/Admins can delete scans
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can delete scans') THEN
        CREATE POLICY "Admins can delete scans"
            ON document_scans FOR DELETE
            USING (
                created_by = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = document_scans.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- document_type_definitions: Everyone can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can read document types') THEN
        CREATE POLICY "Anyone can read document types"
            ON document_type_definitions FOR SELECT
            USING (true);
    END IF;
END $$;

-- FREE tier scan limit enforcement (RLS policy)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Enforce scan limit for FREE tier') THEN
        CREATE POLICY "Enforce scan limit for FREE tier"
            ON document_scans FOR INSERT
            WITH CHECK (
                -- PLUS and FAMILY: unlimited
                EXISTS (
                    SELECT 1 FROM subscriptions s
                    WHERE s.user_id = auth.uid()
                      AND s.status = 'ACTIVE'
                      AND s.plan IN ('PLUS', 'FAMILY')
                )
                OR
                -- FREE tier: 5 scans per month
                (
                    SELECT COUNT(*) FROM document_scans ds
                    WHERE ds.created_by = auth.uid()
                      AND ds.created_at >= date_trunc('month', now())
                ) < 5
            );
    END IF;
END $$;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Check document scan usage limit
CREATE OR REPLACE FUNCTION check_document_scan_limit(
    p_user_id uuid,
    p_circle_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_plan text;
    v_current_count int;
    v_limit int;
BEGIN
    -- Get user's subscription plan
    SELECT COALESCE(s.plan, 'FREE') INTO v_plan
    FROM subscriptions s
    WHERE s.user_id = p_user_id AND s.status = 'ACTIVE';

    v_plan := COALESCE(v_plan, 'FREE');

    IF v_plan IN ('PLUS', 'FAMILY') THEN
        -- Unlimited for paid tiers
        RETURN jsonb_build_object(
            'allowed', true,
            'current', NULL,
            'limit', NULL,
            'tier', v_plan,
            'unlimited', true
        );
    END IF;

    -- FREE tier: 5 scans/month
    v_limit := 5;

    SELECT COUNT(*) INTO v_current_count
    FROM document_scans
    WHERE created_by = p_user_id
      AND created_at >= date_trunc('month', now());

    RETURN jsonb_build_object(
        'allowed', v_current_count < v_limit,
        'current', v_current_count,
        'limit', v_limit,
        'tier', v_plan,
        'unlimited', false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment document scan usage (for tracking)
CREATE OR REPLACE FUNCTION increment_document_scan_usage(
    p_user_id uuid,
    p_circle_id uuid,
    p_scan_id uuid
)
RETURNS void AS $$
BEGIN
    INSERT INTO usage_metrics (
        user_id,
        circle_id,
        metric_type,
        period_start,
        period_end,
        count
    ) VALUES (
        p_user_id,
        p_circle_id,
        'DOCUMENT_SCAN',
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + interval '1 month' - interval '1 day')::date,
        1
    )
    ON CONFLICT (user_id, circle_id, metric_type, period_start)
    DO UPDATE SET
        count = usage_metrics.count + 1,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get default routing for document type
CREATE OR REPLACE FUNCTION get_document_routing(p_document_type text)
RETURNS jsonb AS $$
DECLARE
    v_definition document_type_definitions%ROWTYPE;
BEGIN
    SELECT * INTO v_definition
    FROM document_type_definitions
    WHERE type_key = p_document_type AND is_active = true;

    IF v_definition IS NULL THEN
        RETURN jsonb_build_object(
            'route_to', 'INBOX',
            'extraction_schema', '{"fields": []}'::jsonb
        );
    END IF;

    RETURN jsonb_build_object(
        'route_to', v_definition.route_to,
        'extraction_schema', v_definition.extraction_schema_json,
        'display_name', v_definition.display_name,
        'icon', v_definition.icon
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- STORAGE BUCKET CONFIGURATION (run in Supabase Dashboard)
-- ============================================================================
-- Note: Create storage bucket 'scanned-documents' via Supabase Dashboard
-- with the following settings:
-- - Public: false
-- - File size limit: 10MB
-- - Allowed MIME types: image/jpeg, image/png, application/pdf
--
-- Storage RLS policies to add:
-- 1. SELECT: Members can read scans from their circles
-- 2. INSERT: Contributors can upload to their circles
-- 3. DELETE: Creators and admins can delete

COMMENT ON TABLE document_scans IS 'Scanned documents with AI classification and field extraction.

Storage bucket: scanned-documents
Path pattern: {circle_id}/{scan_id}/{page_number}.jpg

Tier gating:
- FREE: 5 scans/month, manual classification only
- PLUS: Unlimited scans, AI classification
- FAMILY: Unlimited scans, AI classification + field extraction

Document types:
- PRESCRIPTION → Binder > Medications
- LAB_RESULT → Handoff draft
- DISCHARGE → Handoff draft
- BILL → Billing
- EOB → Billing
- APPOINTMENT → Binder > Contacts
- INSURANCE_CARD → Binder > Insurance
- MEDICATION_LIST → Binder > Medications
- OTHER → Care Inbox
';
