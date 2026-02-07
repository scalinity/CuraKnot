-- ============================================================================
-- Migration: Care Cost Projection
-- Created: 2026-02-20
-- Description: Tables for care expense tracking, cost scenario modeling,
--              local care cost benchmarks, and financial resource directory.
-- ============================================================================

-- ============================================================================
-- TABLE: care_expenses
-- Tracks actual caregiving expenses with optional insurance coverage
-- ============================================================================

CREATE TABLE IF NOT EXISTS care_expenses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,
    category text NOT NULL CHECK (category IN (
        'HOME_CARE', 'MEDICATIONS', 'SUPPLIES', 'TRANSPORTATION',
        'INSURANCE', 'EQUIPMENT', 'FACILITY', 'PROFESSIONAL'
    )),
    description text NOT NULL,
    vendor_name text,
    amount decimal(10, 2) NOT NULL CHECK (amount > 0 AND amount <= 1000000),
    expense_date date NOT NULL,
    is_recurring boolean NOT NULL DEFAULT false,
    recurrence_rule text CHECK (
        recurrence_rule IS NULL OR recurrence_rule IN ('WEEKLY', 'BIWEEKLY', 'MONTHLY')
    ),
    parent_expense_id uuid REFERENCES care_expenses(id) ON DELETE SET NULL,
    covered_by_insurance decimal(10, 2) NOT NULL DEFAULT 0 CHECK (covered_by_insurance >= 0),
    out_of_pocket decimal(10, 2) GENERATED ALWAYS AS (amount - covered_by_insurance) STORED,
    receipt_storage_key text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (covered_by_insurance <= amount),
    CHECK (NOT is_recurring OR recurrence_rule IS NOT NULL)
);

-- Indexes for care_expenses
CREATE INDEX IF NOT EXISTS idx_care_expenses_circle_date
    ON care_expenses (circle_id, expense_date DESC);

CREATE INDEX IF NOT EXISTS idx_care_expenses_patient_date
    ON care_expenses (patient_id, expense_date DESC);

CREATE INDEX IF NOT EXISTS idx_care_expenses_circle_category_date
    ON care_expenses (circle_id, category, expense_date DESC);

-- updated_at trigger (reuse existing function from initial migration)
CREATE TRIGGER care_expenses_updated_at
    BEFORE UPDATE ON care_expenses
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- TABLE: care_cost_estimates
-- Scenario-based cost projections for different care arrangements
-- ============================================================================

CREATE TABLE IF NOT EXISTS care_cost_estimates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    scenario_name text NOT NULL,
    scenario_type text NOT NULL CHECK (scenario_type IN (
        'CURRENT', 'FULL_TIME_HOME', 'TWENTY_FOUR_SEVEN',
        'ASSISTED_LIVING', 'MEMORY_CARE', 'NURSING_HOME', 'CUSTOM'
    )),
    is_current boolean NOT NULL DEFAULT false,
    home_care_hours_weekly int,
    home_care_hourly_rate decimal(10, 2),
    home_care_monthly decimal(10, 2),
    medications_monthly decimal(10, 2),
    supplies_monthly decimal(10, 2),
    transportation_monthly decimal(10, 2),
    facility_monthly decimal(10, 2),
    other_monthly decimal(10, 2),
    total_monthly decimal(10, 2) NOT NULL CHECK (total_monthly >= 0),
    medicare_coverage_pct decimal(5, 2) CHECK (medicare_coverage_pct >= 0 AND medicare_coverage_pct <= 100),
    medicaid_coverage_pct decimal(5, 2) CHECK (medicaid_coverage_pct >= 0 AND medicaid_coverage_pct <= 100),
    private_insurance_pct decimal(5, 2) CHECK (private_insurance_pct >= 0 AND private_insurance_pct <= 100),
    out_of_pocket_monthly decimal(10, 2),
    notes text,
    data_source text NOT NULL DEFAULT 'USER_INPUT',
    data_year int NOT NULL DEFAULT EXTRACT(YEAR FROM now()),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for care_cost_estimates
CREATE INDEX IF NOT EXISTS idx_care_cost_estimates_circle_current
    ON care_cost_estimates (circle_id, is_current);

CREATE UNIQUE INDEX IF NOT EXISTS idx_care_cost_estimates_circle_patient_type
    ON care_cost_estimates (circle_id, patient_id, scenario_type);

-- updated_at trigger
CREATE TRIGGER care_cost_estimates_updated_at
    BEFORE UPDATE ON care_cost_estimates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- TABLE: local_care_costs
-- Regional benchmark data for care cost comparisons
-- ============================================================================

