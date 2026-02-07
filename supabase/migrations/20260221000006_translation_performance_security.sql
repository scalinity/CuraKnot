-- ============================================================================
-- Migration: Translation Performance & Security Hardening
-- Description: Add index for staleness query, glossary term length constraints
-- Date: 2026-02-21
-- ============================================================================

-- 1. Add index on handoffs.updated_at for staleness detection query
-- The mark_stale_translations RPC joins handoff_translations with handoffs
-- and filters by h.updated_at > ht.created_at. Without this index, the
-- query performs a full table scan on handoffs.
CREATE INDEX IF NOT EXISTS idx_handoffs_updated_at_id
    ON handoffs(updated_at DESC, id);

-- 2. Add CHECK constraints on glossary term lengths to enforce server-side
-- validation (defense-in-depth against client bypass)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'glossary_source_term_length'
    ) THEN
        ALTER TABLE translation_glossary
            ADD CONSTRAINT glossary_source_term_length
            CHECK (char_length(source_term) <= 200);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'glossary_translated_term_length'
    ) THEN
        ALTER TABLE translation_glossary
            ADD CONSTRAINT glossary_translated_term_length
            CHECK (char_length(translated_term) <= 200);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'glossary_context_length'
    ) THEN
        ALTER TABLE translation_glossary
            ADD CONSTRAINT glossary_context_length
            CHECK (context IS NULL OR char_length(context) <= 500);
    END IF;
END $$;
