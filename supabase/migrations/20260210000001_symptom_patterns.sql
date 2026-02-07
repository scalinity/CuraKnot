-- ============================================================================
-- Migration: Symptom Pattern Surfacing
-- Description: Non-clinical pattern detection from handoff analysis
-- Date: 2026-02-10
-- Feature: Automatically surface recurring symptom patterns from handoffs
-- ============================================================================

-- ============================================================================
-- TABLE: detected_patterns
-- Main table for storing detected symptom patterns
-- ============================================================================

CREATE TABLE IF NOT EXISTS detected_patterns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,

    -- Pattern identification
    concern_category text NOT NULL CHECK (concern_category IN (
        'TIREDNESS', 'APPETITE', 'SLEEP', 'PAIN', 'MOOD',
        'MOBILITY', 'COGNITION', 'DIGESTION', 'BREATHING', 'SKIN'
    )),
    concern_keywords text[] NOT NULL DEFAULT '{}',
    pattern_type text NOT NULL CHECK (pattern_type IN (
        'FREQUENCY', 'TREND', 'CORRELATION', 'NEW', 'ABSENCE'
    )),
    pattern_hash text NOT NULL, -- SHA-256 for deduplication

    -- Metrics
    mention_count int NOT NULL DEFAULT 0,
    first_mention_at timestamptz NOT NULL,
    last_mention_at timestamptz NOT NULL,
    trend text CHECK (trend IN ('INCREASING', 'DECREASING', 'STABLE')),

    -- Correlation with events (meds, facilities)
    correlated_events jsonb,

    -- Status management
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISMISSED', 'TRACKING')),
    dismissed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    dismissed_at timestamptz,

    -- Source handoffs
    source_handoff_ids uuid[] NOT NULL DEFAULT '{}',

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Deduplication constraint
    UNIQUE(patient_id, pattern_hash)
);

CREATE INDEX IF NOT EXISTS idx_detected_patterns_patient
    ON detected_patterns(patient_id, status, last_mention_at DESC);

CREATE INDEX IF NOT EXISTS idx_detected_patterns_circle
    ON detected_patterns(circle_id, status);

CREATE INDEX IF NOT EXISTS idx_detected_patterns_hash
    ON detected_patterns(pattern_hash);

CREATE INDEX IF NOT EXISTS idx_detected_patterns_category
    ON detected_patterns(concern_category);

-- Auto-update timestamp trigger
CREATE TRIGGER detected_patterns_updated_at
    BEFORE UPDATE ON detected_patterns
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE detected_patterns IS 'Non-clinical symptom patterns detected from handoff analysis';

-- ============================================================================
-- TABLE: pattern_mentions
-- Individual mention records linking patterns to handoffs
-- ============================================================================

CREATE TABLE IF NOT EXISTS pattern_mentions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id uuid NOT NULL REFERENCES detected_patterns(id) ON DELETE CASCADE,
    handoff_id uuid NOT NULL REFERENCES handoffs(id) ON DELETE CASCADE,

    -- Extracted content
    matched_text text NOT NULL, -- Original phrase from handoff
    normalized_term text NOT NULL, -- LLM-normalized observational term
    mentioned_at timestamptz NOT NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(pattern_id, handoff_id)
);

CREATE INDEX IF NOT EXISTS idx_pattern_mentions_pattern
    ON pattern_mentions(pattern_id, mentioned_at DESC);

CREATE INDEX IF NOT EXISTS idx_pattern_mentions_handoff
    ON pattern_mentions(handoff_id);

COMMENT ON TABLE pattern_mentions IS 'Individual symptom mentions linked to detected patterns';

-- ============================================================================
-- TABLE: tracked_concerns
-- Manual tracking of specific concerns
-- ============================================================================

CREATE TABLE IF NOT EXISTS tracked_concerns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    pattern_id uuid REFERENCES detected_patterns(id) ON DELETE SET NULL,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,

    -- Concern details
    concern_name text NOT NULL,
    concern_category text CHECK (concern_category IN (
        'TIREDNESS', 'APPETITE', 'SLEEP', 'PAIN', 'MOOD',
        'MOBILITY', 'COGNITION', 'DIGESTION', 'BREATHING', 'SKIN'
    )),
    tracking_prompt text, -- "How was tiredness today?"

    -- Status
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PAUSED', 'RESOLVED')),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tracked_concerns_patient
    ON tracked_concerns(patient_id, status);

