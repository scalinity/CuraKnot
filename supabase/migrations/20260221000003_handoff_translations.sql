-- ============================================================================
-- Migration: Multi-Language Handoff Translation
-- Description: Translation tables, cache, glossary, and language preferences
-- Date: 2026-02-21
-- ============================================================================

-- 1. Add source_language to handoffs
ALTER TABLE handoffs ADD COLUMN IF NOT EXISTS source_language text DEFAULT 'en';

-- 2. Add source_language to binder_items
ALTER TABLE binder_items ADD COLUMN IF NOT EXISTS source_language text DEFAULT 'en';

-- 3. Add source_language to tasks
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS source_language text DEFAULT 'en';

-- 4. Add language preferences to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS language_preferences_json jsonb DEFAULT '{"preferredLanguage":"en","translationMode":"AUTO","showOriginal":false}'::jsonb;

-- 5. Handoff Translations table (per-handoff cached translations)
CREATE TABLE IF NOT EXISTS handoff_translations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    handoff_id uuid NOT NULL REFERENCES handoffs(id) ON DELETE CASCADE,
    revision_id uuid REFERENCES handoff_revisions(id),

    source_language text NOT NULL,
    target_language text NOT NULL,

    translated_title text,
    translated_summary text,
    translated_content jsonb,

    translation_engine text NOT NULL,
    confidence_score decimal(3,2),

    source_hash text NOT NULL,
    is_stale boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(handoff_id, target_language)
);

-- 6. Translation Cache table (generic text cache)
CREATE TABLE IF NOT EXISTS translation_cache (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    source_text_hash text NOT NULL,
    source_language text NOT NULL,
    target_language text NOT NULL,

    translated_text text NOT NULL,

    confidence_score decimal(3,2),
    contains_medical_terms boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL DEFAULT (now() + interval '30 days'),

    UNIQUE(source_text_hash, source_language, target_language)
);

-- 7. Translation Glossary table (custom medical terms per circle)
CREATE TABLE IF NOT EXISTS translation_glossary (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid REFERENCES circles(id) ON DELETE CASCADE,

    source_language text NOT NULL,
    target_language text NOT NULL,

    source_term text NOT NULL,
    translated_term text NOT NULL,
    context text,
    category text,

    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(circle_id, source_language, target_language, source_term)
);

-- 8. Indexes
CREATE INDEX IF NOT EXISTS idx_translations_lookup
    ON handoff_translations(handoff_id, target_language);
CREATE INDEX IF NOT EXISTS idx_translations_stale
    ON handoff_translations(is_stale) WHERE is_stale = true;
CREATE INDEX IF NOT EXISTS idx_translation_cache_lookup
    ON translation_cache(source_text_hash, source_language, target_language);
CREATE INDEX IF NOT EXISTS idx_translation_cache_expires
    ON translation_cache(expires_at);
CREATE INDEX IF NOT EXISTS idx_glossary_lookup
    ON translation_glossary(circle_id, source_language, target_language);
CREATE INDEX IF NOT EXISTS idx_glossary_system
    ON translation_glossary(source_language, target_language) WHERE circle_id IS NULL;

-- 9. Enable RLS
ALTER TABLE handoff_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE translation_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE translation_glossary ENABLE ROW LEVEL SECURITY;

-- 10. RLS Policies

-- Handoff translations: readable by circle members
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Members can read handoff translations' AND tablename = 'handoff_translations') THEN
    CREATE POLICY "Members can read handoff translations"
        ON handoff_translations FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM handoffs h
                JOIN circle_members cm ON cm.circle_id = h.circle_id
                WHERE h.id = handoff_translations.handoff_id
                  AND cm.user_id = auth.uid()
                  AND cm.status = 'ACTIVE'
            )
        );
END IF;
END $$;

-- Handoff translations: insertable by service role (Edge Functions)
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service can insert handoff translations' AND tablename = 'handoff_translations') THEN
    CREATE POLICY "Service can insert handoff translations"
        ON handoff_translations FOR INSERT
        WITH CHECK (true);
END IF;
END $$;

-- Handoff translations: updatable by service role
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service can update handoff translations' AND tablename = 'handoff_translations') THEN
    CREATE POLICY "Service can update handoff translations"
        ON handoff_translations FOR UPDATE
        USING (true);
END IF;
END $$;

-- Translation cache: service-managed only
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service manages translation cache' AND tablename = 'translation_cache') THEN
    CREATE POLICY "Service manages translation cache"
        ON translation_cache FOR ALL
        USING (true)
        WITH CHECK (true);
END IF;
END $$;

-- Glossary: system entries readable by all authenticated users
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can read system glossary' AND tablename = 'translation_glossary') THEN
    CREATE POLICY "Authenticated users can read system glossary"
        ON translation_glossary FOR SELECT
        USING (
            circle_id IS NULL
            OR EXISTS (
                SELECT 1 FROM circle_members cm
                WHERE cm.circle_id = translation_glossary.circle_id
                  AND cm.user_id = auth.uid()
                  AND cm.status = 'ACTIVE'
            )
        );
END IF;
END $$;

-- Glossary: circle admins/owners can manage circle glossary
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle admins can manage glossary' AND tablename = 'translation_glossary') THEN
    CREATE POLICY "Circle admins can manage glossary"
        ON translation_glossary FOR INSERT
        WITH CHECK (
            circle_id IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM circle_members cm
                WHERE cm.circle_id = translation_glossary.circle_id
                  AND cm.user_id = auth.uid()
                  AND cm.role IN ('OWNER', 'ADMIN')
                  AND cm.status = 'ACTIVE'
            )
        );
END IF;
END $$;

DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle admins can update glossary' AND tablename = 'translation_glossary') THEN
    CREATE POLICY "Circle admins can update glossary"
        ON translation_glossary FOR UPDATE
        USING (
            circle_id IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM circle_members cm
                WHERE cm.circle_id = translation_glossary.circle_id
                  AND cm.user_id = auth.uid()
                  AND cm.role IN ('OWNER', 'ADMIN')
                  AND cm.status = 'ACTIVE'
            )
        );
END IF;
END $$;

DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Circle admins can delete glossary' AND tablename = 'translation_glossary') THEN
    CREATE POLICY "Circle admins can delete glossary"
        ON translation_glossary FOR DELETE
        USING (
            circle_id IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM circle_members cm
                WHERE cm.circle_id = translation_glossary.circle_id
                  AND cm.user_id = auth.uid()
                  AND cm.role IN ('OWNER', 'ADMIN')
                  AND cm.status = 'ACTIVE'
            )
        );
END IF;
END $$;
