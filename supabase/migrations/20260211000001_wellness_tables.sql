-- Migration: 20260211000001_wellness_tables
-- Description: Caregiver Wellness & Burnout Detection tables
-- Date: 2026-02-11

-- ============================================================================
-- TABLE: wellness_checkins
-- Description: Weekly wellness check-ins (USER-PRIVATE)
-- ============================================================================

CREATE TABLE IF NOT EXISTS wellness_checkins (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Check-in data (1-5 scales, capacity is 1-4)
    stress_level int NOT NULL CHECK (stress_level BETWEEN 1 AND 5),
    sleep_quality int NOT NULL CHECK (sleep_quality BETWEEN 1 AND 5),
    capacity_level int NOT NULL CHECK (capacity_level BETWEEN 1 AND 4),

    -- Encrypted notes (AES-256-GCM)
    -- Notes are encrypted client-side before storage
    notes_encrypted text,
    notes_nonce text,
    notes_tag text,

    -- Calculated scores (0-100)
    wellness_score int CHECK (wellness_score BETWEEN 0 AND 100),
    behavioral_score int CHECK (behavioral_score BETWEEN 0 AND 100),
    total_score int CHECK (total_score BETWEEN 0 AND 100),

    -- Metadata
    week_start date NOT NULL, -- Start of the check-in week (Monday)
    skipped boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- One check-in per user per week
    CONSTRAINT wellness_checkins_unique_user_week UNIQUE (user_id, week_start)
);

COMMENT ON TABLE wellness_checkins IS 'Weekly wellness check-ins - USER PRIVATE, not shared with circle';
COMMENT ON COLUMN wellness_checkins.notes_encrypted IS 'AES-256-GCM encrypted notes (base64)';
COMMENT ON COLUMN wellness_checkins.notes_nonce IS 'AES-256-GCM nonce/IV (base64)';
COMMENT ON COLUMN wellness_checkins.notes_tag IS 'AES-256-GCM auth tag (base64)';

-- Update trigger
CREATE TRIGGER wellness_checkins_updated_at
    BEFORE UPDATE ON wellness_checkins
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- TABLE: wellness_alerts
-- Description: Burnout alerts and intervention suggestions (USER-PRIVATE)
-- ============================================================================

CREATE TABLE IF NOT EXISTS wellness_alerts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Alert data
    risk_level text NOT NULL CHECK (risk_level IN ('LOW', 'MODERATE', 'HIGH')),
    alert_type text NOT NULL CHECK (alert_type IN ('BURNOUT_RISK', 'TREND_DECLINE', 'MISSED_CHECKIN')),
    title text NOT NULL,
    message text NOT NULL,

    -- Delegation suggestions (array of {userId, fullName} from circle_members, NOT wellness data)
    -- Privacy: These names come from circle membership, not from comparing wellness scores
    delegation_suggestions jsonb,

    -- Status tracking
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISMISSED', 'RESOLVED')),
    dismissed_at timestamptz,

    -- Metadata
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE wellness_alerts IS 'Burnout alerts - USER PRIVATE, suggestions from circle membership not wellness data';
COMMENT ON COLUMN wellness_alerts.delegation_suggestions IS 'Array of {userId, fullName} from circle_members, NOT based on others wellness scores';

-- Update trigger
CREATE TRIGGER wellness_alerts_updated_at
    BEFORE UPDATE ON wellness_alerts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- TABLE: wellness_preferences
-- Description: User preferences for wellness feature (USER-PRIVATE)
-- ============================================================================

CREATE TABLE IF NOT EXISTS wellness_preferences (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Notification preferences
    enable_burnout_alerts boolean NOT NULL DEFAULT true,
    enable_weekly_reminders boolean NOT NULL DEFAULT true,
    reminder_day_of_week int CHECK (reminder_day_of_week BETWEEN 0 AND 6), -- 0=Sunday
    reminder_time time, -- Local time for reminder

    -- Privacy (future: opt-in to share capacity level only)
    share_capacity_with_circle boolean NOT NULL DEFAULT false,

    -- Metadata
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE wellness_preferences IS 'Wellness notification preferences - USER PRIVATE';

-- Update trigger
CREATE TRIGGER wellness_preferences_updated_at
    BEFORE UPDATE ON wellness_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- INDEXES
-- ============================================================================

-- wellness_checkins: Query by user, ordered by date
CREATE INDEX IF NOT EXISTS idx_wellness_checkins_user_created
    ON wellness_checkins(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wellness_checkins_user_week
    ON wellness_checkins(user_id, week_start DESC);

-- wellness_alerts: Query active alerts for user
CREATE INDEX IF NOT EXISTS idx_wellness_alerts_user_status
    ON wellness_alerts(user_id, status)
    WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_wellness_alerts_created
    ON wellness_alerts(created_at DESC);

-- ============================================================================
-- RLS POLICIES (USER-PRIVATE: user_id = auth.uid())
-- ============================================================================

ALTER TABLE wellness_checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellness_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellness_preferences ENABLE ROW LEVEL SECURITY;

-- wellness_checkins: User can only access their own check-ins
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'wellness_checkins'
        AND policyname = 'Users can view own check-ins'
    ) THEN
        CREATE POLICY "Users can view own check-ins"
            ON wellness_checkins FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'wellness_checkins'
        AND policyname = 'Users can insert own check-ins'
    ) THEN
        CREATE POLICY "Users can insert own check-ins"
            ON wellness_checkins FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'wellness_checkins'
        AND policyname = 'Users can update own check-ins'
    ) THEN
        CREATE POLICY "Users can update own check-ins"
            ON wellness_checkins FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'wellness_checkins'
        AND policyname = 'Users can delete own check-ins'
    ) THEN
        CREATE POLICY "Users can delete own check-ins"
            ON wellness_checkins FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- wellness_alerts: User can only access their own alerts
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'wellness_alerts'
        AND policyname = 'Users can view own alerts'
    ) THEN
        CREATE POLICY "Users can view own alerts"
            ON wellness_alerts FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'wellness_alerts'
        AND policyname = 'Users can update own alerts'
    ) THEN
        CREATE POLICY "Users can update own alerts"
            ON wellness_alerts FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- wellness_preferences: User can only access their own preferences
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'wellness_preferences'
        AND policyname = 'Users can manage own preferences'
    ) THEN
        CREATE POLICY "Users can manage own preferences"
            ON wellness_preferences FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- SUBSCRIPTION FEATURE GATE
-- ============================================================================

-- Note: wellness_checkins feature is already defined in plan_limits.features_json
-- for PLUS and FAMILY plans in 20260205000001_subscriptions.sql
--
-- FREE plan: wellness_checkins NOT in features_json (show preview only)
-- PLUS plan: wellness_checkins IN features_json (full access)
-- FAMILY plan: wellness_checkins IN features_json (full access)
--
-- Use has_feature_access(user_id, 'wellness_checkins') to check tier gating
