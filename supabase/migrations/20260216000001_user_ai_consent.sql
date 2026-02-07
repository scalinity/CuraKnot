-- ============================================================================
-- Migration: User AI Consent
-- Description: Track user consent for AI processing of PHI data
-- ============================================================================

-- ============================================================================
-- TABLE: user_ai_consent
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_ai_consent (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    ai_processing_enabled boolean NOT NULL DEFAULT false,
    consent_given_at timestamptz,
    consent_version text,  -- Track which consent version was accepted
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Comment on table
COMMENT ON TABLE user_ai_consent IS 'Tracks user consent for AI processing of health data (PHI)';
COMMENT ON COLUMN user_ai_consent.ai_processing_enabled IS 'Whether user has consented to AI processing of their data';
COMMENT ON COLUMN user_ai_consent.consent_version IS 'Version of consent terms accepted (e.g., "v1.0")';

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE user_ai_consent ENABLE ROW LEVEL SECURITY;

-- Users can only read and update their own consent
CREATE POLICY "Users manage own consent"
    ON user_ai_consent
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ============================================================================
-- TRIGGER: Update updated_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_user_ai_consent_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    -- Auto-set consent_given_at when enabling
    IF NEW.ai_processing_enabled = true AND OLD.ai_processing_enabled = false THEN
        NEW.consent_given_at = now();
    END IF;
    -- Clear consent_given_at when disabling
    IF NEW.ai_processing_enabled = false AND OLD.ai_processing_enabled = true THEN
        NEW.consent_given_at = NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_ai_consent_timestamp
    BEFORE UPDATE ON user_ai_consent
    FOR EACH ROW
    EXECUTE FUNCTION update_user_ai_consent_timestamp();

-- ============================================================================
-- FUNCTION: Check AI consent (for use in Edge Functions and RPC)
-- ============================================================================

CREATE OR REPLACE FUNCTION check_user_ai_consent(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
    v_enabled boolean;
BEGIN
    SELECT ai_processing_enabled INTO v_enabled
    FROM user_ai_consent
    WHERE user_id = p_user_id;

    -- Default to false if no record exists
    RETURN COALESCE(v_enabled, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION check_user_ai_consent(uuid) TO authenticated;
