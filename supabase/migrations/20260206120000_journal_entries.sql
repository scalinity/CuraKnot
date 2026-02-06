-- ============================================================================
-- Migration: Gratitude & Milestone Journal
-- Description: Journal entries for capturing positive moments and milestones
-- ============================================================================

-- ============================================================================
-- TABLE: journal_entries
-- ============================================================================

CREATE TABLE IF NOT EXISTS journal_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Entry content
    entry_type text NOT NULL CHECK (entry_type IN ('GOOD_MOMENT', 'MILESTONE')),
    title text CHECK (char_length(title) <= 200),
    content text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 2000),
    milestone_type text CHECK (milestone_type IN ('ANNIVERSARY', 'PROGRESS', 'FIRST', 'ACHIEVEMENT', 'MEMORY')),

    -- Photos (stored in Supabase Storage: journal/{circle_id}/{entry_id}/)
    photo_storage_keys text[] DEFAULT ARRAY[]::text[],

    -- Privacy
    visibility text NOT NULL DEFAULT 'CIRCLE' CHECK (visibility IN ('PRIVATE', 'CIRCLE')),

    -- Entry date (can be backdated for remembering past moments)
    entry_date date NOT NULL DEFAULT CURRENT_DATE,

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Constraints
    CONSTRAINT milestone_requires_title CHECK (
        entry_type != 'MILESTONE' OR title IS NOT NULL
    ),
    CONSTRAINT milestone_requires_type CHECK (
        entry_type != 'MILESTONE' OR milestone_type IS NOT NULL
    ),
    CONSTRAINT good_moment_no_milestone_type CHECK (
        entry_type != 'GOOD_MOMENT' OR milestone_type IS NULL
    ),
    CONSTRAINT max_photos CHECK (
        array_length(photo_storage_keys, 1) IS NULL OR array_length(photo_storage_keys, 1) <= 3
    )
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_journal_entries_circle_date
    ON journal_entries(circle_id, entry_date DESC);

CREATE INDEX IF NOT EXISTS idx_journal_entries_patient_date
    ON journal_entries(patient_id, entry_date DESC);

CREATE INDEX IF NOT EXISTS idx_journal_entries_author
    ON journal_entries(created_by, entry_date DESC);

CREATE INDEX IF NOT EXISTS idx_journal_entries_visibility
    ON journal_entries(circle_id, visibility, entry_date DESC);

CREATE INDEX IF NOT EXISTS idx_journal_entries_type
    ON journal_entries(circle_id, entry_type, entry_date DESC);

-- ============================================================================
-- TABLE: journal_prompts (System prompts for gentle encouragement)
-- ============================================================================

CREATE TABLE IF NOT EXISTS journal_prompts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_text text NOT NULL,
    prompt_type text NOT NULL CHECK (prompt_type IN ('GOOD_MOMENT', 'MILESTONE')),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_journal_prompts_active
    ON journal_prompts(is_active, prompt_type);

-- Seed prompts (gentle, never guilt-inducing)
INSERT INTO journal_prompts (prompt_text, prompt_type) VALUES
    ('What made you smile this week?', 'GOOD_MOMENT'),
    ('What small victory happened recently?', 'GOOD_MOMENT'),
    ('What are you grateful for in your caregiving journey?', 'GOOD_MOMENT'),
    ('Has anything improved recently?', 'GOOD_MOMENT'),
    ('Any special moments worth remembering?', 'GOOD_MOMENT'),
    ('Did something unexpected brighten your day?', 'GOOD_MOMENT'),
    ('What kindness did you witness today?', 'GOOD_MOMENT'),
    ('Is there a recent achievement to celebrate?', 'MILESTONE'),
    ('Has there been a "first" moment worth marking?', 'MILESTONE'),
    ('Any progress milestones to remember?', 'MILESTONE')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- Update plan_limits for journal features
-- ============================================================================

-- Add max_journal_entries_per_month column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'plan_limits' AND column_name = 'max_journal_entries_per_month'
    ) THEN
        ALTER TABLE plan_limits ADD COLUMN max_journal_entries_per_month int;
    END IF;
END $$;

-- Update limits: FREE = 5/month, PLUS/FAMILY = unlimited (NULL)
UPDATE plan_limits SET max_journal_entries_per_month = 5 WHERE plan = 'FREE';
UPDATE plan_limits SET max_journal_entries_per_month = NULL WHERE plan IN ('PLUS', 'FAMILY');

-- Add journal_photos feature to PLUS and FAMILY
UPDATE plan_limits
SET features_json = features_json || '["journal_photos"]'::jsonb
WHERE plan IN ('PLUS', 'FAMILY')
  AND NOT (features_json ? 'journal_photos');

