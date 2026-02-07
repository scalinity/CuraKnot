-- Migration: 0016_employer
-- Description: Employer/Insurer Distribution - B2B benefit codes
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: organizations
-- ============================================================================

CREATE TABLE organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    slug text UNIQUE,
    logo_url text,
    settings_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX organizations_slug_idx ON organizations(slug) WHERE slug IS NOT NULL;

CREATE TRIGGER organizations_updated_at
    BEFORE UPDATE ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE organizations IS 'Employer/insurer organizations for B2B distribution';

-- ============================================================================
-- TABLE: organization_admins
-- ============================================================================

CREATE TABLE organization_admins (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role text DEFAULT 'ADMIN' NOT NULL CHECK (role IN ('OWNER', 'ADMIN')),
    created_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT organization_admins_unique UNIQUE (org_id, user_id)
);

CREATE INDEX organization_admins_org_idx ON organization_admins(org_id);
CREATE INDEX organization_admins_user_idx ON organization_admins(user_id);

COMMENT ON TABLE organization_admins IS 'Admin users for organizations';

-- ============================================================================
-- TABLE: benefit_codes
-- ============================================================================

CREATE TABLE benefit_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    code text UNIQUE NOT NULL,
    plan text NOT NULL CHECK (plan IN ('PLUS', 'FAMILY', 'ENTERPRISE')),
    description text,
    max_redemptions int NOT NULL,
    redeemed_count int DEFAULT 0 NOT NULL,
    expires_at timestamptz,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL,
    revoked_at timestamptz
);

CREATE INDEX benefit_codes_org_idx ON benefit_codes(org_id);
CREATE INDEX benefit_codes_code_idx ON benefit_codes(code);
CREATE INDEX benefit_codes_active_idx ON benefit_codes(expires_at) WHERE revoked_at IS NULL;

COMMENT ON TABLE benefit_codes IS 'Benefit codes for premium plan access';

-- ============================================================================
-- TABLE: benefit_redemptions
-- ============================================================================

CREATE TABLE benefit_redemptions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    benefit_code_id uuid NOT NULL REFERENCES benefit_codes(id) ON DELETE CASCADE,
    circle_id uuid REFERENCES circles(id) ON DELETE SET NULL,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    redeemed_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX benefit_redemptions_code_idx ON benefit_redemptions(benefit_code_id);
CREATE INDEX benefit_redemptions_user_idx ON benefit_redemptions(user_id);
CREATE INDEX benefit_redemptions_circle_idx ON benefit_redemptions(circle_id) WHERE circle_id IS NOT NULL;

COMMENT ON TABLE benefit_redemptions IS 'Record of benefit code redemptions';

-- ============================================================================
-- FUNCTION: redeem_benefit_code
-- ============================================================================

