-- Migration: 0010_emergency_card
-- Description: Emergency Card - offline-accessible critical info with QR sharing
-- Date: 2026-01-29

-- ============================================================================
-- TABLE: emergency_cards
-- ============================================================================

CREATE TABLE emergency_cards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    config_json jsonb NOT NULL DEFAULT '{
        "include_name": true,
        "include_dob": false,
        "include_blood_type": false,
        "include_allergies": true,
        "include_conditions": true,
        "include_medications": true,
        "include_emergency_contacts": true,
        "include_physician": true,
        "include_insurance": false,
        "include_notes": false
    }'::jsonb,
    snapshot_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    version int DEFAULT 1 NOT NULL,
    last_synced_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT emergency_cards_unique UNIQUE (circle_id, patient_id)
);

CREATE INDEX emergency_cards_circle_id_idx ON emergency_cards(circle_id);
CREATE INDEX emergency_cards_patient_id_idx ON emergency_cards(patient_id);

CREATE TRIGGER emergency_cards_updated_at
    BEFORE UPDATE ON emergency_cards
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE emergency_cards IS 'Emergency cards with configurable info for offline/QR access';

-- ============================================================================
-- TABLE: emergency_card_fields (Custom fields)
-- ============================================================================

CREATE TABLE emergency_card_fields (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_card_id uuid NOT NULL REFERENCES emergency_cards(id) ON DELETE CASCADE,
    field_key text NOT NULL,
    field_label text NOT NULL,
    field_value text NOT NULL,
    display_order int DEFAULT 0 NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    
    CONSTRAINT emergency_card_fields_unique UNIQUE (emergency_card_id, field_key)
);

CREATE INDEX emergency_card_fields_card_idx ON emergency_card_fields(emergency_card_id);

COMMENT ON TABLE emergency_card_fields IS 'Custom fields for emergency cards';

-- ============================================================================
-- FUNCTION: generate_emergency_card_snapshot
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_emergency_card_snapshot(
    p_card_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_card emergency_cards%ROWTYPE;
    v_patient patients%ROWTYPE;
    v_config jsonb;
    v_snapshot jsonb;
    v_allergies jsonb;
    v_conditions jsonb;
    v_medications jsonb;
    v_contacts jsonb;
    v_custom_fields jsonb;
BEGIN
    -- Get card
    SELECT * INTO v_card FROM emergency_cards WHERE id = p_card_id;
    IF v_card IS NULL THEN
        RETURN jsonb_build_object('error', 'Card not found');
    END IF;
    
    -- Get patient
    SELECT * INTO v_patient FROM patients WHERE id = v_card.patient_id;
    
    v_config := v_card.config_json;
    
    -- Build snapshot based on config
    v_snapshot := jsonb_build_object(
        'generated_at', now(),
        'version', v_card.version + 1
    );
    
    -- Patient info
    IF (v_config->>'include_name')::boolean THEN
        v_snapshot := v_snapshot || jsonb_build_object(
            'name', v_patient.display_name,
            'initials', v_patient.initials
        );
    END IF;
    
    IF (v_config->>'include_dob')::boolean AND v_patient.dob IS NOT NULL THEN
        v_snapshot := v_snapshot || jsonb_build_object('dob', v_patient.dob);
    END IF;
    
    -- Allergies from binder
    IF (v_config->>'include_allergies')::boolean THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'name', bi.title,
            'severity', bi.content_json->>'severity'
        )), '[]'::jsonb)
        INTO v_allergies
        FROM binder_items bi
        WHERE bi.circle_id = v_card.circle_id
          AND bi.patient_id = v_card.patient_id
          AND bi.type = 'NOTE'
          AND bi.content_json->>'category' = 'allergy'
          AND bi.is_active = true;
        
        v_snapshot := v_snapshot || jsonb_build_object('allergies', v_allergies);
    END IF;
    
    -- Conditions from notes
    IF (v_config->>'include_conditions')::boolean THEN
        SELECT COALESCE(jsonb_agg(bi.title), '[]'::jsonb)
        INTO v_conditions
        FROM binder_items bi
        WHERE bi.circle_id = v_card.circle_id
          AND bi.patient_id = v_card.patient_id
          AND bi.type = 'NOTE'
          AND bi.content_json->>'category' = 'condition'
          AND bi.is_active = true;
        
        v_snapshot := v_snapshot || jsonb_build_object('conditions', v_conditions);
    END IF;
    
    -- Active medications
    IF (v_config->>'include_medications')::boolean THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'name', bi.title,
            'dose', bi.content_json->>'dose',
            'schedule', bi.content_json->>'schedule'
        ) ORDER BY bi.title), '[]'::jsonb)
        INTO v_medications
        FROM binder_items bi
        WHERE bi.circle_id = v_card.circle_id
          AND bi.patient_id = v_card.patient_id
          AND bi.type = 'MED'
          AND bi.is_active = true;
        
        v_snapshot := v_snapshot || jsonb_build_object('medications', v_medications);
    END IF;
    
    -- Emergency contacts
    IF (v_config->>'include_emergency_contacts')::boolean THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'name', sub.title,
            'role', sub.content_json->>'role',
            'phone', sub.content_json->>'phone'
        )), '[]'::jsonb)
        INTO v_contacts
        FROM (
            SELECT bi.title, bi.content_json, bi.created_at
            FROM binder_items bi
            WHERE bi.circle_id = v_card.circle_id
              AND bi.patient_id = v_card.patient_id
              AND bi.type = 'CONTACT'
              AND bi.is_active = true
            ORDER BY bi.created_at
            LIMIT 3
        ) sub;

        v_snapshot := v_snapshot || jsonb_build_object('emergency_contacts', v_contacts);
    END IF;
    
    -- Primary physician
    IF (v_config->>'include_physician')::boolean THEN
        SELECT jsonb_build_object(
            'name', bi.title,
            'phone', bi.content_json->>'phone'
        )
        INTO v_contacts
        FROM binder_items bi
        WHERE bi.circle_id = v_card.circle_id
          AND bi.patient_id = v_card.patient_id
          AND bi.type = 'CONTACT'
          AND bi.content_json->>'role' = 'doctor'
          AND bi.is_active = true
        ORDER BY bi.created_at
        LIMIT 1;
        
        IF v_contacts IS NOT NULL THEN
            v_snapshot := v_snapshot || jsonb_build_object('physician', v_contacts);
        END IF;
    END IF;
    
    -- Custom fields
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'label', f.field_label,
        'value', f.field_value
    ) ORDER BY f.display_order), '[]'::jsonb)
    INTO v_custom_fields
    FROM emergency_card_fields f
    WHERE f.emergency_card_id = p_card_id;
    
    IF jsonb_array_length(v_custom_fields) > 0 THEN
        v_snapshot := v_snapshot || jsonb_build_object('custom_fields', v_custom_fields);
    END IF;
    
    -- Update the card
    UPDATE emergency_cards
    SET 
        snapshot_json = v_snapshot,
        version = version + 1,
        last_synced_at = now(),
        updated_at = now()
    WHERE id = p_card_id;
    
    RETURN v_snapshot;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_emergency_card_snapshot IS 'Generate and store emergency card snapshot from binder data';

