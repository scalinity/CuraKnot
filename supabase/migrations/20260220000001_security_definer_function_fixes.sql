-- ============================================================================
-- Migration: Security Hardening - SECURITY DEFINER Function Fixes
-- Description: Replace p_user_id with auth.uid() in client-only functions,
--              add auth.uid() validation for Edge Function-called functions.
-- Date: 2026-02-20
-- ============================================================================

-- ============================================================================
-- C1a: publish_handoff - CLIENT ONLY, remove p_user_id, use auth.uid()
-- ============================================================================

CREATE OR REPLACE FUNCTION publish_handoff(
    p_handoff_id uuid,
    p_structured_json jsonb
)
RETURNS jsonb AS $$
DECLARE
    v_handoff handoffs%ROWTYPE;
    v_revision int;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get the handoff
    SELECT * INTO v_handoff FROM handoffs WHERE id = p_handoff_id;

    IF v_handoff IS NULL THEN
        RETURN jsonb_build_object('error', 'Handoff not found');
    END IF;

    -- Check if user can publish
    IF NOT has_circle_role(v_handoff.circle_id, v_caller, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Permission denied');
    END IF;

    -- Determine revision number
    IF v_handoff.status = 'DRAFT' THEN
        v_revision := 1;
    ELSE
        v_revision := v_handoff.current_revision + 1;
    END IF;

    -- Create revision record
    INSERT INTO handoff_revisions (handoff_id, revision, structured_json, edited_by)
    VALUES (p_handoff_id, v_revision, p_structured_json, v_caller);

    -- Update handoff
    UPDATE handoffs
    SET
        status = 'PUBLISHED',
        published_at = COALESCE(published_at, now()),
        current_revision = v_revision,
        title = COALESCE(p_structured_json->>'title', title),
        summary = p_structured_json->>'summary',
        keywords = COALESCE(
            ARRAY(SELECT jsonb_array_elements_text(p_structured_json->'keywords')),
            keywords
        ),
        updated_at = now()
    WHERE id = p_handoff_id;

    RETURN jsonb_build_object(
        'handoff_id', p_handoff_id,
        'revision', v_revision,
        'published_at', now()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION publish_handoff(uuid, jsonb) IS 'Publish a handoff with structured brief (uses auth.uid())';

-- Drop the old 3-param overload if it exists
DROP FUNCTION IF EXISTS publish_handoff(uuid, jsonb, uuid);


-- ============================================================================
-- C1b: complete_task - CLIENT ONLY, remove p_user_id, use auth.uid()
-- ============================================================================

CREATE OR REPLACE FUNCTION complete_task(
    p_task_id uuid,
    p_completion_note text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_task tasks%ROWTYPE;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get the task
    SELECT * INTO v_task FROM tasks WHERE id = p_task_id;

    IF v_task IS NULL THEN
        RETURN jsonb_build_object('error', 'Task not found');
    END IF;

    -- Check if user can complete (must be assignee, creator, or admin+)
    IF v_task.owner_user_id != v_caller
       AND v_task.created_by != v_caller
       AND NOT has_circle_role(v_task.circle_id, v_caller, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Permission denied');
    END IF;

    -- Check if already completed
    IF v_task.status = 'DONE' THEN
        RETURN jsonb_build_object('error', 'Task already completed');
    END IF;

    -- Complete the task
    UPDATE tasks
    SET
        status = 'DONE',
        completed_at = now(),
        completed_by = v_caller,
        completion_note = p_completion_note,
        updated_at = now()
    WHERE id = p_task_id;

    RETURN jsonb_build_object(
        'task_id', p_task_id,
        'status', 'DONE',
        'completed_at', now(),
        'completed_by', v_caller
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION complete_task(uuid, text) IS 'Mark a task as completed with immutable completion log (uses auth.uid())';

-- Drop the old 3-param overload
DROP FUNCTION IF EXISTS complete_task(uuid, uuid, text);


-- ============================================================================
-- C1c: get_financial_summary - CLIENT ONLY, remove p_user_id, use auth.uid()
-- ============================================================================

CREATE OR REPLACE FUNCTION get_financial_summary(
    p_circle_id uuid,
    p_start_date date DEFAULT NULL,
    p_end_date date DEFAULT NULL,
    p_patient_id uuid DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_summary jsonb;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Check membership
    IF NOT is_circle_member(p_circle_id, v_caller) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;

    SELECT jsonb_build_object(
        'total_open', COALESCE(SUM(CASE WHEN status = 'OPEN' THEN amount_cents ELSE 0 END), 0),
        'total_paid', COALESCE(SUM(CASE WHEN status = 'PAID' THEN amount_cents ELSE 0 END), 0),
        'total_denied', COALESCE(SUM(CASE WHEN status = 'DENIED' THEN amount_cents ELSE 0 END), 0),
        'count_by_status', jsonb_build_object(
            'open', COUNT(*) FILTER (WHERE status = 'OPEN'),
            'submitted', COUNT(*) FILTER (WHERE status = 'SUBMITTED'),
            'paid', COUNT(*) FILTER (WHERE status = 'PAID'),
            'denied', COUNT(*) FILTER (WHERE status = 'DENIED'),
            'closed', COUNT(*) FILTER (WHERE status = 'CLOSED')
        ),
        'count_by_kind', jsonb_build_object(
            'bill', COUNT(*) FILTER (WHERE kind = 'BILL'),
            'claim', COUNT(*) FILTER (WHERE kind = 'CLAIM'),
            'eob', COUNT(*) FILTER (WHERE kind = 'EOB'),
            'auth', COUNT(*) FILTER (WHERE kind = 'AUTH'),
            'receipt', COUNT(*) FILTER (WHERE kind = 'RECEIPT')
        ),
        'overdue_count', COUNT(*) FILTER (WHERE status = 'OPEN' AND due_at < now()),
        'due_soon_count', COUNT(*) FILTER (WHERE status = 'OPEN' AND due_at >= now() AND due_at < now() + interval '7 days')
    ) INTO v_summary
    FROM financial_items
    WHERE circle_id = p_circle_id
      AND (p_patient_id IS NULL OR patient_id = p_patient_id)
      AND (p_start_date IS NULL OR created_at >= p_start_date)
      AND (p_end_date IS NULL OR created_at <= p_end_date + interval '1 day');

    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_financial_summary(uuid, date, date, uuid) IS 'Get aggregated financial summary for a circle (uses auth.uid())';

-- Drop old 5-param overload
DROP FUNCTION IF EXISTS get_financial_summary(uuid, uuid, date, date, uuid);


-- ============================================================================
-- C1d: create_financial_reminder_task - CLIENT ONLY, remove p_user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION create_financial_reminder_task(
    p_financial_item_id uuid,
    p_title text DEFAULT NULL,
    p_due_at timestamptz DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_item financial_items%ROWTYPE;
    v_task_id uuid;
    v_task_title text;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get the financial item
    SELECT * INTO v_item FROM financial_items WHERE id = p_financial_item_id;

    IF v_item IS NULL THEN
        RETURN jsonb_build_object('error', 'Financial item not found');
    END IF;

    -- Check permissions
    IF NOT has_circle_role(v_item.circle_id, v_caller, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;

    -- Build task title
    v_task_title := COALESCE(
        p_title,
        'Follow up: ' || v_item.kind || COALESCE(' - ' || v_item.vendor, '')
    );

    -- Create task
    INSERT INTO tasks (
        circle_id,
        patient_id,
        created_by,
        owner_user_id,
        title,
        description,
        due_at,
        priority
    ) VALUES (
        v_item.circle_id,
        v_item.patient_id,
        v_caller,
        v_caller,
        v_task_title,
        'Related to ' || v_item.kind || CASE
            WHEN v_item.reference_id IS NOT NULL THEN ' #' || v_item.reference_id
            ELSE ''
        END,
        COALESCE(p_due_at, v_item.due_at),
        CASE
            WHEN v_item.due_at < now() THEN 'HIGH'
            ELSE 'MED'
        END
    )
    RETURNING id INTO v_task_id;

    -- Link task to financial item
    INSERT INTO financial_item_tasks (financial_item_id, task_id)
    VALUES (p_financial_item_id, v_task_id);

    RETURN jsonb_build_object(
        'task_id', v_task_id,
        'financial_item_id', p_financial_item_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_financial_reminder_task(uuid, text, timestamptz) IS 'Create a reminder task linked to a financial item (uses auth.uid())';

-- Drop old overload
DROP FUNCTION IF EXISTS create_financial_reminder_task(uuid, uuid, text, timestamptz);


-- ============================================================================
-- C1e: revoke_share_link - CLIENT ONLY, remove p_user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION revoke_share_link(
    p_link_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_link share_links%ROWTYPE;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    SELECT * INTO v_link FROM share_links WHERE id = p_link_id;

    IF v_link IS NULL THEN
        RETURN jsonb_build_object('error', 'Link not found');
    END IF;

    -- Check membership
    IF NOT is_circle_member(v_link.circle_id, v_caller) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;

    -- Revoke
    UPDATE share_links SET revoked_at = now() WHERE id = p_link_id;

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_link.circle_id,
        v_caller,
        'SHARE_LINK_REVOKED',
        'share_link',
        p_link_id,
        jsonb_build_object('original_object_type', v_link.object_type, 'original_object_id', v_link.object_id)
    );

    RETURN jsonb_build_object('revoked', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old overload
DROP FUNCTION IF EXISTS revoke_share_link(uuid, uuid);


-- ============================================================================
-- C1f: accept_med_proposal - CLIENT ONLY, remove p_user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION accept_med_proposal(
    p_proposal_id uuid,
    p_modified_json jsonb DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_proposal med_proposals%ROWTYPE;
    v_final_data jsonb;
    v_binder_item_id uuid;
    v_handoff_id uuid;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get proposal
    SELECT * INTO v_proposal FROM med_proposals WHERE id = p_proposal_id;
    IF v_proposal IS NULL THEN
        RETURN jsonb_build_object('error', 'Proposal not found');
    END IF;

    IF v_proposal.status != 'PROPOSED' THEN
        RETURN jsonb_build_object('error', 'Proposal already processed');
    END IF;

    -- Check permissions
    IF NOT has_circle_role(v_proposal.circle_id, v_caller, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;

    -- Use modified data if provided, otherwise use original
    v_final_data := COALESCE(p_modified_json, v_proposal.proposed_json);

    IF v_proposal.existing_med_id IS NOT NULL THEN
        -- Update existing medication
        UPDATE binder_items
        SET
            content_json = content_json || v_final_data,
            updated_by = v_caller,
            updated_at = now()
        WHERE id = v_proposal.existing_med_id;

        v_binder_item_id := v_proposal.existing_med_id;
    ELSE
        -- Create new medication
        INSERT INTO binder_items (
            circle_id,
            patient_id,
            type,
            title,
            content_json,
            created_by,
            updated_by
        ) VALUES (
            v_proposal.circle_id,
            v_proposal.patient_id,
            'MED',
            COALESCE(v_final_data->>'name', 'Unknown Medication'),
            v_final_data || jsonb_build_object(
                'source', 'reconciliation',
                'verified_at', now(),
                'verified_by', v_caller
            ),
            v_caller,
            v_caller
        )
        RETURNING id INTO v_binder_item_id;
    END IF;

    -- Update proposal status
    UPDATE med_proposals
    SET
        status = 'ACCEPTED',
        accepted_by = v_caller,
        accepted_at = now()
    WHERE id = p_proposal_id;

    -- Create audit event
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_proposal.circle_id,
        v_caller,
        'MED_PROPOSAL_ACCEPTED',
        'med_proposal',
        p_proposal_id,
        jsonb_build_object(
            'binder_item_id', v_binder_item_id,
            'was_update', v_proposal.existing_med_id IS NOT NULL
        )
    );

    RETURN jsonb_build_object(
        'proposal_id', p_proposal_id,
        'binder_item_id', v_binder_item_id,
        'status', 'ACCEPTED'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION accept_med_proposal(uuid, jsonb) IS 'Accept a med proposal (uses auth.uid())';

-- Drop old overload
DROP FUNCTION IF EXISTS accept_med_proposal(uuid, uuid, jsonb);


-- ============================================================================
-- C1g: reject_med_proposal - CLIENT ONLY, remove p_user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION reject_med_proposal(
    p_proposal_id uuid,
    p_reason text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_proposal med_proposals%ROWTYPE;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get proposal
    SELECT * INTO v_proposal FROM med_proposals WHERE id = p_proposal_id;
    IF v_proposal IS NULL THEN
        RETURN jsonb_build_object('error', 'Proposal not found');
    END IF;

    IF v_proposal.status != 'PROPOSED' THEN
        RETURN jsonb_build_object('error', 'Proposal already processed');
    END IF;

    -- Check permissions
    IF NOT has_circle_role(v_proposal.circle_id, v_caller, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;

    -- Update proposal status
    UPDATE med_proposals
    SET
        status = 'REJECTED',
        rejected_by = v_caller,
        rejected_at = now(),
        rejection_reason = p_reason
    WHERE id = p_proposal_id;

    RETURN jsonb_build_object(
        'proposal_id', p_proposal_id,
        'status', 'REJECTED'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old overload
DROP FUNCTION IF EXISTS reject_med_proposal(uuid, uuid, text);


-- ============================================================================
-- C1h: finalize_shift - CLIENT ONLY, remove p_user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION finalize_shift(
    p_shift_id uuid,
    p_notes text DEFAULT NULL,
    p_create_handoff boolean DEFAULT true
)
RETURNS jsonb AS $$
DECLARE
    v_shift care_shifts%ROWTYPE;
    v_handoff_id uuid;
    v_checklist_summary text;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get shift
    SELECT * INTO v_shift FROM care_shifts WHERE id = p_shift_id;
    IF v_shift IS NULL THEN
        RETURN jsonb_build_object('error', 'Shift not found');
    END IF;

    -- Check ownership or admin
    IF v_shift.owner_user_id != v_caller AND NOT has_circle_role(v_shift.circle_id, v_caller, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Not authorized to finalize this shift');
    END IF;

    -- Check status
    IF v_shift.status NOT IN ('SCHEDULED', 'ACTIVE') THEN
        RETURN jsonb_build_object('error', 'Shift already finalized');
    END IF;

    -- Build checklist summary
    SELECT string_agg(
        CASE WHEN (item->>'completed')::boolean THEN E'\u2713 ' ELSE E'\u25CB ' END || (item->>'text'),
        E'\n'
    )
    INTO v_checklist_summary
    FROM jsonb_array_elements(v_shift.checklist_json) AS item;

    -- Create handoff if requested
    IF p_create_handoff THEN
        INSERT INTO handoffs (
            circle_id,
            patient_id,
            created_by,
            type,
            title,
            summary,
            status
        ) VALUES (
            v_shift.circle_id,
            v_shift.patient_id,
            v_caller,
            'OTHER',
            'Shift Summary: ' || to_char(v_shift.start_at, 'Mon DD HH24:MI') || ' - ' || to_char(v_shift.end_at, 'HH24:MI'),
            COALESCE(p_notes, '') ||
            CASE WHEN v_checklist_summary IS NOT NULL THEN E'\n\nChecklist:\n' || v_checklist_summary ELSE '' END,
            'DRAFT'
        )
        RETURNING id INTO v_handoff_id;
    END IF;

    -- Update shift status
    UPDATE care_shifts
    SET
        status = 'COMPLETED',
        notes = COALESCE(p_notes, notes),
        summary_handoff_id = v_handoff_id,
        updated_at = now()
    WHERE id = p_shift_id;

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_shift.circle_id,
        v_caller,
        'SHIFT_COMPLETED',
        'care_shift',
        p_shift_id,
        jsonb_build_object('handoff_id', v_handoff_id)
    );

    RETURN jsonb_build_object(
        'shift_id', p_shift_id,
        'status', 'COMPLETED',
        'handoff_id', v_handoff_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old overload
DROP FUNCTION IF EXISTS finalize_shift(uuid, uuid, text, boolean);


-- ============================================================================
-- C1i: create_helper_link - CLIENT ONLY, remove p_user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION create_helper_link(
    p_circle_id uuid,
    p_patient_id uuid,
    p_name text DEFAULT NULL,
    p_ttl_days int DEFAULT 30
)
RETURNS jsonb AS $$
DECLARE
    v_token text;
    v_link_id uuid;
    v_expires_at timestamptz;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Check permissions (admin only)
    IF NOT has_circle_role(p_circle_id, v_caller, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Admin role required');
    END IF;

    -- Generate token
    v_token := encode(gen_random_bytes(24), 'base64');
    v_token := replace(replace(replace(v_token, '+', '-'), '/', '_'), '=', '');
    v_expires_at := now() + (p_ttl_days || ' days')::interval;

    -- Create link
    INSERT INTO helper_links (
        circle_id,
        patient_id,
        token,
        name,
        expires_at,
        created_by
    ) VALUES (
        p_circle_id,
        p_patient_id,
        v_token,
        p_name,
        v_expires_at,
        v_caller
    )
    RETURNING id INTO v_link_id;

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        p_circle_id,
        v_caller,
        'HELPER_LINK_CREATED',
        'helper_link',
        v_link_id,
        jsonb_build_object('name', p_name, 'ttl_days', p_ttl_days)
    );

    RETURN jsonb_build_object(
        'link_id', v_link_id,
        'token', v_token,
        'expires_at', v_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old overload
DROP FUNCTION IF EXISTS create_helper_link(uuid, uuid, uuid, text, int);


-- ============================================================================
-- C1j: review_helper_submission - CLIENT ONLY, remove p_user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION review_helper_submission(
    p_submission_id uuid,
    p_action text,  -- 'APPROVE' or 'REJECT'
    p_note text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_submission helper_submissions%ROWTYPE;
    v_handoff_id uuid;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get submission
    SELECT * INTO v_submission FROM helper_submissions WHERE id = p_submission_id;

    IF v_submission IS NULL THEN
        RETURN jsonb_build_object('error', 'Submission not found');
    END IF;

    IF v_submission.status != 'PENDING' THEN
        RETURN jsonb_build_object('error', 'Submission already reviewed');
    END IF;

    -- Check permissions
    IF NOT has_circle_role(v_submission.circle_id, v_caller, 'ADMIN') THEN
        RETURN jsonb_build_object('error', 'Admin role required');
    END IF;

    IF p_action = 'APPROVE' THEN
        -- Create handoff from submission
        INSERT INTO handoffs (
            circle_id,
            patient_id,
            created_by,
            type,
            title,
            summary,
            status
        ) VALUES (
            v_submission.circle_id,
            v_submission.patient_id,
            v_caller,
            'FACILITY_UPDATE',
            COALESCE(v_submission.payload_json->>'title', 'External Update from ' || COALESCE(v_submission.submitter_name, 'Helper')),
            COALESCE(v_submission.payload_json->>'summary', v_submission.payload_json::text),
            'PUBLISHED'
        )
        RETURNING id INTO v_handoff_id;

        -- Update submission
        UPDATE helper_submissions
        SET
            status = 'APPROVED',
            reviewed_by = v_caller,
            reviewed_at = now(),
            review_note = p_note,
            result_handoff_id = v_handoff_id
        WHERE id = p_submission_id;

    ELSE -- REJECT
        UPDATE helper_submissions
        SET
            status = 'REJECTED',
            reviewed_by = v_caller,
            reviewed_at = now(),
            review_note = p_note
        WHERE id = p_submission_id;
    END IF;

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_submission.circle_id,
        v_caller,
        CASE WHEN p_action = 'APPROVE' THEN 'HELPER_SUBMISSION_APPROVED' ELSE 'HELPER_SUBMISSION_REJECTED' END,
        'helper_submission',
        p_submission_id,
        jsonb_build_object('action', p_action, 'handoff_id', v_handoff_id)
    );

    RETURN jsonb_build_object(
        'submission_id', p_submission_id,
        'action', p_action,
        'handoff_id', v_handoff_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old overload
DROP FUNCTION IF EXISTS review_helper_submission(uuid, uuid, text, text);


-- ============================================================================
-- C1k: assign_inbox_item - CLIENT ONLY, remove p_user_id (keep p_assignee_id)
-- ============================================================================

CREATE OR REPLACE FUNCTION assign_inbox_item(
    p_item_id uuid,
    p_assignee_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_item inbox_items%ROWTYPE;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('error', 'Authentication required');
    END IF;

    -- Get the inbox item
    SELECT * INTO v_item FROM inbox_items WHERE id = p_item_id;

    IF v_item IS NULL THEN
        RETURN jsonb_build_object('error', 'Item not found');
    END IF;

    -- Check if user is a member with at least contributor role
    IF NOT has_circle_role(v_item.circle_id, v_caller, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;

    -- Check assignee is a member
    IF NOT is_circle_member(v_item.circle_id, p_assignee_id) THEN
        RETURN jsonb_build_object('error', 'Assignee is not a circle member');
    END IF;

    -- Update the item
    UPDATE inbox_items
    SET
        assigned_to = p_assignee_id,
        status = 'ASSIGNED',
        updated_at = now()
    WHERE id = p_item_id;

    RETURN jsonb_build_object(
        'item_id', p_item_id,
        'status', 'ASSIGNED',
        'assigned_to', p_assignee_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION assign_inbox_item(uuid, uuid) IS 'Assign an inbox item to a circle member (uses auth.uid())';

-- Drop old overload
DROP FUNCTION IF EXISTS assign_inbox_item(uuid, uuid, uuid);


-- ============================================================================
-- C1l: triage_inbox_item - CALLED FROM EDGE FUNCTION via service_role
-- Keep p_user_id but validate auth.uid() matches when called from client
-- ============================================================================

CREATE OR REPLACE FUNCTION triage_inbox_item(
    p_item_id uuid,
    p_user_id uuid,
    p_destination_type text,
    p_destination_data jsonb DEFAULT NULL,
    p_note text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_item inbox_items%ROWTYPE;
    v_destination_id uuid;
    v_handoff_id uuid;
    v_task_id uuid;
    v_binder_item_id uuid;
BEGIN
    -- Validate: if auth context exists, p_user_id must match
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'User ID mismatch: cannot act on behalf of another user';
    END IF;

    -- Get the inbox item
    SELECT * INTO v_item FROM inbox_items WHERE id = p_item_id;

    IF v_item IS NULL THEN
        RETURN jsonb_build_object('error', 'Item not found');
    END IF;

    -- Check if user is a member of the circle
    IF NOT is_circle_member(v_item.circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;

    -- Check if already triaged
    IF v_item.status = 'TRIAGED' THEN
        RETURN jsonb_build_object('error', 'Item already triaged');
    END IF;

    -- Handle based on destination type
    CASE p_destination_type
        WHEN 'HANDOFF' THEN
            INSERT INTO handoffs (
                circle_id,
                patient_id,
                created_by,
                type,
                title,
                summary,
                status
            ) VALUES (
                v_item.circle_id,
                COALESCE(v_item.patient_id, (p_destination_data->>'patient_id')::uuid),
                p_user_id,
                COALESCE(p_destination_data->>'type', 'OTHER'),
                COALESCE(v_item.title, 'Inbox Item'),
                COALESCE(v_item.note, v_item.text_payload, ''),
                'DRAFT'
            )
            RETURNING id INTO v_handoff_id;

            IF v_item.attachment_id IS NOT NULL THEN
                UPDATE attachments
                SET handoff_id = v_handoff_id
                WHERE id = v_item.attachment_id;
            END IF;

            v_destination_id := v_handoff_id;

        WHEN 'TASK' THEN
            INSERT INTO tasks (
                circle_id,
                patient_id,
                created_by,
                owner_user_id,
                title,
                description,
                due_at,
                priority
            ) VALUES (
                v_item.circle_id,
                v_item.patient_id,
                p_user_id,
                COALESCE((p_destination_data->>'owner_user_id')::uuid, p_user_id),
                COALESCE(v_item.title, 'From Inbox'),
                COALESCE(v_item.note, v_item.text_payload),
                (p_destination_data->>'due_at')::timestamptz,
                COALESCE(p_destination_data->>'priority', 'MED')
            )
            RETURNING id INTO v_task_id;

            v_destination_id := v_task_id;

        WHEN 'BINDER' THEN
            INSERT INTO binder_items (
                circle_id,
                patient_id,
                type,
                title,
                content_json,
                created_by,
                updated_by
            ) VALUES (
                v_item.circle_id,
                v_item.patient_id,
                CASE
                    WHEN v_item.kind IN ('PHOTO', 'PDF') THEN 'DOC'
                    ELSE 'NOTE'
                END,
                COALESCE(v_item.title, 'From Inbox'),
                jsonb_build_object(
                    'content', COALESCE(v_item.note, v_item.text_payload, ''),
                    'attachment_id', v_item.attachment_id,
                    'source', 'inbox'
                ),
                p_user_id,
                p_user_id
            )
            RETURNING id INTO v_binder_item_id;

            IF v_item.attachment_id IS NOT NULL THEN
                UPDATE attachments
                SET binder_item_id = v_binder_item_id
                WHERE id = v_item.attachment_id;
            END IF;

            v_destination_id := v_binder_item_id;

        WHEN 'ARCHIVE' THEN
            v_destination_id := NULL;

        ELSE
            RETURN jsonb_build_object('error', 'Invalid destination type');
    END CASE;

    -- Update inbox item status
    UPDATE inbox_items
    SET
        status = 'TRIAGED',
        updated_at = now()
    WHERE id = p_item_id;

    -- Create triage log
    INSERT INTO inbox_triage_log (
        inbox_item_id,
        triaged_by,
        destination_type,
        destination_id,
        note
    ) VALUES (
        p_item_id,
        p_user_id,
        p_destination_type,
        v_destination_id,
        p_note
    );

    -- Create audit event
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        v_item.circle_id,
        p_user_id,
        'INBOX_ITEM_TRIAGED',
        'inbox_item',
        p_item_id,
        jsonb_build_object(
            'destination_type', p_destination_type,
            'destination_id', v_destination_id
        )
    );

    RETURN jsonb_build_object(
        'item_id', p_item_id,
        'status', 'TRIAGED',
        'destination_type', p_destination_type,
        'destination_id', v_destination_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION triage_inbox_item IS 'Route an inbox item to handoff, task, binder, or archive (validates auth.uid() when present)';


-- ============================================================================
-- C1m: create_share_link - CALLED FROM EDGE FUNCTIONS via service_role
-- Keep p_user_id but validate auth.uid() matches when called from client
-- ============================================================================

CREATE OR REPLACE FUNCTION create_share_link(
    p_circle_id uuid,
    p_user_id uuid,
    p_object_type text,
    p_object_id uuid,
    p_ttl_hours int DEFAULT 24
)
RETURNS jsonb AS $$
DECLARE
    v_token text;
    v_link_id uuid;
    v_expires_at timestamptz;
BEGIN
    -- Validate: if auth context exists, p_user_id must match
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'User ID mismatch: cannot act on behalf of another user';
    END IF;

    -- Check membership
    IF NOT is_circle_member(p_circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;

    -- Generate token and expiry
    v_token := generate_share_token();
    v_expires_at := now() + (p_ttl_hours || ' hours')::interval;

    -- Create link
    INSERT INTO share_links (
        circle_id,
        object_type,
        object_id,
        token,
        expires_at,
        created_by
    ) VALUES (
        p_circle_id,
        p_object_type,
        p_object_id,
        v_token,
        v_expires_at,
        p_user_id
    )
    RETURNING id INTO v_link_id;

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        p_circle_id,
        p_user_id,
        'SHARE_LINK_CREATED',
        p_object_type,
        p_object_id,
        jsonb_build_object('link_id', v_link_id, 'ttl_hours', p_ttl_hours)
    );

    RETURN jsonb_build_object(
        'link_id', v_link_id,
        'token', v_token,
        'expires_at', v_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- C1n: create_or_update_emergency_card - CALLED FROM EDGE FUNCTION via service_role
-- Keep p_user_id but validate auth.uid() matches when called from client
-- ============================================================================

CREATE OR REPLACE FUNCTION create_or_update_emergency_card(
    p_circle_id uuid,
    p_patient_id uuid,
    p_user_id uuid,
    p_config jsonb DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_card_id uuid;
    v_snapshot jsonb;
BEGIN
    -- Validate: if auth context exists, p_user_id must match
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'User ID mismatch: cannot act on behalf of another user';
    END IF;

    -- Check membership
    IF NOT has_circle_role(p_circle_id, p_user_id, 'CONTRIBUTOR') THEN
        RETURN jsonb_build_object('error', 'Insufficient permissions');
    END IF;

    -- Upsert card
    INSERT INTO emergency_cards (circle_id, patient_id, created_by, config_json)
    VALUES (p_circle_id, p_patient_id, p_user_id, COALESCE(p_config, '{}'::jsonb))
    ON CONFLICT (circle_id, patient_id) DO UPDATE
    SET
        config_json = COALESCE(p_config, emergency_cards.config_json),
        updated_at = now()
    RETURNING id INTO v_card_id;

    -- Generate snapshot
    v_snapshot := generate_emergency_card_snapshot(v_card_id);

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id
    ) VALUES (
        p_circle_id,
        p_user_id,
        'EMERGENCY_CARD_UPDATED',
        'emergency_card',
        v_card_id
    );

    RETURN jsonb_build_object(
        'card_id', v_card_id,
        'snapshot', v_snapshot
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- C1o: create_care_network_export - CALLED FROM EDGE FUNCTION via service_role
-- Keep p_user_id but validate auth.uid() matches when called from client
-- ============================================================================

CREATE OR REPLACE FUNCTION create_care_network_export(
    p_circle_id uuid,
    p_patient_id uuid,
    p_user_id uuid,
    p_included_types text[],
    p_create_share_link boolean DEFAULT false,
    p_share_link_ttl_hours int DEFAULT 168
)
RETURNS jsonb AS $$
DECLARE
    v_export_id uuid;
    v_content jsonb;
    v_provider_count int;
    v_share_link_result jsonb;
    v_share_link_id uuid;
BEGIN
    -- Validate: if auth context exists, p_user_id must match
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'User ID mismatch: cannot act on behalf of another user';
    END IF;

    -- Check membership
    IF NOT is_circle_member(p_circle_id, p_user_id) THEN
        RETURN jsonb_build_object('error', 'Not a circle member');
    END IF;

    -- Compose content
    v_content := compose_care_network_content(p_circle_id, p_patient_id, p_included_types);
    v_provider_count := (v_content->'counts'->>'total')::int;

    IF v_provider_count = 0 THEN
        RETURN jsonb_build_object('error', 'No providers found to export');
    END IF;

    -- Create export record
    INSERT INTO care_network_exports (
        circle_id,
        patient_id,
        created_by,
        included_types,
        content_snapshot_json,
        provider_count
    ) VALUES (
        p_circle_id,
        p_patient_id,
        p_user_id,
        p_included_types,
        v_content,
        v_provider_count
    )
    RETURNING id INTO v_export_id;

    -- Create share link if requested
    IF p_create_share_link THEN
        v_share_link_result := create_share_link(
            p_circle_id,
            p_user_id,
            'care_network',
            v_export_id,
            p_share_link_ttl_hours
        );

        IF v_share_link_result ? 'error' THEN
            RETURN v_share_link_result;
        END IF;

        v_share_link_id := (v_share_link_result->>'link_id')::uuid;

        -- Update export with share link reference
        UPDATE care_network_exports
        SET share_link_id = v_share_link_id
        WHERE id = v_export_id;
    END IF;

    -- Audit
    INSERT INTO audit_events (
        circle_id,
        actor_user_id,
        event_type,
        object_type,
        object_id,
        metadata_json
    ) VALUES (
        p_circle_id,
        p_user_id,
        'CARE_NETWORK_EXPORTED',
        'care_network_export',
        v_export_id,
        jsonb_build_object(
            'patient_id', p_patient_id,
            'included_types', p_included_types,
            'provider_count', v_provider_count,
            'share_link_created', p_create_share_link
        )
    );

    RETURN jsonb_build_object(
        'export_id', v_export_id,
        'content', v_content,
        'share_link', v_share_link_result
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- C2: check_user_ai_consent - use auth.uid()
-- ============================================================================

-- New overload that uses auth.uid() directly (for client calls)
CREATE OR REPLACE FUNCTION check_user_ai_consent()
RETURNS boolean AS $$
DECLARE
    v_enabled boolean;
    v_caller uuid := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RETURN false;
    END IF;

    SELECT ai_processing_enabled INTO v_enabled
    FROM user_ai_consent
    WHERE user_id = v_caller;

    -- Default to false if no record exists
    RETURN COALESCE(v_enabled, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION check_user_ai_consent() TO authenticated;

-- Keep old overload for Edge Function compatibility but add auth check
CREATE OR REPLACE FUNCTION check_user_ai_consent(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
    v_enabled boolean;
BEGIN
    -- If auth context exists, user can only check their own consent
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Cannot check consent for another user';
    END IF;

    SELECT ai_processing_enabled INTO v_enabled
    FROM user_ai_consent
    WHERE user_id = p_user_id;

    RETURN COALESCE(v_enabled, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION check_user_ai_consent(uuid) TO authenticated;
