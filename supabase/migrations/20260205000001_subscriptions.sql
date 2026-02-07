-- ============================================================================
-- Migration: Subscriptions and Usage Tracking
-- Description: Premium tier subscription management and usage metering
-- ============================================================================

-- ============================================================================
-- TABLE: subscriptions
-- ============================================================================

CREATE TABLE IF NOT EXISTS subscriptions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan text NOT NULL DEFAULT 'FREE',  -- FREE | PLUS | FAMILY
    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | CANCELLED | PAST_DUE | TRIALING | GRACE_PERIOD
    provider text NOT NULL DEFAULT 'NONE',  -- NONE | APPLE | STRIPE | EMPLOYER
    provider_subscription_id text,
    provider_product_id text,
    current_period_start timestamptz,
    current_period_end timestamptz,
    cancel_at_period_end boolean NOT NULL DEFAULT false,
    trial_end timestamptz,
    grace_period_end timestamptz,
    employer_code_id uuid REFERENCES benefit_codes(id),
    metadata_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(user_id)
);

-- Index for provider lookups (webhook processing)
CREATE INDEX IF NOT EXISTS idx_subscriptions_provider
    ON subscriptions(provider, provider_subscription_id)
    WHERE provider_subscription_id IS NOT NULL;

-- Index for status checks
CREATE INDEX IF NOT EXISTS idx_subscriptions_status
    ON subscriptions(status, current_period_end);

-- ============================================================================
-- TABLE: usage_metrics
-- ============================================================================

CREATE TABLE IF NOT EXISTS usage_metrics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    metric_type text NOT NULL,  -- AUDIO_HANDOFF | AI_MESSAGE | EXPORT | STORAGE_BYTES
    period_start date NOT NULL,
    period_end date NOT NULL,
    count bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(user_id, circle_id, metric_type, period_start)
);

-- Index for usage queries
CREATE INDEX IF NOT EXISTS idx_usage_metrics_lookup
    ON usage_metrics(user_id, metric_type, period_start);

-- ============================================================================
-- TABLE: subscription_events (Audit Log)
-- ============================================================================

CREATE TABLE IF NOT EXISTS subscription_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id uuid NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    event_type text NOT NULL,  -- CREATED | UPGRADED | DOWNGRADED | CANCELLED | RENEWED | GRACE_ENTERED | EXPIRED
    from_plan text,
    to_plan text,
    provider_event_id text,
    metadata_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscription_events_sub
    ON subscription_events(subscription_id, created_at DESC);

-- ============================================================================
-- TABLE: plan_limits (Configuration)
-- ============================================================================