-- Add memory_book_export feature to FAMILY only
UPDATE plan_limits
SET features_json = features_json || '["memory_book_export"]'::jsonb
WHERE plan = 'FAMILY'
  AND NOT (features_json ? 'memory_book_export');

-- ============================================================================
-- Function to check journal usage
-- ============================================================================

CREATE OR REPLACE FUNCTION check_journal_usage(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_count int;
    v_limit int;
    v_plan text;
BEGIN
    -- Get user's current plan
    v_plan := get_user_plan(p_user_id);

    -- Get limit for journal entries
    SELECT max_journal_entries_per_month INTO v_limit
    FROM plan_limits
    WHERE plan = v_plan;

    -- If no limit (NULL), user has unlimited
    IF v_limit IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'current', 0,
            'limit', NULL,
            'unlimited', true,
            'plan', v_plan
        );
    END IF;

    -- Count entries this calendar month (UTC)
    SELECT COUNT(*)
    INTO v_current_count
    FROM journal_entries
    WHERE created_by = p_user_id
      AND created_at >= date_trunc('month', now() AT TIME ZONE 'UTC');

    RETURN jsonb_build_object(
        'allowed', v_current_count < v_limit,
        'current', v_current_count,
        'limit', v_limit,
        'unlimited', false,
        'plan', v_plan
    );
END;
$$;

-- ============================================================================
-- Function to increment journal usage (for compatibility with usage_metrics)
-- ============================================================================

CREATE OR REPLACE FUNCTION increment_journal_usage(
    p_user_id uuid,
    p_circle_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_period_start date;
    v_period_end date;
BEGIN
    v_period_start := date_trunc('month', now() AT TIME ZONE 'UTC')::date;
    v_period_end := (date_trunc('month', now() AT TIME ZONE 'UTC') + interval '1 month' - interval '1 day')::date;

    INSERT INTO usage_metrics (user_id, circle_id, metric_type, period_start, period_end, count)
    VALUES (p_user_id, p_circle_id, 'JOURNAL_ENTRY', v_period_start, v_period_end, 1)
    ON CONFLICT (user_id, circle_id, metric_type, period_start)
    DO UPDATE SET
        count = usage_metrics.count + 1,
        updated_at = now();
END;
$$;

-- ============================================================================
-- RLS Policies
-- ============================================================================

ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_prompts ENABLE ROW LEVEL SECURITY;

-- Authors can read all their own entries (including PRIVATE)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authors read own journal entries') THEN
        CREATE POLICY "Authors read own journal entries" ON journal_entries
            FOR SELECT USING (created_by = auth.uid());
    END IF;
END $$;

-- Circle members can read CIRCLE-visibility entries from their circles
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members read circle journal entries') THEN
        CREATE POLICY "Members read circle journal entries" ON journal_entries
            FOR SELECT USING (
                visibility = 'CIRCLE' AND
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = journal_entries.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- Contributors and above can create entries (not VIEWER)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create journal entries') THEN
        CREATE POLICY "Contributors create journal entries" ON journal_entries
            FOR INSERT WITH CHECK (
                created_by = auth.uid() AND
                EXISTS (
                    SELECT 1 FROM circle_members
                    WHERE circle_members.circle_id = journal_entries.circle_id
                      AND circle_members.user_id = auth.uid()
                      AND circle_members.role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR')
                      AND circle_members.status = 'ACTIVE'
                )
            );
    END IF;
END $$;

-- Authors can update their own entries
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authors update own journal entries') THEN
        CREATE POLICY "Authors update own journal entries" ON journal_entries
            FOR UPDATE USING (created_by = auth.uid())
            WITH CHECK (created_by = auth.uid());
    END IF;
END $$;

-- Authors can delete their own entries
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authors delete own journal entries') THEN
        CREATE POLICY "Authors delete own journal entries" ON journal_entries
            FOR DELETE USING (created_by = auth.uid());
    END IF;
END $$;

-- Everyone can read active prompts
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone read active journal prompts') THEN
        CREATE POLICY "Anyone read active journal prompts" ON journal_prompts
            FOR SELECT USING (is_active = true);
    END IF;
END $$;

-- ============================================================================
-- Trigger for updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION update_journal_entries_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_journal_entries_updated_at ON journal_entries;
CREATE TRIGGER trg_journal_entries_updated_at
    BEFORE UPDATE ON journal_entries
    FOR EACH ROW
    EXECUTE FUNCTION update_journal_entries_updated_at();
