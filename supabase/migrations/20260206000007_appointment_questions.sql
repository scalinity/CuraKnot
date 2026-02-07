-- Migration: 0007_appointment_questions
-- Description: Smart Appointment Question Generator - AI-powered personalized questions
-- Date: 2026-02-06
-- Feature: Extends visit_questions with AI generation, priority scoring, and post-appointment workflow

-- ============================================================================
-- TABLE: appointment_questions
-- Enhanced question management with AI generation support
-- ============================================================================

CREATE TABLE IF NOT EXISTS appointment_questions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    appointment_pack_id uuid REFERENCES appointment_packs(id) ON DELETE SET NULL,

    -- Question content
    question_text text NOT NULL CHECK (char_length(question_text) >= 10 AND char_length(question_text) <= 500),
    reasoning text CHECK (char_length(reasoning) <= 300),
    category text NOT NULL CHECK (category IN ('SYMPTOM', 'MEDICATION', 'TEST', 'CARE_PLAN', 'PROGNOSIS', 'SIDE_EFFECT', 'GENERAL')),

    -- Source tracking for AI transparency
    source text NOT NULL CHECK (source IN ('AI_GENERATED', 'USER_ADDED', 'TEMPLATE')),
    source_handoff_ids uuid[] DEFAULT '{}',
    source_medication_ids uuid[] DEFAULT '{}',
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Priority scoring
    priority text NOT NULL DEFAULT 'MEDIUM' CHECK (priority IN ('HIGH', 'MEDIUM', 'LOW')),
    priority_score int NOT NULL DEFAULT 0 CHECK (priority_score >= 0 AND priority_score <= 10),

    -- Status tracking
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'DISCUSSED', 'NOT_DISCUSSED', 'DEFERRED')),
    sort_order int NOT NULL DEFAULT 0,

    -- Post-appointment workflow
    response_notes text CHECK (char_length(response_notes) <= 2000),
    discussed_at timestamptz,
    discussed_by uuid REFERENCES users(id) ON DELETE SET NULL,
    follow_up_task_id uuid REFERENCES tasks(id) ON DELETE SET NULL,

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_appointment_questions_pack
    ON appointment_questions(appointment_pack_id)
    WHERE appointment_pack_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_appointment_questions_patient
    ON appointment_questions(patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_appointment_questions_circle
    ON appointment_questions(circle_id);

CREATE INDEX IF NOT EXISTS idx_appointment_questions_pending
    ON appointment_questions(patient_id, status)
    WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_appointment_questions_priority
    ON appointment_questions(patient_id, priority_score DESC);

-- Composite indexes for optimized query patterns (CA3 performance review)
-- Index for listing pending questions with priority ordering
CREATE INDEX IF NOT EXISTS idx_appointment_questions_patient_pending_sorted
    ON appointment_questions(patient_id, status, priority_score DESC, sort_order)
    WHERE status = 'PENDING';

-- Index for appointment pack queries with priority ordering
CREATE INDEX IF NOT EXISTS idx_appointment_questions_pack_sorted
    ON appointment_questions(appointment_pack_id, priority_score DESC, sort_order)
    WHERE appointment_pack_id IS NOT NULL;

-- Index for circle-wide patient status queries (admin views)
CREATE INDEX IF NOT EXISTS idx_appointment_questions_circle_patient_status
    ON appointment_questions(circle_id, patient_id, status);

-- Index for post-appointment review queries (recently discussed)
CREATE INDEX IF NOT EXISTS idx_appointment_questions_discussed
    ON appointment_questions(patient_id, discussed_at DESC)
    WHERE discussed_at IS NOT NULL;

-- Auto-update timestamp trigger
CREATE TRIGGER appointment_questions_updated_at
    BEFORE UPDATE ON appointment_questions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE appointment_questions IS 'AI-generated and user-added questions for medical appointments with priority scoring and post-visit tracking';

-- ============================================================================
-- TABLE: question_templates
-- Reusable templates for question generation fallback
-- ============================================================================

CREATE TABLE IF NOT EXISTS question_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category text NOT NULL CHECK (category IN ('SYMPTOM', 'MEDICATION', 'TEST', 'CARE_PLAN', 'PROGNOSIS', 'SIDE_EFFECT', 'GENERAL')),
    trigger_type text NOT NULL CHECK (trigger_type IN (
        'SYMPTOM_REPEATED', 'MED_NEW', 'MED_CHANGED', 'MED_SIDE_EFFECT',
        'TEST_PENDING', 'REFERRAL_PENDING', 'CONDITION_NEW', 'BASELINE'
    )),
    template_text text NOT NULL,
    template_variables text[] DEFAULT '{}',
    priority_default text NOT NULL DEFAULT 'MEDIUM' CHECK (priority_default IN ('HIGH', 'MEDIUM', 'LOW')),
    is_active boolean NOT NULL DEFAULT true,
    min_confidence_score numeric(3,2) DEFAULT 0.5 CHECK (min_confidence_score >= 0 AND min_confidence_score <= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_question_templates_active
    ON question_templates(trigger_type)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_question_templates_category
    ON question_templates(category);

CREATE TRIGGER question_templates_updated_at
    BEFORE UPDATE ON question_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE question_templates IS 'Reusable question templates for fallback and baseline questions';

-- ============================================================================
-- SEED DATA: question_templates
-- ============================================================================

INSERT INTO question_templates (category, trigger_type, template_text, template_variables, priority_default, min_confidence_score) VALUES
-- Symptom-related (HIGH priority)
('SYMPTOM', 'SYMPTOM_REPEATED', 'You mentioned {symptom} {count} times in the last {days} days. Could this be related to medications or a new condition?', ARRAY['symptom', 'count', 'days'], 'HIGH', 0.7),
('SYMPTOM', 'SYMPTOM_REPEATED', 'The recurring {symptom} seems to be getting worse. Should we investigate further?', ARRAY['symptom'], 'HIGH', 0.8),

-- Medication-related (MEDIUM-HIGH priority)
('MEDICATION', 'MED_NEW', '{medication} was started {duration} ago. Is it working as expected? Any side effects to watch for?', ARRAY['medication', 'duration'], 'MEDIUM', 0.8),
('MEDICATION', 'MED_CHANGED', 'The dose of {medication} was changed {duration} ago. How is the new dose working?', ARRAY['medication', 'duration'], 'MEDIUM', 0.8),
('SIDE_EFFECT', 'MED_SIDE_EFFECT', 'Could {symptom} be a side effect of {medication}?', ARRAY['symptom', 'medication'], 'HIGH', 0.6),
('MEDICATION', 'MED_NEW', 'What are the most important side effects of {medication} that we should watch for?', ARRAY['medication'], 'MEDIUM', 0.7),

-- Test-related (MEDIUM priority)
('TEST', 'TEST_PENDING', 'What were the results of the recent {test_type}?', ARRAY['test_type'], 'MEDIUM', 0.5),
('TEST', 'TEST_PENDING', 'Do we need any follow-up tests based on the {test_type} results?', ARRAY['test_type'], 'MEDIUM', 0.6),

-- Care plan-related (MEDIUM priority)
('CARE_PLAN', 'REFERRAL_PENDING', 'Can we move forward with the {referral_type} referral?', ARRAY['referral_type'], 'MEDIUM', 0.5),
('CARE_PLAN', 'CONDITION_NEW', 'What should we know about managing {condition}?', ARRAY['condition'], 'HIGH', 0.7),
('PROGNOSIS', 'CONDITION_NEW', 'What is the typical progression for {condition}?', ARRAY['condition'], 'MEDIUM', 0.6),

-- Baseline questions (LOW priority, always available)
('GENERAL', 'BASELINE', 'Are all current medications still necessary?', ARRAY[]::text[], 'LOW', 0.3),
('GENERAL', 'BASELINE', 'What are the warning signs to watch for before the next visit?', ARRAY[]::text[], 'MEDIUM', 0.3),
('GENERAL', 'BASELINE', 'What should we do if symptoms worsen?', ARRAY[]::text[], 'MEDIUM', 0.3),
('GENERAL', 'BASELINE', 'Is there anything we should be doing differently at home?', ARRAY[]::text[], 'LOW', 0.3),
('GENERAL', 'BASELINE', 'When should we schedule the next appointment?', ARRAY[]::text[], 'LOW', 0.3)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE appointment_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE question_templates ENABLE ROW LEVEL SECURITY;

-- Circle members can read questions
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'appointment_questions_select' AND tablename = 'appointment_questions') THEN
        CREATE POLICY appointment_questions_select ON appointment_questions
            FOR SELECT USING (is_circle_member(circle_id, auth.uid()));
    END IF;
END $$;

-- Contributors+ can create questions
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'appointment_questions_insert' AND tablename = 'appointment_questions') THEN
        CREATE POLICY appointment_questions_insert ON appointment_questions
            FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));
    END IF;
END $$;

-- Creator or Admin+ can update questions
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'appointment_questions_update' AND tablename = 'appointment_questions') THEN
        CREATE POLICY appointment_questions_update ON appointment_questions
            FOR UPDATE USING (
                created_by = auth.uid() OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
            );
    END IF;
END $$;

-- Admin+ can delete questions
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'appointment_questions_delete' AND tablename = 'appointment_questions') THEN
        CREATE POLICY appointment_questions_delete ON appointment_questions
            FOR DELETE USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));
    END IF;
END $$;

-- Everyone can read active templates (system data)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'question_templates_select' AND tablename = 'question_templates') THEN
        CREATE POLICY question_templates_select ON question_templates
            FOR SELECT USING (is_active = true);
    END IF;
END $$;

-- ============================================================================
-- Add appointment_questions to plan_limits for premium gating
-- ============================================================================

-- Note: appointment_questions feature is already included in the PLUS and FAMILY 
-- plans in the plan_limits seed data (see 20260205000001_subscriptions.sql).
-- The feature flag 'appointment_questions' is checked via has_feature_access().

COMMENT ON TABLE appointment_questions IS 'AI-generated and user-added questions for medical appointments. Premium feature (PLUS/FAMILY tiers).';
