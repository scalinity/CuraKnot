-- ============================================================================
-- Migration: Legal Document Vault
-- Description: Secure storage for legal documents with per-member access
--              controls, time-limited sharing, and complete audit trails.
-- Date: 2026-02-21
-- ============================================================================

-- 1. Enum type for legal document categories
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'legal_document_type') THEN
        CREATE TYPE legal_document_type AS ENUM (
            'POA', 'HEALTHCARE_PROXY', 'ADVANCE_DIRECTIVE', 'HIPAA_AUTH',
            'DNR', 'POLST', 'WILL', 'TRUST', 'GUARDIANSHIP', 'OTHER'
        );
    END IF;
END $$;

-- 2. Main legal_documents table
CREATE TABLE IF NOT EXISTS legal_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,

    -- Document info
    document_type legal_document_type NOT NULL,
    title text NOT NULL,
    description text,

    -- Storage
    storage_key text NOT NULL,
    file_type text NOT NULL,  -- PDF, IMAGE
    file_size_bytes bigint NOT NULL DEFAULT 0,
    ocr_text text,

    -- Dates
    execution_date date,
    expiration_date date,

    -- Parties
    principal_name text,
    agent_name text,
    alternate_agent_name text,

    -- Verification
    notarized boolean NOT NULL DEFAULT false,
    notarized_date date,
    witness_names text[] NOT NULL DEFAULT '{}',

    -- Status: ACTIVE | EXPIRED | REVOKED | SUPERSEDED
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'EXPIRED', 'REVOKED', 'SUPERSEDED')),
    superseded_by uuid REFERENCES legal_documents(id) ON DELETE SET NULL,

    -- Emergency access
    include_in_emergency boolean NOT NULL DEFAULT false,

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 3. Per-document access control
CREATE TABLE IF NOT EXISTS legal_document_access (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Permissions
    can_view boolean NOT NULL DEFAULT true,
    can_share boolean NOT NULL DEFAULT false,
    can_edit boolean NOT NULL DEFAULT false,

    granted_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    granted_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(document_id, user_id)
);

-- 4. Time-limited share links
CREATE TABLE IF NOT EXISTS legal_document_shares (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    shared_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,

    -- Share settings
    share_token text NOT NULL UNIQUE,
    access_code text,  -- Optional 6-digit PIN
    expires_at timestamptz NOT NULL,
    max_views int,     -- NULL = unlimited

    -- Tracking
    view_count int NOT NULL DEFAULT 0,
    last_viewed_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now()
);

