-- ============================================================================
-- Migration: Apple Subscription Sync Function
-- Description: Function to sync Apple StoreKit subscriptions to the backend
-- ============================================================================

-- Function to sync Apple subscription
CREATE OR REPLACE FUNCTION sync_apple_subscription(
    p_plan text,
    p_product_id text,
    p_transaction_id text,
    p_expiration text
)
RETURNS void AS $$
DECLARE
    v_user_id uuid;
    v_expiration timestamptz;
    v_old_plan text;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Parse expiration date
    IF p_expiration != '' THEN
        v_expiration := p_expiration::timestamptz;
    ELSE
        v_expiration := NULL;
    END IF;

    -- Get current plan for event logging
    SELECT plan INTO v_old_plan
    FROM subscriptions
    WHERE user_id = v_user_id;

    -- Upsert subscription
    INSERT INTO subscriptions (
        user_id,
        plan,
        status,
        provider,
        provider_subscription_id,
        provider_product_id,
        current_period_end,
        updated_at
    )
    VALUES (
        v_user_id,
        p_plan,
        'ACTIVE',
        'APPLE',
        p_transaction_id,
        p_product_id,
        v_expiration,
        now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        plan = p_plan,
        status = 'ACTIVE',
        provider = 'APPLE',
        provider_subscription_id = p_transaction_id,
        provider_product_id = p_product_id,
        current_period_end = v_expiration,
        updated_at = now();

    -- Log subscription event
    INSERT INTO subscription_events (
        subscription_id,
        event_type,
        from_plan,
        to_plan,
        provider_event_id,
        metadata_json
    )
    SELECT
        id,
        CASE
            WHEN v_old_plan IS NULL THEN 'CREATED'
            WHEN v_old_plan = p_plan THEN 'RENEWED'
            WHEN (v_old_plan = 'FREE' AND p_plan IN ('PLUS', 'FAMILY')) OR
                 (v_old_plan = 'PLUS' AND p_plan = 'FAMILY') THEN 'UPGRADED'
            ELSE 'DOWNGRADED'
        END,
        COALESCE(v_old_plan, 'FREE'),
        p_plan,
        p_transaction_id,
        jsonb_build_object(
            'product_id', p_product_id,
            'expiration', p_expiration
        )
    FROM subscriptions
    WHERE user_id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's subscription details
CREATE OR REPLACE FUNCTION get_user_subscription()
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid;
    v_result jsonb;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('plan', 'FREE', 'valid_until', NULL);
    END IF;

    SELECT jsonb_build_object(
        'plan', COALESCE(plan, 'FREE'),
        'valid_until', current_period_end,
        'status', status,
        'provider', provider
    ) INTO v_result
    FROM subscriptions
    WHERE user_id = v_user_id
      AND status IN ('ACTIVE', 'TRIALING', 'GRACE_PERIOD');

    RETURN COALESCE(v_result, jsonb_build_object('plan', 'FREE', 'valid_until', NULL));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