CREATE INDEX IF NOT EXISTS idx_tracked_concerns_pattern
    ON tracked_concerns(pattern_id)
    WHERE pattern_id IS NOT NULL;

CREATE TRIGGER tracked_concerns_updated_at
    BEFORE UPDATE ON tracked_concerns
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE tracked_concerns IS 'User-initiated manual tracking of specific concerns';

-- ============================================================================
-- TABLE: tracking_entries
-- Daily tracking check-ins
-- ============================================================================

CREATE TABLE IF NOT EXISTS tracking_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    concern_id uuid NOT NULL REFERENCES tracked_concerns(id) ON DELETE CASCADE,
    recorded_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,

    -- Entry data
    rating int CHECK (rating >= 1 AND rating <= 5), -- 1=much better, 5=much worse
    notes text,
    handoff_id uuid REFERENCES handoffs(id) ON DELETE SET NULL,

    recorded_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tracking_entries_concern
    ON tracking_entries(concern_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_tracking_entries_user
    ON tracking_entries(recorded_by, recorded_at DESC);

COMMENT ON TABLE tracking_entries IS 'Daily tracking entries for monitored concerns';

-- ============================================================================
-- TABLE: pattern_feedback
-- User feedback on pattern quality for ML improvement
-- ============================================================================

CREATE TABLE IF NOT EXISTS pattern_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id uuid NOT NULL REFERENCES detected_patterns(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    feedback_type text NOT NULL CHECK (feedback_type IN ('HELPFUL', 'NOT_HELPFUL', 'FALSE_POSITIVE')),
    feedback_text text,

    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(pattern_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_pattern_feedback_pattern
    ON pattern_feedback(pattern_id);

COMMENT ON TABLE pattern_feedback IS 'User feedback on pattern detection accuracy';

-- ============================================================================
-- Add source_pattern_id to appointment_questions for integration
-- ============================================================================

ALTER TABLE appointment_questions
    ADD COLUMN IF NOT EXISTS source_pattern_id uuid REFERENCES detected_patterns(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_appointment_questions_pattern
    ON appointment_questions(source_pattern_id)
    WHERE source_pattern_id IS NOT NULL;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE detected_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE pattern_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracked_concerns ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE pattern_feedback ENABLE ROW LEVEL SECURITY;

-- detected_patterns: Circle members can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members read patterns' AND tablename = 'detected_patterns') THEN
        CREATE POLICY "Circle members read patterns" ON detected_patterns
            FOR SELECT USING (is_circle_member(circle_id, auth.uid()));
    END IF;
END $$;

-- detected_patterns: Contributors can update (dismiss/track)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors update patterns' AND tablename = 'detected_patterns') THEN
        CREATE POLICY "Contributors update patterns" ON detected_patterns
            FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
    END IF;
END $$;

-- pattern_mentions: Circle members can read (through pattern)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members read mentions' AND tablename = 'pattern_mentions') THEN
        CREATE POLICY "Circle members read mentions" ON pattern_mentions
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM detected_patterns dp
                    WHERE dp.id = pattern_mentions.pattern_id
                      AND is_circle_member(dp.circle_id, auth.uid())
                )
            );
    END IF;
END $$;

-- tracked_concerns: Circle members can read
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members read tracked concerns' AND tablename = 'tracked_concerns') THEN
        CREATE POLICY "Circle members read tracked concerns" ON tracked_concerns
            FOR SELECT USING (is_circle_member(circle_id, auth.uid()));
    END IF;
END $$;

-- tracked_concerns: Contributors can create
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create tracked concerns' AND tablename = 'tracked_concerns') THEN
        CREATE POLICY "Contributors create tracked concerns" ON tracked_concerns
            FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
    END IF;
END $$;

-- tracked_concerns: Contributors can update
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors update tracked concerns' AND tablename = 'tracked_concerns') THEN
        CREATE POLICY "Contributors update tracked concerns" ON tracked_concerns
            FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
    END IF;
END $$;

-- tracking_entries: Circle members can read (through concern)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle members read tracking entries' AND tablename = 'tracking_entries') THEN
        CREATE POLICY "Circle members read tracking entries" ON tracking_entries
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM tracked_concerns tc
                    WHERE tc.id = tracking_entries.concern_id
                      AND is_circle_member(tc.circle_id, auth.uid())
                )
            );
    END IF;
