-- Migration: 0006_rls
-- Description: Row Level Security policies for all tables
-- Date: 2026-01-29

-- ============================================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE circles ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE handoffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE handoff_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE read_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE binder_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE binder_item_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_outbox ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- USERS POLICIES
-- ============================================================================

-- Users can read their own profile
CREATE POLICY users_select_own ON users
    FOR SELECT
    USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY users_update_own ON users
    FOR UPDATE
    USING (auth.uid() = id);

-- Users can insert their own profile (on signup)
CREATE POLICY users_insert_own ON users
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- CIRCLES POLICIES
-- ============================================================================

-- Members can read circles they belong to
CREATE POLICY circles_select_member ON circles
    FOR SELECT
    USING (
        deleted_at IS NULL
        AND is_circle_member(id, auth.uid())
    );

-- Any authenticated user can create a circle
CREATE POLICY circles_insert_auth ON circles
    FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL AND owner_user_id = auth.uid());

-- Owner or Admin can update circle
CREATE POLICY circles_update_admin ON circles
    FOR UPDATE
    USING (has_circle_role(id, auth.uid(), 'ADMIN'));

-- Only Owner can delete (soft delete)
CREATE POLICY circles_delete_owner ON circles
    FOR DELETE
    USING (has_circle_role(id, auth.uid(), 'OWNER'));

-- ============================================================================
-- CIRCLE_MEMBERS POLICIES
-- ============================================================================

-- Members can see other members of their circles
CREATE POLICY circle_members_select ON circle_members
    FOR SELECT
    USING (is_circle_member(circle_id, auth.uid()));

-- Owner or Admin can add members
CREATE POLICY circle_members_insert ON circle_members
    FOR INSERT
    WITH CHECK (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- Owner or Admin can update members (role changes)
CREATE POLICY circle_members_update ON circle_members
    FOR UPDATE
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- Owner or Admin can remove members
CREATE POLICY circle_members_delete ON circle_members
    FOR DELETE
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- ============================================================================
-- CIRCLE_INVITES POLICIES
-- ============================================================================

-- Owner or Admin can see invites
CREATE POLICY circle_invites_select ON circle_invites
    FOR SELECT
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- Owner or Admin can create invites
CREATE POLICY circle_invites_insert ON circle_invites
    FOR INSERT
    WITH CHECK (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- Owner or Admin can revoke invites
CREATE POLICY circle_invites_update ON circle_invites
    FOR UPDATE
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- ============================================================================
-- PATIENTS POLICIES
-- ============================================================================

-- Members can see patients in their circles
CREATE POLICY patients_select ON patients
    FOR SELECT
    USING (is_circle_member(circle_id, auth.uid()));

-- Contributors and above can create patients
CREATE POLICY patients_insert ON patients
    FOR INSERT
    WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Contributors and above can update patients
CREATE POLICY patients_update ON patients
    FOR UPDATE
    USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Owner or Admin can archive patients
CREATE POLICY patients_delete ON patients
    FOR DELETE
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- ============================================================================
-- HANDOFFS POLICIES
-- ============================================================================

-- Members can see published handoffs in their circles
-- Note: raw_transcript is handled separately via column-level security or view
CREATE POLICY handoffs_select ON handoffs
    FOR SELECT
    USING (is_circle_member(circle_id, auth.uid()));

-- Contributors and above can create handoffs
CREATE POLICY handoffs_insert ON handoffs
    FOR INSERT
    WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Creator can update within 15 min of publish, or admin+ anytime
CREATE POLICY handoffs_update ON handoffs
    FOR UPDATE
    USING (
        has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR')
        AND (
            -- Creator within 15 min of publish
            (created_by = auth.uid() AND (published_at IS NULL OR published_at > now() - interval '15 minutes'))
            -- Or admin+
            OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
        )
    );

-- Owner or Admin can delete
CREATE POLICY handoffs_delete ON handoffs
    FOR DELETE
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- ============================================================================
-- HANDOFF_REVISIONS POLICIES
-- ============================================================================

-- Members can see revisions
CREATE POLICY handoff_revisions_select ON handoff_revisions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM handoffs h
            WHERE h.id = handoff_id
            AND is_circle_member(h.circle_id, auth.uid())
        )
    );

-- Insert is done via publish_handoff function
CREATE POLICY handoff_revisions_insert ON handoff_revisions
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM handoffs h
            WHERE h.id = handoff_id
            AND has_circle_role(h.circle_id, auth.uid(), 'CONTRIBUTOR')
        )
    );

