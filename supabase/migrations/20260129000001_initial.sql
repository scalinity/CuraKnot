-- Migration: 0001_initial
-- Description: Core tables - users, circles, circle_members, circle_invites, patients
-- Date: 2026-01-29

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TABLE: users
-- ============================================================================

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text UNIQUE,
    apple_sub text UNIQUE,
    display_name text NOT NULL,
    avatar_url text,
    settings_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT users_has_auth CHECK (email IS NOT NULL OR apple_sub IS NOT NULL)
);

CREATE INDEX users_email_idx ON users(email) WHERE email IS NOT NULL;
CREATE INDEX users_apple_sub_idx ON users(apple_sub) WHERE apple_sub IS NOT NULL;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE users IS 'User profiles linked to Supabase Auth';

-- ============================================================================
-- TABLE: circles
-- ============================================================================

CREATE TABLE circles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    icon text,
    owner_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    plan text DEFAULT 'FREE' NOT NULL CHECK (plan IN ('FREE', 'PLUS', 'FAMILY')),
    settings_json jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    deleted_at timestamptz
);

CREATE INDEX circles_owner_user_id_idx ON circles(owner_user_id);
CREATE INDEX circles_deleted_at_idx ON circles(deleted_at) WHERE deleted_at IS NULL;

CREATE TRIGGER circles_updated_at
    BEFORE UPDATE ON circles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE circles IS 'Care circles - shared spaces for caregiving coordination';

-- ============================================================================
-- TABLE: circle_members
-- ============================================================================

CREATE TABLE circle_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('OWNER', 'ADMIN', 'CONTRIBUTOR', 'VIEWER')),
    status text DEFAULT 'ACTIVE' NOT NULL CHECK (status IN ('INVITED', 'ACTIVE', 'REMOVED')),
    invited_by uuid REFERENCES users(id) ON DELETE SET NULL,
    invited_at timestamptz DEFAULT now(),
    joined_at timestamptz,
    last_active_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT circle_members_unique UNIQUE (circle_id, user_id)
);

CREATE INDEX circle_members_user_id_idx ON circle_members(user_id);
CREATE INDEX circle_members_circle_id_idx ON circle_members(circle_id);
CREATE INDEX circle_members_status_idx ON circle_members(status) WHERE status = 'ACTIVE';

CREATE TRIGGER circle_members_updated_at
    BEFORE UPDATE ON circle_members
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE circle_members IS 'Membership junction table with roles';

-- ============================================================================
-- TABLE: circle_invites
-- ============================================================================

CREATE TABLE circle_invites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    token text UNIQUE NOT NULL,
    role text DEFAULT 'CONTRIBUTOR' NOT NULL CHECK (role IN ('ADMIN', 'CONTRIBUTOR', 'VIEWER')),
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    used_by uuid REFERENCES users(id) ON DELETE SET NULL,
    revoked_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX circle_invites_token_idx ON circle_invites(token);
CREATE INDEX circle_invites_circle_id_idx ON circle_invites(circle_id);
CREATE INDEX circle_invites_expires_at_idx ON circle_invites(expires_at) WHERE used_at IS NULL AND revoked_at IS NULL;

COMMENT ON TABLE circle_invites IS 'Pending invitations with tokens';

-- ============================================================================
-- TABLE: patients
-- ============================================================================

CREATE TABLE patients (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    display_name text NOT NULL,
    initials text,
    dob date,
    pronouns text,
    notes text,
    archived_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX patients_circle_id_idx ON patients(circle_id);
CREATE INDEX patients_archived_at_idx ON patients(archived_at) WHERE archived_at IS NULL;

CREATE TRIGGER patients_updated_at
    BEFORE UPDATE ON patients
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE patients IS 'Care recipients within a circle';

-- ============================================================================
-- HELPER FUNCTIONS FOR RLS
-- ============================================================================

-- Check if user is a member of a circle
CREATE OR REPLACE FUNCTION is_circle_member(p_circle_id uuid, p_user_id uuid)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM circle_members
        WHERE circle_id = p_circle_id
        AND user_id = p_user_id
        AND status = 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get user's role in a circle
CREATE OR REPLACE FUNCTION get_circle_role(p_circle_id uuid, p_user_id uuid)
RETURNS text AS $$
BEGIN
    RETURN (
        SELECT role FROM circle_members
        WHERE circle_id = p_circle_id
        AND user_id = p_user_id
        AND status = 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user has at least a certain role level
CREATE OR REPLACE FUNCTION has_circle_role(p_circle_id uuid, p_user_id uuid, p_min_role text)
RETURNS boolean AS $$
DECLARE
    v_role text;
    v_role_level int;
    v_min_level int;
BEGIN
    v_role := get_circle_role(p_circle_id, p_user_id);
    
    IF v_role IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Role hierarchy: OWNER > ADMIN > CONTRIBUTOR > VIEWER
    v_role_level := CASE v_role
        WHEN 'OWNER' THEN 4
        WHEN 'ADMIN' THEN 3
        WHEN 'CONTRIBUTOR' THEN 2
        WHEN 'VIEWER' THEN 1
        ELSE 0
    END;
    
    v_min_level := CASE p_min_role
        WHEN 'OWNER' THEN 4
        WHEN 'ADMIN' THEN 3
        WHEN 'CONTRIBUTOR' THEN 2
        WHEN 'VIEWER' THEN 1
        ELSE 0
    END;
    
    RETURN v_role_level >= v_min_level;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