END $$;

-- tracking_entries: Contributors can create
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Contributors create tracking entries' AND tablename = 'tracking_entries') THEN
        CREATE POLICY "Contributors create tracking entries" ON tracking_entries
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM tracked_concerns tc
                    WHERE tc.id = tracking_entries.concern_id
                      AND has_circle_role(tc.circle_id, auth.uid(), 'CONTRIBUTOR')
                )
            );
    END IF;
END $$;

-- pattern_feedback: Users can create their own feedback
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users create own feedback' AND tablename = 'pattern_feedback') THEN
        CREATE POLICY "Users create own feedback" ON pattern_feedback
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- pattern_feedback: Users can read their own feedback
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own feedback' AND tablename = 'pattern_feedback') THEN
        CREATE POLICY "Users read own feedback" ON pattern_feedback
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- TRIGGER: Recompute pattern stats on handoff deletion
-- ============================================================================

CREATE OR REPLACE FUNCTION recompute_pattern_on_mention_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Update pattern stats after mention deletion
    UPDATE detected_patterns
    SET
        mention_count = (
            SELECT COUNT(*) FROM pattern_mentions
            WHERE pattern_id = OLD.pattern_id
        ),
        source_handoff_ids = (
            SELECT COALESCE(array_agg(handoff_id), '{}')
            FROM pattern_mentions
            WHERE pattern_id = OLD.pattern_id
        ),
        updated_at = now()
    WHERE id = OLD.pattern_id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_recompute_pattern_on_mention_delete
    AFTER DELETE ON pattern_mentions
    FOR EACH ROW
    EXECUTE FUNCTION recompute_pattern_on_mention_delete();

-- Also delete mentions when handoff is deleted (cascade handled by FK, but update pattern)
CREATE OR REPLACE FUNCTION cascade_handoff_deletion_to_patterns()
RETURNS TRIGGER AS $$
BEGIN
    -- pattern_mentions FK will cascade delete, but we need to update pattern stats
    -- This is handled by trigger_recompute_pattern_on_mention_delete
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: Generate pattern summary text (non-clinical language)
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_pattern_summary(
    p_concern_category text,
    p_pattern_type text,
    p_mention_count int,
    p_trend text,
    p_first_mention timestamptz,
    p_correlated_events jsonb
)
RETURNS text AS $$
DECLARE
    v_summary text;
    v_days_span int;
    v_event_desc text;
BEGIN
    v_days_span := EXTRACT(DAY FROM (now() - p_first_mention))::int;

    CASE p_pattern_type
        WHEN 'FREQUENCY' THEN
            v_summary := format(
                'You mentioned %s-related observations %s times in the last %s days',
                lower(p_concern_category),
                p_mention_count,
                v_days_span
            );
        WHEN 'TREND' THEN
            v_summary := format(
                '%s observations have been %s over the last %s days',
                initcap(p_concern_category),
                lower(p_trend),
                v_days_span
            );
        WHEN 'CORRELATION' THEN
            v_event_desc := p_correlated_events->0->>'eventDescription';
            v_summary := format(
                '%s observations started around when %s',
                initcap(p_concern_category),
                COALESCE(v_event_desc, 'a recent change occurred')
            );
        WHEN 'NEW' THEN
            v_summary := format(
                '%s was first noted %s days ago',
                initcap(p_concern_category),
                v_days_span
            );
        WHEN 'ABSENCE' THEN
            v_summary := format(
                '%s has not been mentioned recently (was noted frequently before)',
                initcap(p_concern_category)
            );
        ELSE
            v_summary := format(
                'Pattern detected for %s',
                lower(p_concern_category)
            );
    END CASE;

    RETURN v_summary;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION generate_pattern_summary IS 'Generates non-clinical summary text for detected patterns';