-- 5. Compliance audit log
CREATE TABLE IF NOT EXISTS legal_document_audit (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    user_id uuid,  -- NULL for external access via share link

    -- VIEWED | SHARED | DOWNLOADED | PRINTED | UPDATED | DELETED | ACCESS_GRANTED | ACCESS_REVOKED
    action text NOT NULL,
    details_json jsonb,

    ip_address inet,
    user_agent text,

    created_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================================
-- Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_legal_documents_patient
    ON legal_documents(patient_id, document_type);

CREATE INDEX IF NOT EXISTS idx_legal_documents_circle
    ON legal_documents(circle_id);

CREATE INDEX IF NOT EXISTS idx_legal_documents_expiration
    ON legal_documents(expiration_date)
    WHERE expiration_date IS NOT NULL AND status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_legal_documents_emergency
    ON legal_documents(patient_id)
    WHERE include_in_emergency = true AND status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_legal_document_access_document
    ON legal_document_access(document_id);

CREATE INDEX IF NOT EXISTS idx_legal_document_access_user
    ON legal_document_access(user_id);

CREATE INDEX IF NOT EXISTS idx_legal_document_shares_token
    ON legal_document_shares(share_token);

CREATE INDEX IF NOT EXISTS idx_legal_document_shares_expires
    ON legal_document_shares(expires_at)
    WHERE view_count < COALESCE(max_views, 2147483647);

CREATE INDEX IF NOT EXISTS idx_legal_document_audit_document
    ON legal_document_audit(document_id, created_at DESC);

-- ============================================================================
-- updated_at trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION update_legal_documents_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_legal_documents_updated_at ON legal_documents;
CREATE TRIGGER trg_legal_documents_updated_at
    BEFORE UPDATE ON legal_documents
    FOR EACH ROW EXECUTE FUNCTION update_legal_documents_updated_at();

-- ============================================================================
-- Row Level Security
-- ============================================================================

ALTER TABLE legal_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_document_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_document_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_document_audit ENABLE ROW LEVEL SECURITY;

-- Helper: check if user has explicit access to a document
CREATE OR REPLACE FUNCTION has_legal_doc_access(p_document_id uuid, p_user_id uuid)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM legal_document_access
        WHERE document_id = p_document_id
          AND user_id = p_user_id
          AND can_view = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper: check if user is document creator
CREATE OR REPLACE FUNCTION is_legal_doc_creator(p_document_id uuid, p_user_id uuid)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM legal_documents
        WHERE id = p_document_id
          AND created_by = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── legal_documents policies ──

-- SELECT: User must have explicit access OR be the creator
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_documents_select' AND tablename = 'legal_documents') THEN
        CREATE POLICY legal_documents_select ON legal_documents
            FOR SELECT USING (
                created_by = auth.uid()
                OR has_legal_doc_access(id, auth.uid())
            );
    END IF;
END $$;

-- INSERT: Must be circle member (Contributor+)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_documents_insert' AND tablename = 'legal_documents') THEN
        CREATE POLICY legal_documents_insert ON legal_documents
            FOR INSERT WITH CHECK (
                auth.uid() IS NOT NULL
                AND created_by = auth.uid()
                AND is_circle_member(circle_id, auth.uid())
            );
    END IF;
END $$;

-- UPDATE: Creator or Owner/Admin of circle
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_documents_update' AND tablename = 'legal_documents') THEN
        CREATE POLICY legal_documents_update ON legal_documents
            FOR UPDATE USING (
                (created_by = auth.uid() AND is_circle_member(circle_id, auth.uid()))
                OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
            );
    END IF;
END $$;

-- DELETE: Creator or Owner/Admin of circle
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_documents_delete' AND tablename = 'legal_documents') THEN
        CREATE POLICY legal_documents_delete ON legal_documents
            FOR DELETE USING (
                (created_by = auth.uid() AND is_circle_member(circle_id, auth.uid()))
                OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
            );
    END IF;
END $$;

-- ── legal_document_access policies ──

-- SELECT: User can see their own access records, or if they are Owner/Admin
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_access_select' AND tablename = 'legal_document_access') THEN
        CREATE POLICY legal_document_access_select ON legal_document_access
            FOR SELECT USING (
                user_id = auth.uid()
                OR is_legal_doc_creator(document_id, auth.uid())
                OR EXISTS (
                    SELECT 1 FROM legal_documents ld
                    JOIN circle_members cm ON cm.circle_id = ld.circle_id
                    WHERE ld.id = document_id
                      AND cm.user_id = auth.uid()
                      AND cm.status = 'ACTIVE'
                      AND cm.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- INSERT/UPDATE/DELETE: Only document creator or Owner/Admin can manage access
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_access_insert' AND tablename = 'legal_document_access') THEN
        CREATE POLICY legal_document_access_insert ON legal_document_access
            FOR INSERT WITH CHECK (
                auth.uid() IS NOT NULL
                AND granted_by = auth.uid()
                AND (
                    is_legal_doc_creator(document_id, auth.uid())
                    OR EXISTS (
                        SELECT 1 FROM legal_documents ld
                        JOIN circle_members cm ON cm.circle_id = ld.circle_id
                        WHERE ld.id = document_id
                          AND cm.user_id = auth.uid()
                          AND cm.status = 'ACTIVE'
                          AND cm.role IN ('OWNER', 'ADMIN')
                    )
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_access_update' AND tablename = 'legal_document_access') THEN
        CREATE POLICY legal_document_access_update ON legal_document_access
            FOR UPDATE USING (
                is_legal_doc_creator(document_id, auth.uid())
                OR EXISTS (
                    SELECT 1 FROM legal_documents ld
                    JOIN circle_members cm ON cm.circle_id = ld.circle_id
                    WHERE ld.id = document_id
                      AND cm.user_id = auth.uid()
                      AND cm.status = 'ACTIVE'
                      AND cm.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_access_delete' AND tablename = 'legal_document_access') THEN
        CREATE POLICY legal_document_access_delete ON legal_document_access
            FOR DELETE USING (
                is_legal_doc_creator(document_id, auth.uid())
                OR EXISTS (
                    SELECT 1 FROM legal_documents ld
                    JOIN circle_members cm ON cm.circle_id = ld.circle_id
                    WHERE ld.id = document_id
                      AND cm.user_id = auth.uid()
                      AND cm.status = 'ACTIVE'
                      AND cm.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- ── legal_document_shares policies ──

-- SELECT: Shared-by user or document creator
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_shares_select' AND tablename = 'legal_document_shares') THEN
        CREATE POLICY legal_document_shares_select ON legal_document_shares
            FOR SELECT USING (
                shared_by = auth.uid()
                OR is_legal_doc_creator(document_id, auth.uid())
            );
    END IF;
END $$;

-- INSERT: Must have can_share permission
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_shares_insert' AND tablename = 'legal_document_shares') THEN
        CREATE POLICY legal_document_shares_insert ON legal_document_shares
            FOR INSERT WITH CHECK (
                auth.uid() IS NOT NULL
                AND shared_by = auth.uid()
                AND (
                    is_legal_doc_creator(document_id, auth.uid())
                    OR EXISTS (
                        SELECT 1 FROM legal_document_access
                        WHERE document_id = legal_document_shares.document_id
                          AND user_id = auth.uid()
                          AND can_share = true
                    )
                )
            );
    END IF;
END $$;

-- UPDATE: Service role or shared-by user (for view count increments via RPC)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_shares_update' AND tablename = 'legal_document_shares') THEN
        CREATE POLICY legal_document_shares_update ON legal_document_shares
            FOR UPDATE USING (
                shared_by = auth.uid()
                OR is_legal_doc_creator(document_id, auth.uid())
            );
    END IF;
END $$;

-- DELETE: Shared-by user or document creator
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_shares_delete' AND tablename = 'legal_document_shares') THEN
        CREATE POLICY legal_document_shares_delete ON legal_document_shares
            FOR DELETE USING (
                shared_by = auth.uid()
                OR is_legal_doc_creator(document_id, auth.uid())
            );
    END IF;
END $$;

-- ── legal_document_audit policies ──

-- SELECT: Owner/Admin of the circle, or the acting user
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_audit_select' AND tablename = 'legal_document_audit') THEN
        CREATE POLICY legal_document_audit_select ON legal_document_audit
            FOR SELECT USING (
                user_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM legal_documents ld
                    JOIN circle_members cm ON cm.circle_id = ld.circle_id
                    WHERE ld.id = document_id
                      AND cm.user_id = auth.uid()
                      AND cm.status = 'ACTIVE'
                      AND cm.role IN ('OWNER', 'ADMIN')
                )
            );
    END IF;
END $$;

-- INSERT: Authenticated users can insert audit entries for themselves
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'legal_document_audit_insert' AND tablename = 'legal_document_audit') THEN
        CREATE POLICY legal_document_audit_insert ON legal_document_audit
            FOR INSERT WITH CHECK (
                auth.uid() IS NOT NULL
                AND (user_id = auth.uid() OR user_id IS NULL)
            );
    END IF;
END $$;

-- ============================================================================
-- Storage bucket for legal documents (if not exists)
-- ============================================================================
-- Note: Storage bucket creation is handled via Supabase Dashboard or CLI.
-- The bucket "legal-documents" should be created as a private bucket.

-- ============================================================================
-- Atomic share view count increment (used by resolve-document-share)
-- ============================================================================

CREATE OR REPLACE FUNCTION increment_share_view_count(p_share_id uuid)
RETURNS void AS $$
BEGIN
    UPDATE legal_document_shares
    SET view_count = view_count + 1,
        last_viewed_at = now()
    WHERE id = p_share_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Add legal_vault feature + max_legal_documents to plan_limits
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'plan_limits') THEN
        -- Add max_legal_documents column if it doesn't exist
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'plan_limits' AND column_name = 'max_legal_documents'
        ) THEN
            ALTER TABLE plan_limits ADD COLUMN max_legal_documents int;  -- NULL = unlimited
        END IF;

        -- Set limits: FREE=0, PLUS=5, FAMILY=unlimited
        UPDATE plan_limits SET max_legal_documents = 0 WHERE plan = 'FREE';
        UPDATE plan_limits SET max_legal_documents = 5 WHERE plan = 'PLUS';
        UPDATE plan_limits SET max_legal_documents = NULL WHERE plan = 'FAMILY';
    END IF;
END $$;