CREATE OR REPLACE FUNCTION redeem_benefit_code(
    p_code text,
    p_user_id uuid,
    p_circle_id uuid DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_benefit_code benefit_codes%ROWTYPE;
    v_redemption_id uuid;
BEGIN
    -- Get and lock the code
    SELECT * INTO v_benefit_code
    FROM benefit_codes
    WHERE code = upper(trim(p_code))
    FOR UPDATE;
    
    IF v_benefit_code IS NULL THEN
        RETURN jsonb_build_object('error', 'Invalid code');
    END IF;
    
    IF v_benefit_code.revoked_at IS NOT NULL THEN
        RETURN jsonb_build_object('error', 'Code has been revoked');
    END IF;
    
    IF v_benefit_code.expires_at IS NOT NULL AND v_benefit_code.expires_at < now() THEN
        RETURN jsonb_build_object('error', 'Code has expired');
    END IF;
    
    IF v_benefit_code.redeemed_count >= v_benefit_code.max_redemptions THEN
        RETURN jsonb_build_object('error', 'Code has reached maximum redemptions');
    END IF;
    
    -- Check if user already redeemed this code
    IF EXISTS (
        SELECT 1 FROM benefit_redemptions
        WHERE benefit_code_id = v_benefit_code.id AND user_id = p_user_id
    ) THEN
        RETURN jsonb_build_object('error', 'You have already redeemed this code');
    END IF;
    
    -- Create redemption
    INSERT INTO benefit_redemptions (benefit_code_id, circle_id, user_id)
    VALUES (v_benefit_code.id, p_circle_id, p_user_id)
    RETURNING id INTO v_redemption_id;
    
    -- Increment counter
    UPDATE benefit_codes
    SET redeemed_count = redeemed_count + 1
    WHERE id = v_benefit_code.id;
    
    -- Upgrade circle plan if provided
    IF p_circle_id IS NOT NULL THEN
        UPDATE circles
        SET plan = v_benefit_code.plan
        WHERE id = p_circle_id;
    END IF;
    
    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        p_circle_id,
        p_user_id,
        'BENEFIT_CODE_REDEEMED',
        'benefit_code',
        v_benefit_code.id,
        jsonb_build_object(
            'org_id', v_benefit_code.org_id,
            'plan', v_benefit_code.plan,
            'redemption_id', v_redemption_id
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'redemption_id', v_redemption_id,
        'plan', v_benefit_code.plan,
        'org_name', (SELECT name FROM organizations WHERE id = v_benefit_code.org_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: get_org_metrics (aggregated, k-anonymous)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_org_metrics(
    p_org_id uuid,
    p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_metrics jsonb;
    v_k_threshold int := 5;  -- k-anonymity threshold
BEGIN
    -- Check org admin
    IF NOT EXISTS (
        SELECT 1 FROM organization_admins
        WHERE org_id = p_org_id AND user_id = p_user_id
    ) THEN
        RETURN jsonb_build_object('error', 'Not an organization admin');
    END IF;
    
    SELECT jsonb_build_object(
        'codes', jsonb_build_object(
            'total', COUNT(*),
            'active', COUNT(*) FILTER (WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())),
            'total_redemptions', SUM(redeemed_count)
        ),
        'usage', CASE 
            WHEN (SELECT COUNT(*) FROM benefit_redemptions br 
                  JOIN benefit_codes bc ON br.benefit_code_id = bc.id 
                  WHERE bc.org_id = p_org_id) >= v_k_threshold 
            THEN jsonb_build_object(
                'unique_users', (
                    SELECT COUNT(DISTINCT user_id) 
                    FROM benefit_redemptions br 
                    JOIN benefit_codes bc ON br.benefit_code_id = bc.id 
                    WHERE bc.org_id = p_org_id
                ),
                'circles_upgraded', (
                    SELECT COUNT(DISTINCT circle_id) 
                    FROM benefit_redemptions br 
                    JOIN benefit_codes bc ON br.benefit_code_id = bc.id 
                    WHERE bc.org_id = p_org_id AND circle_id IS NOT NULL
                )
            )
            ELSE jsonb_build_object('message', 'Insufficient data for privacy-safe reporting')
        END
    ) INTO v_metrics
    FROM benefit_codes
    WHERE org_id = p_org_id;
    
    RETURN v_metrics;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE benefit_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE benefit_redemptions ENABLE ROW LEVEL SECURITY;

-- organizations: Admins can view their orgs
CREATE POLICY organizations_select ON organizations
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM organization_admins WHERE org_id = organizations.id AND user_id = auth.uid())
    );

-- organization_admins: Owners can manage
CREATE POLICY organization_admins_select ON organization_admins
    FOR SELECT USING (
        user_id = auth.uid() OR EXISTS (
            SELECT 1 FROM organization_admins oa 
            WHERE oa.org_id = organization_admins.org_id AND oa.user_id = auth.uid() AND oa.role = 'OWNER'
        )
    );

-- benefit_codes: Org admins can view
CREATE POLICY benefit_codes_select ON benefit_codes
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM organization_admins WHERE org_id = benefit_codes.org_id AND user_id = auth.uid())
    );

CREATE POLICY benefit_codes_insert ON benefit_codes
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM organization_admins WHERE org_id = benefit_codes.org_id AND user_id = auth.uid())
    );

-- benefit_redemptions: User can see their own
CREATE POLICY benefit_redemptions_select ON benefit_redemptions
    FOR SELECT USING (user_id = auth.uid());