CREATE TABLE IF NOT EXISTS local_care_costs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    state text NOT NULL,
    metro_area text,
    zip_code_prefix text,
    home_health_aide_hourly decimal(10, 2),
    homemaker_services_hourly decimal(10, 2),
    adult_day_health_daily decimal(10, 2),
    assisted_living_monthly decimal(10, 2),
    nursing_home_semi_private_daily decimal(10, 2),
    nursing_home_private_daily decimal(10, 2),
    memory_care_monthly decimal(10, 2),
    data_source text NOT NULL CHECK (data_source IN ('GENWORTH', 'CMS', 'USER_REPORTED')),
    data_year int NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(state, metro_area, zip_code_prefix, data_year)
);

-- Indexes for local_care_costs
CREATE INDEX IF NOT EXISTS idx_local_care_costs_state_zip
    ON local_care_costs (state, zip_code_prefix);

CREATE INDEX IF NOT EXISTS idx_local_care_costs_data_year
    ON local_care_costs (data_year DESC);

-- updated_at trigger
CREATE TRIGGER local_care_costs_updated_at
    BEFORE UPDATE ON local_care_costs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- TABLE: financial_resources
-- Curated directory of financial aid, benefits, and planning resources
-- ============================================================================

CREATE TABLE IF NOT EXISTS financial_resources (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    resource_type text NOT NULL CHECK (resource_type IN ('ARTICLE', 'CALCULATOR', 'DIRECTORY', 'OFFICIAL_LINK')),
    category text NOT NULL CHECK (category IN ('MEDICARE', 'MEDICAID', 'VA', 'TAX', 'PLANNING')),
    description text,
    url text,
    content_markdown text,
    states text[],
    is_featured boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for financial_resources
CREATE INDEX IF NOT EXISTS idx_financial_resources_category_active
    ON financial_resources (category, is_active);

CREATE INDEX IF NOT EXISTS idx_financial_resources_featured_active
    ON financial_resources (is_featured, is_active);

-- updated_at trigger
CREATE TRIGGER financial_resources_updated_at
    BEFORE UPDATE ON financial_resources
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- RLS: Enable Row Level Security on all tables
-- ============================================================================

ALTER TABLE care_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_cost_estimates ENABLE ROW LEVEL SECURITY;
ALTER TABLE local_care_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_resources ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES: care_expenses
-- ============================================================================

-- SELECT: Active circle members can read their circle's expenses
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members read expenses') THEN
        CREATE POLICY "Circle members read expenses" ON care_expenses
            FOR SELECT TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = care_expenses.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- INSERT: Contributors, Admins, and Owners can create expenses
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create expenses') THEN
        CREATE POLICY "Contributors create expenses" ON care_expenses
            FOR INSERT TO authenticated
            WITH CHECK (
                created_by = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = care_expenses.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

-- UPDATE: Creator or Admin/Owner of the circle can update expenses
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Creator or admin update expenses') THEN
        CREATE POLICY "Creator or admin update expenses" ON care_expenses
            FOR UPDATE TO authenticated
            USING (
                created_by = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = care_expenses.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('ADMIN', 'OWNER')
                )
            )
            WITH CHECK (
                created_by = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = care_expenses.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

-- DELETE: Creator or Admin/Owner of the circle can delete expenses
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Creator or admin delete expenses') THEN
        CREATE POLICY "Creator or admin delete expenses" ON care_expenses
            FOR DELETE TO authenticated
            USING (
                created_by = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = care_expenses.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: care_cost_estimates
-- ============================================================================

-- SELECT: Active circle members can read their circle's estimates
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members read cost estimates') THEN
        CREATE POLICY "Circle members read cost estimates" ON care_cost_estimates
            FOR SELECT TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = care_cost_estimates.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- ALL: service_role can perform all operations (for edge functions)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages cost estimates') THEN
        CREATE POLICY "Service role manages cost estimates" ON care_cost_estimates
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- INSERT: Contributors, Admins, and Owners can create estimates
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create cost estimates') THEN
        CREATE POLICY "Contributors create cost estimates" ON care_cost_estimates
            FOR INSERT TO authenticated
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = care_cost_estimates.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: local_care_costs
-- ============================================================================

-- SELECT: All authenticated users can read benchmark data
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users read local care costs') THEN
        CREATE POLICY "Authenticated users read local care costs" ON local_care_costs
            FOR SELECT TO authenticated
            USING (true);
    END IF;
END $$;

-- ALL: service_role only for managing benchmark data
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages local care costs') THEN
        CREATE POLICY "Service role manages local care costs" ON local_care_costs
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: financial_resources
-- ============================================================================

-- SELECT: All authenticated users can read active resources
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users read financial resources') THEN
        CREATE POLICY "Authenticated users read financial resources" ON financial_resources
            FOR SELECT TO authenticated
            USING (is_active = true);
    END IF;
END $$;

-- ALL: service_role only for managing resource directory
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages financial resources') THEN
        CREATE POLICY "Service role manages financial resources" ON financial_resources
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- ============================================================================
-- STORAGE: Create care-expense-receipts bucket (private)
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'care-expense-receipts',
    'care-expense-receipts',
    false,
    10485760,  -- 10MB
    ARRAY['image/jpeg', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: Circle members with CONTRIBUTOR+ role can upload receipts
-- Path format: {circle_id}/{expense_id}/{filename}
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle members upload expense receipts') THEN
        CREATE POLICY "Circle members upload expense receipts" ON storage.objects
            FOR INSERT WITH CHECK (
                bucket_id = 'care-expense-receipts'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 3
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = (string_to_array(name, '/'))[1]::uuid
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                      AND circle_members.role IN ('CONTRIBUTOR', 'ADMIN', 'OWNER')
                )
            );
    END IF;
END $$;

-- Storage RLS: Circle members can read receipts from their circles
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle members read expense receipts') THEN
        CREATE POLICY "Circle members read expense receipts" ON storage.objects
            FOR SELECT USING (
                bucket_id = 'care-expense-receipts'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 3
                AND EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = (string_to_array(name, '/'))[1]::uuid
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- Storage RLS: Creator or Admin/Owner can delete receipts
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Circle admins delete expense receipts') THEN
        CREATE POLICY "Circle admins delete expense receipts" ON storage.objects
            FOR DELETE USING (
                bucket_id = 'care-expense-receipts'
                AND auth.uid() IS NOT NULL
                AND array_length(string_to_array(name, '/'), 1) >= 3
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

-- ============================================================================
-- SEED DATA: National fallback care costs (Genworth 2023 survey)
-- ============================================================================

INSERT INTO local_care_costs (
    state,
    metro_area,
    zip_code_prefix,
    home_health_aide_hourly,
    homemaker_services_hourly,
    adult_day_health_daily,
    assisted_living_monthly,
    nursing_home_semi_private_daily,
    nursing_home_private_daily,
    memory_care_monthly,
    data_source,
    data_year
) VALUES (
    'US',
    NULL,
    NULL,
    33.99,
    30.00,
    78.00,
    5350.00,
    260.00,
    297.00,
    6935.00,
    'GENWORTH',
    2023
) ON CONFLICT (state, metro_area, zip_code_prefix, data_year) DO NOTHING;

-- ============================================================================
-- SEED DATA: Financial resources directory
-- ============================================================================

INSERT INTO financial_resources (title, resource_type, category, description, url, is_featured, is_active)
VALUES
    (
        'Medicare Home Health Coverage',
        'OFFICIAL_LINK',
        'MEDICARE',
        'Official Medicare guide to home health services coverage, including eligibility requirements and what Medicare covers for home-based care.',
        'https://www.medicare.gov/coverage/home-health-services',
        true,
        true
    ),
    (
        'Medicaid Long-Term Care',
        'OFFICIAL_LINK',
        'MEDICAID',
        'Federal Medicaid information on long-term services and supports, including home and community-based services and institutional care.',
        'https://www.medicaid.gov/medicaid/long-term-services-supports',
        true,
        true
    ),
    (
        'VA Aid & Attendance',
        'OFFICIAL_LINK',
        'VA',
        'Veterans Affairs Aid and Attendance benefit for veterans and survivors who need help with daily activities or are housebound.',
        'https://www.va.gov/pension/aid-attendance-housebound',
        true,
        true
    ),
    (
        'Tax Deductions for Caregiving',
        'ARTICLE',
        'TAX',
        'IRS Publication 502 detailing medical and dental expense deductions, including qualifying caregiving expenses for tax purposes.',
        'https://www.irs.gov/publications/p502',
        false,
        true
    ),
    (
        'National Academy of Elder Law Attorneys',
        'DIRECTORY',
        'PLANNING',
        'Find elder law attorneys who specialize in Medicaid planning, estate planning, guardianship, and other legal issues affecting older adults and their caregivers.',
        'https://www.naela.org',
        false,
        true
    ),
    (
        'National Council on Aging Benefits',
        'ARTICLE',
        'PLANNING',
        'Comprehensive guide to top benefit programs for older adults, including financial assistance, healthcare, and community resources.',
        'https://www.ncoa.org/article/top-10-benefits-programs-for-older-adults',
        false,
        true
    )
ON CONFLICT DO NOTHING;