-- ============================================================================
-- READ_RECEIPTS POLICIES
-- ============================================================================

-- Users can see their own read receipts
CREATE POLICY read_receipts_select_own ON read_receipts
    FOR SELECT
    USING (user_id = auth.uid());

-- Users can create their own read receipts
CREATE POLICY read_receipts_insert_own ON read_receipts
    FOR INSERT
    WITH CHECK (
        user_id = auth.uid()
        AND is_circle_member(circle_id, auth.uid())
    );

-- Users can update their own read receipts
CREATE POLICY read_receipts_update_own ON read_receipts
    FOR UPDATE
    USING (user_id = auth.uid());

-- Users can delete their own read receipts
CREATE POLICY read_receipts_delete_own ON read_receipts
    FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================================
-- TASKS POLICIES
-- ============================================================================

-- Members can see tasks in their circles
CREATE POLICY tasks_select ON tasks
    FOR SELECT
    USING (is_circle_member(circle_id, auth.uid()));

-- Contributors and above can create tasks
CREATE POLICY tasks_insert ON tasks
    FOR INSERT
    WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Creator, assignee, or admin+ can update tasks
CREATE POLICY tasks_update ON tasks
    FOR UPDATE
    USING (
        created_by = auth.uid()
        OR owner_user_id = auth.uid()
        OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

-- Creator or admin+ can delete tasks
CREATE POLICY tasks_delete ON tasks
    FOR DELETE
    USING (
        created_by = auth.uid()
        OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

-- ============================================================================
-- BINDER_ITEMS POLICIES
-- ============================================================================

-- Members can see binder items
CREATE POLICY binder_items_select ON binder_items
    FOR SELECT
    USING (is_circle_member(circle_id, auth.uid()));

-- Contributors and above can create binder items
CREATE POLICY binder_items_insert ON binder_items
    FOR INSERT
    WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Contributors and above can update binder items
CREATE POLICY binder_items_update ON binder_items
    FOR UPDATE
    USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Owner or Admin can delete binder items
CREATE POLICY binder_items_delete ON binder_items
    FOR DELETE
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- ============================================================================
-- BINDER_ITEM_REVISIONS POLICIES
-- ============================================================================

-- Members can see revisions
CREATE POLICY binder_item_revisions_select ON binder_item_revisions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM binder_items bi
            WHERE bi.id = binder_item_id
            AND is_circle_member(bi.circle_id, auth.uid())
        )
    );

-- ============================================================================
-- ATTACHMENTS POLICIES
-- ============================================================================

-- Members can see attachments
CREATE POLICY attachments_select ON attachments
    FOR SELECT
    USING (is_circle_member(circle_id, auth.uid()));

-- Contributors and above can upload attachments
CREATE POLICY attachments_insert ON attachments
    FOR INSERT
    WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- Uploader or admin+ can delete attachments
CREATE POLICY attachments_delete ON attachments
    FOR DELETE
    USING (
        uploader_user_id = auth.uid()
        OR has_circle_role(circle_id, auth.uid(), 'ADMIN')
    );

-- ============================================================================
-- AUDIT_EVENTS POLICIES
-- ============================================================================

-- Owner or Admin can see audit events
CREATE POLICY audit_events_select ON audit_events
    FOR SELECT
    USING (has_circle_role(circle_id, auth.uid(), 'ADMIN'));

-- Insert is done via functions (SECURITY DEFINER)
-- No direct insert policy needed

-- ============================================================================
-- NOTIFICATION_OUTBOX POLICIES
-- ============================================================================

-- Users can see their own notifications
CREATE POLICY notification_outbox_select_own ON notification_outbox
    FOR SELECT
    USING (user_id = auth.uid());

-- Insert is done via functions (SECURITY DEFINER)
-- No direct insert policy needed

-- ============================================================================
-- STORAGE POLICIES (for reference - applied via Supabase Dashboard or SQL)
-- ============================================================================

-- Note: Storage bucket policies are configured separately
-- These are the intended policies:

-- attachments bucket:
--   SELECT: is_circle_member for the associated circle
--   INSERT: has_circle_role CONTRIBUTOR for the circle
--   DELETE: uploader or admin+

-- handoff-audio bucket:
--   SELECT: is_circle_member for the associated circle
--   INSERT: has_circle_role CONTRIBUTOR for the circle
--   DELETE: admin+ only

-- exports bucket:
--   SELECT: is_circle_member for the associated circle
--   INSERT: system only (via Edge Functions)
--   DELETE: admin+ only
