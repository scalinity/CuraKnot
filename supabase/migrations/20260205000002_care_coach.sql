-- ============================================================================
-- Migration: AI Care Coach
-- Description: Tables for AI Care Coach conversational guidance feature
-- ============================================================================

-- ============================================================================
-- TABLE: coach_conversations
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,

    title text,  -- Auto-generated from first message
    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | ARCHIVED

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Index for user's conversations
CREATE INDEX IF NOT EXISTS idx_coach_conversations_user
    ON coach_conversations(user_id, updated_at DESC);

-- Index for circle's conversations
CREATE INDEX IF NOT EXISTS idx_coach_conversations_circle
    ON coach_conversations(circle_id, updated_at DESC);

-- ============================================================================
-- TABLE: coach_messages
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES coach_conversations(id) ON DELETE CASCADE,

    role text NOT NULL,  -- USER | ASSISTANT
    content text NOT NULL,

    -- Context used for this message
    context_handoff_ids uuid[],
    context_binder_ids uuid[],
    context_snapshot_json jsonb,  -- Snapshot of context used

    -- Suggested actions in response
    actions_json jsonb,

    -- User feedback
    is_bookmarked boolean NOT NULL DEFAULT false,
    feedback text,  -- HELPFUL | NOT_HELPFUL | NULL

    -- Metadata
    tokens_used int,
    latency_ms int,
    model_version text,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coach_messages_conversation
    ON coach_messages(conversation_id, created_at);

CREATE INDEX IF NOT EXISTS idx_coach_messages_bookmarked
    ON coach_messages(conversation_id)
    WHERE is_bookmarked = true;