-- ============================================================================
-- FUNCTION: create_or_update_emergency_card
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
-- RLS POLICIES
-- ============================================================================

ALTER TABLE emergency_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_card_fields ENABLE ROW LEVEL SECURITY;

-- emergency_cards: Circle members can read
CREATE POLICY emergency_cards_select ON emergency_cards
    FOR SELECT USING (is_circle_member(circle_id, auth.uid()));

-- emergency_cards: Contributors+ can insert/update
CREATE POLICY emergency_cards_insert ON emergency_cards
    FOR INSERT WITH CHECK (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

CREATE POLICY emergency_cards_update ON emergency_cards
    FOR UPDATE USING (has_circle_role(circle_id, auth.uid(), 'CONTRIBUTOR'));

-- emergency_card_fields: Based on card access
CREATE POLICY emergency_card_fields_select ON emergency_card_fields
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM emergency_cards c
            WHERE c.id = emergency_card_fields.emergency_card_id
            AND is_circle_member(c.circle_id, auth.uid())
        )
    );

CREATE POLICY emergency_card_fields_insert ON emergency_card_fields
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM emergency_cards c
            WHERE c.id = emergency_card_fields.emergency_card_id
            AND has_circle_role(c.circle_id, auth.uid(), 'CONTRIBUTOR')
        )
    );

CREATE POLICY emergency_card_fields_update ON emergency_card_fields
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM emergency_cards c
            WHERE c.id = emergency_card_fields.emergency_card_id
            AND has_circle_role(c.circle_id, auth.uid(), 'CONTRIBUTOR')
        )
    );

CREATE POLICY emergency_card_fields_delete ON emergency_card_fields
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM emergency_cards c
            WHERE c.id = emergency_card_fields.emergency_card_id
            AND has_circle_role(c.circle_id, auth.uid(), 'CONTRIBUTOR')
        )
    );