CREATE TABLE IF NOT EXISTS plan_limits (
    plan text PRIMARY KEY,  -- FREE | PLUS | FAMILY
    max_circles int NOT NULL,
    max_members_per_circle int NOT NULL,
    max_patients_per_circle int NOT NULL,
    handoff_history_days int,  -- NULL = unlimited
    max_binder_items int,  -- NULL = unlimited
    max_active_tasks int,  -- NULL = unlimited
    max_audio_handoffs_per_month int,  -- NULL = unlimited
    max_storage_bytes bigint NOT NULL,
    max_exports_per_month int,  -- NULL = unlimited
    max_ai_messages_per_month int,  -- NULL = unlimited
    features_json jsonb NOT NULL DEFAULT '[]'::jsonb,  -- Array of feature flags
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Seed plan limits
INSERT INTO plan_limits (plan, max_circles, max_members_per_circle, max_patients_per_circle, handoff_history_days, max_binder_items, max_active_tasks, max_audio_handoffs_per_month, max_storage_bytes, max_exports_per_month, max_ai_messages_per_month, features_json) VALUES
('FREE', 1, 3, 1, 90, 25, 10, 10, 524288000, 2, 5, '["basic_handoffs", "basic_timeline", "basic_tasks", "basic_binder", "emergency_card", "basic_siri", "push_notifications"]'::jsonb),
('PLUS', 2, 8, 2, NULL, NULL, NULL, NULL, 10737418240, NULL, 50, '["basic_handoffs", "basic_timeline", "basic_tasks", "basic_binder", "emergency_card", "basic_siri", "push_notifications", "watch_app", "discharge_wizard", "med_reconciliation", "symptom_patterns", "advanced_siri", "wellness_checkins", "appointment_questions", "family_meetings", "calendar_bidirectional", "priority_support"]'::jsonb),
('FAMILY', 5, 20, 5, NULL, NULL, NULL, NULL, 53687091200, NULL, NULL, '["basic_handoffs", "basic_timeline", "basic_tasks", "basic_binder", "emergency_card", "basic_siri", "push_notifications", "watch_app", "discharge_wizard", "med_reconciliation", "symptom_patterns", "advanced_siri", "wellness_checkins", "appointment_questions", "family_meetings", "calendar_bidirectional", "priority_support", "ai_coach_unlimited", "ai_proactive", "shift_mode", "helper_portal", "delegation_intelligence", "operational_insights", "respite_finder", "legal_vault", "photo_tracking_ai", "shared_calendar", "care_directory", "multi_patient_correlation", "concierge_support"]'::jsonb)
ON CONFLICT (plan) DO UPDATE SET
    max_circles = EXCLUDED.max_circles,
    max_members_per_circle = EXCLUDED.max_members_per_circle,
    max_patients_per_circle = EXCLUDED.max_patients_per_circle,
    handoff_history_days = EXCLUDED.handoff_history_days,
    max_binder_items = EXCLUDED.max_binder_items,
    max_active_tasks = EXCLUDED.max_active_tasks,
    max_audio_handoffs_per_month = EXCLUDED.max_audio_handoffs_per_month,
    max_storage_bytes = EXCLUDED.max_storage_bytes,
    max_exports_per_month = EXCLUDED.max_exports_per_month,
    max_ai_messages_per_month = EXCLUDED.max_ai_messages_per_month,
    features_json = EXCLUDED.features_json,
    updated_at = now();

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to get user's current plan
CREATE OR REPLACE FUNCTION get_user_plan(p_user_id uuid)
RETURNS text AS $$
DECLARE
    v_plan text;
BEGIN
    SELECT plan INTO v_plan
    FROM subscriptions
    WHERE user_id = p_user_id
      AND status IN ('ACTIVE', 'TRIALING', 'GRACE_PERIOD');

    RETURN COALESCE(v_plan, 'FREE');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has feature access
CREATE OR REPLACE FUNCTION has_feature_access(p_user_id uuid, p_feature text)
RETURNS boolean AS $$
DECLARE
    v_plan text;
    v_features jsonb;
BEGIN
    v_plan := get_user_plan(p_user_id);

    SELECT features_json INTO v_features
    FROM plan_limits
    WHERE plan = v_plan;

    RETURN v_features ? p_feature;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check usage limit
CREATE OR REPLACE FUNCTION check_usage_limit(
    p_user_id uuid,
    p_circle_id uuid,
    p_metric_type text
)
RETURNS jsonb AS $$
DECLARE
    v_plan text;
    v_limit int;
    v_current bigint;
    v_period_start date;
BEGIN
    v_plan := get_user_plan(p_user_id);
    v_period_start := date_trunc('month', now())::date;

    -- Get limit for this metric
    SELECT CASE p_metric_type
        WHEN 'AUDIO_HANDOFF' THEN max_audio_handoffs_per_month
        WHEN 'AI_MESSAGE' THEN max_ai_messages_per_month
        WHEN 'EXPORT' THEN max_exports_per_month
        ELSE NULL
    END INTO v_limit
    FROM plan_limits
    WHERE plan = v_plan;

    -- If no limit, allow
    IF v_limit IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'current', 0,
            'limit', NULL,
            'unlimited', true
        );
    END IF;

    -- Get current usage
    SELECT COALESCE(SUM(count), 0) INTO v_current
    FROM usage_metrics
    WHERE user_id = p_user_id
      AND metric_type = p_metric_type
      AND period_start = v_period_start;

    RETURN jsonb_build_object(
        'allowed', v_current < v_limit,
        'current', v_current,
        'limit', v_limit,
        'unlimited', false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment usage
CREATE OR REPLACE FUNCTION increment_usage(
    p_user_id uuid,
    p_circle_id uuid,
    p_metric_type text,
    p_amount int DEFAULT 1
)
RETURNS void AS $$
DECLARE
    v_period_start date;
    v_period_end date;
BEGIN
    v_period_start := date_trunc('month', now())::date;
    v_period_end := (date_trunc('month', now()) + interval '1 month' - interval '1 day')::date;

    INSERT INTO usage_metrics (user_id, circle_id, metric_type, period_start, period_end, count)
    VALUES (p_user_id, p_circle_id, p_metric_type, v_period_start, v_period_end, p_amount)
    ON CONFLICT (user_id, circle_id, metric_type, period_start)
    DO UPDATE SET
        count = usage_metrics.count + p_amount,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_limits ENABLE ROW LEVEL SECURITY;

-- Subscriptions: users can read their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own subscription') THEN
        CREATE POLICY "Users read own subscription" ON subscriptions
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- Usage metrics: users can read their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own usage') THEN
        CREATE POLICY "Users read own usage" ON usage_metrics
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- Subscription events: users can read their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own subscription events') THEN
        CREATE POLICY "Users read own subscription events" ON subscription_events
            FOR SELECT USING (
                subscription_id IN (
                    SELECT id FROM subscriptions WHERE user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- Plan limits: everyone can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can read plan limits') THEN
        CREATE POLICY "Anyone can read plan limits" ON plan_limits
            FOR SELECT USING (true);
    END IF;
END $$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-create subscription for new users
CREATE OR REPLACE FUNCTION create_default_subscription()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO subscriptions (user_id, plan, status, provider)
    VALUES (NEW.id, 'FREE', 'ACTIVE', 'NONE')
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: Trigger should be created on auth.users but requires special permissions
-- This would typically be done via Supabase dashboard or a separate privileged migration