-- ============================================================================
-- TABLE: coach_suggestions (Proactive suggestions)
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_suggestions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    suggestion_type text NOT NULL,  -- TREND_ALERT | APPOINTMENT_PREP | WELLNESS_CHECK | FOLLOWUP
    title text NOT NULL,
    content text NOT NULL,
    context_json jsonb,  -- Context that triggered suggestion

    status text NOT NULL DEFAULT 'PENDING',  -- PENDING | VIEWED | DISMISSED | ACTIONED
    actioned_at timestamptz,
    dismissed_at timestamptz,
    expires_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coach_suggestions_user
    ON coach_suggestions(user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_coach_suggestions_patient
    ON coach_suggestions(patient_id, status, created_at DESC)
    WHERE patient_id IS NOT NULL;

-- ============================================================================
-- TABLE: coach_usage (Usage tracking for rate limiting)
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_usage (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    month date NOT NULL,  -- First of month

    messages_used int NOT NULL DEFAULT 0,
    messages_limit int NOT NULL DEFAULT 50,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(user_id, month)
);

CREATE INDEX IF NOT EXISTS idx_coach_usage_lookup
    ON coach_usage(user_id, month);

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to check coach usage limit and remaining messages
CREATE OR REPLACE FUNCTION check_coach_usage(p_user_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_plan text;
    v_limit int;
    v_used int;
    v_month date;
BEGIN
    v_plan := get_user_plan(p_user_id);
    v_month := date_trunc('month', now())::date;

    -- Determine limit based on plan
    -- FREE: No access
    -- PLUS: 50 messages/month
    -- FAMILY: Unlimited
    CASE v_plan
        WHEN 'FREE' THEN v_limit := 0;
        WHEN 'PLUS' THEN v_limit := 50;
        WHEN 'FAMILY' THEN v_limit := NULL;  -- NULL = unlimited
        ELSE v_limit := 0;
    END CASE;

    -- Get current usage
    SELECT COALESCE(messages_used, 0) INTO v_used
    FROM coach_usage
    WHERE user_id = p_user_id AND month = v_month;

    IF v_used IS NULL THEN
        v_used := 0;
    END IF;

    RETURN jsonb_build_object(
        'plan', v_plan,
        'allowed', CASE
            WHEN v_limit IS NULL THEN true
            WHEN v_limit = 0 THEN false
            ELSE v_used < v_limit
        END,
        'used', v_used,
        'limit', v_limit,
        'unlimited', v_limit IS NULL,
        'remaining', CASE
            WHEN v_limit IS NULL THEN NULL
            ELSE GREATEST(v_limit - v_used, 0)
        END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment coach usage
CREATE OR REPLACE FUNCTION increment_coach_usage(p_user_id uuid)
RETURNS void AS $$
DECLARE
    v_month date;
    v_limit int;
    v_plan text;
BEGIN
    v_month := date_trunc('month', now())::date;
    v_plan := get_user_plan(p_user_id);

    -- Get limit for plan
    CASE v_plan
        WHEN 'FREE' THEN v_limit := 0;
        WHEN 'PLUS' THEN v_limit := 50;
        WHEN 'FAMILY' THEN v_limit := 999999;  -- Effectively unlimited
        ELSE v_limit := 0;
    END CASE;

    INSERT INTO coach_usage (user_id, month, messages_used, messages_limit)
    VALUES (p_user_id, v_month, 1, v_limit)
    ON CONFLICT (user_id, month)
    DO UPDATE SET
        messages_used = coach_usage.messages_used + 1,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to decrement coach usage (for rollback on failures)
CREATE OR REPLACE FUNCTION decrement_coach_usage(p_user_id uuid)
RETURNS void AS $$
DECLARE
    v_month date;
BEGIN
    v_month := date_trunc('month', now())::date;

    UPDATE coach_usage
    SET
        messages_used = GREATEST(messages_used - 1, 0),
        updated_at = now()
    WHERE user_id = p_user_id AND month = v_month;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has coach access
CREATE OR REPLACE FUNCTION has_coach_access(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
    v_plan text;
BEGIN
    v_plan := get_user_plan(p_user_id);
    RETURN v_plan IN ('PLUS', 'FAMILY');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has proactive suggestions access
CREATE OR REPLACE FUNCTION has_proactive_coach_access(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
    v_plan text;
BEGIN
    v_plan := get_user_plan(p_user_id);
    RETURN v_plan = 'FAMILY';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE coach_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_usage ENABLE ROW LEVEL SECURITY;

-- coach_conversations: Users can access their own conversations
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users access own coach conversations') THEN
        CREATE POLICY "Users access own coach conversations" ON coach_conversations
            FOR ALL USING (user_id = auth.uid());
    END IF;
END $$;

-- coach_messages: Access through conversation ownership
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users access own coach messages') THEN
        CREATE POLICY "Users access own coach messages" ON coach_messages
            FOR ALL USING (
                conversation_id IN (
                    SELECT id FROM coach_conversations WHERE user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- coach_suggestions: Users can access their own suggestions
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users access own coach suggestions') THEN
        CREATE POLICY "Users access own coach suggestions" ON coach_suggestions
            FOR ALL USING (user_id = auth.uid());
    END IF;
END $$;

-- coach_usage: Users can read their own usage
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own coach usage') THEN
        CREATE POLICY "Users read own coach usage" ON coach_usage
            FOR SELECT USING (user_id = auth.uid());
    END IF;
END $$;

-- Block direct writes to coach_usage (must go through functions)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Block direct writes to coach usage') THEN
        CREATE POLICY "Block direct writes to coach usage" ON coach_usage
            FOR INSERT WITH CHECK (false);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Block direct updates to coach usage') THEN
        CREATE POLICY "Block direct updates to coach usage" ON coach_usage
            FOR UPDATE USING (false);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Block direct deletes from coach usage') THEN
        CREATE POLICY "Block direct deletes from coach usage" ON coach_usage
            FOR DELETE USING (false);
    END IF;
END $$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update conversation's updated_at when messages are added
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE coach_conversations
    SET updated_at = now()
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS coach_message_update_conversation ON coach_messages;
CREATE TRIGGER coach_message_update_conversation
    AFTER INSERT ON coach_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_timestamp();

-- ============================================================================
-- Update plan_limits to include coach features
-- ============================================================================

UPDATE plan_limits
SET features_json = features_json || '["ai_coach_basic"]'::jsonb
WHERE plan = 'PLUS' AND NOT (features_json ? 'ai_coach_basic');

UPDATE plan_limits
SET features_json = features_json || '["ai_coach_basic", "ai_coach_unlimited", "ai_proactive"]'::jsonb
WHERE plan = 'FAMILY' AND NOT (features_json ? 'ai_coach_unlimited');
