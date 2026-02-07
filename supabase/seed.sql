-- Seed data for local development
-- Run with: supabase db reset (which runs migrations + seed)

-- ============================================================================
-- TEST USERS
-- ============================================================================

-- Note: In production, users are created via Supabase Auth
-- For local dev, we create them directly

INSERT INTO users (id, email, display_name, apple_sub) VALUES
    ('00000000-0000-0000-0000-000000000001', 'alice@example.com', 'Alice Johnson', 'apple_alice'),
    ('00000000-0000-0000-0000-000000000002', 'bob@example.com', 'Bob Smith', 'apple_bob'),
    ('00000000-0000-0000-0000-000000000003', 'carol@example.com', 'Carol Davis', 'apple_carol'),
    ('00000000-0000-0000-0000-000000000004', 'dan@example.com', 'Dan Wilson', 'apple_dan');

-- ============================================================================
-- TEST CIRCLE
-- ============================================================================

INSERT INTO circles (id, name, icon, owner_user_id, plan) VALUES
    ('10000000-0000-0000-0000-000000000001', 'Grandma Care', '🧶', '00000000-0000-0000-0000-000000000001', 'FREE');

-- ============================================================================
-- CIRCLE MEMBERS
-- ============================================================================

INSERT INTO circle_members (circle_id, user_id, role, status, joined_at) VALUES
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'OWNER', 'ACTIVE', now()),
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'ADMIN', 'ACTIVE', now()),
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'CONTRIBUTOR', 'ACTIVE', now()),
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'VIEWER', 'ACTIVE', now());

-- ============================================================================
-- TEST PATIENT
-- ============================================================================

INSERT INTO patients (id, circle_id, display_name, initials, dob, pronouns, notes) VALUES
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Grandma Rose', 'GR', '1940-03-15', 'she/her', 'Lives at Sunny Acres Assisted Living. Room 204.');

-- ============================================================================
-- TEST HANDOFFS
-- ============================================================================

INSERT INTO handoffs (id, circle_id, patient_id, created_by, type, title, summary, keywords, status, published_at, current_revision) VALUES
    ('30000000-0000-0000-0000-000000000001', 
     '10000000-0000-0000-0000-000000000001', 
     '20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001',
     'VISIT',
     'Visit with Dr. Martinez',
     'Visited Dr. Martinez for quarterly checkup. Blood pressure slightly elevated at 145/90. Doctor adjusted Lisinopril dose from 10mg to 15mg. Ordered blood work for next week.',
     ARRAY['blood pressure', 'lisinopril', 'checkup', 'dr martinez'],
     'PUBLISHED',
     now() - interval '2 days',
     1),
    
    ('30000000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000002',
     'CALL',
     'Call from Sunny Acres',
     'Received call from facility nurse. Grandma had a minor fall yesterday evening but no injury. They''re monitoring her more closely. Suggest we visit tomorrow to check in.',
     ARRAY['fall', 'sunny acres', 'monitoring'],
     'PUBLISHED',
     now() - interval '1 day',
     1);

-- ============================================================================
-- HANDOFF REVISIONS
-- ============================================================================

INSERT INTO handoff_revisions (handoff_id, revision, structured_json, edited_by) VALUES
    ('30000000-0000-0000-0000-000000000001', 1, '{
        "handoff_id": "30000000-0000-0000-0000-000000000001",
        "title": "Visit with Dr. Martinez",
        "summary": "Visited Dr. Martinez for quarterly checkup. Blood pressure slightly elevated at 145/90. Doctor adjusted Lisinopril dose from 10mg to 15mg. Ordered blood work for next week.",
        "status": {
            "mood_energy": "Good spirits, a bit tired",
            "pain": 2,
            "appetite": "Normal",
            "sleep": "6 hours",
            "mobility": "Using walker",
            "safety_flags": []
        },
        "changes": {
            "med_changes": [{
                "name": "Lisinopril",
                "change": "DOSE",
                "details": "Increased from 10mg to 15mg",
                "effective": "2026-01-27"
            }],
            "symptom_changes": [{
                "symptom": "Blood pressure",
                "details": "Slightly elevated at 145/90"
            }],
            "care_plan_changes": []
        },
        "questions_for_clinician": [],
        "next_steps": [{
            "action": "Schedule blood work",
            "due": "2026-02-03T10:00:00Z",
            "priority": "MED"
        }, {
            "action": "Pick up new Lisinopril prescription",
            "due": "2026-01-28T17:00:00Z",
            "priority": "HIGH"
        }],
        "keywords": ["blood pressure", "lisinopril", "checkup", "dr martinez"],
        "revision": 1
    }'::jsonb, '00000000-0000-0000-0000-000000000001'),
    
    ('30000000-0000-0000-0000-000000000002', 1, '{
        "handoff_id": "30000000-0000-0000-0000-000000000002",
        "title": "Call from Sunny Acres",
        "summary": "Received call from facility nurse. Grandma had a minor fall yesterday evening but no injury. They are monitoring her more closely. Suggest we visit tomorrow to check in.",
        "status": {
            "mood_energy": "Unknown - spoke with nurse only",
            "pain": null,
            "appetite": null,
            "sleep": null,
            "mobility": "Fall concern",
            "safety_flags": ["Recent fall"]
        },
        "changes": {
            "med_changes": [],
            "symptom_changes": [],
            "care_plan_changes": []
        },
        "questions_for_clinician": [{
            "question": "Should we request PT evaluation after the fall?",
            "priority": "MED"
        }],
        "next_steps": [{
            "action": "Visit Grandma to assess",
            "due": "2026-01-29T14:00:00Z",
            "priority": "HIGH"
        }, {
            "action": "Call facility for fall incident report",
            "priority": "MED"
        }],
        "keywords": ["fall", "sunny acres", "monitoring"],
        "revision": 1
    }'::jsonb, '00000000-0000-0000-0000-000000000002');

-- ============================================================================
-- READ RECEIPTS
-- ============================================================================

INSERT INTO read_receipts (circle_id, handoff_id, user_id, read_at) VALUES
    ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', now() - interval '2 days'),
    ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', now() - interval '1 day'),
    ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', now() - interval '1 day');

-- ============================================================================
-- TEST TASKS
-- ============================================================================

INSERT INTO tasks (id, circle_id, patient_id, handoff_id, created_by, owner_user_id, title, description, due_at, priority, status) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000002',
     'Pick up new Lisinopril prescription',
     'Dr. Martinez increased dose to 15mg. Prescription sent to CVS on Main St.',
     now() + interval '1 day',
     'HIGH',
     'OPEN'),
    
    ('40000000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000003',
     'Schedule blood work',
     'Dr. Martinez ordered blood work. Call Quest Diagnostics to schedule.',
     now() + interval '5 days',
     'MED',
     'OPEN'),
    
    ('40000000-0000-0000-0000-000000000003',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-000000000001',
     'Visit Grandma to assess after fall',
     'Check in after the minor fall reported by Sunny Acres.',
     now() + interval '1 hour',
     'HIGH',
     'OPEN');

-- ============================================================================
-- BINDER ITEMS
-- ============================================================================

-- Medications
INSERT INTO binder_items (id, circle_id, patient_id, type, title, content_json, is_active, created_by, updated_by) VALUES
    ('50000000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     'MED',
     'Lisinopril',
     '{
        "name": "Lisinopril",
        "dose": "15mg",
        "schedule": "Once daily in the morning",
        "purpose": "Blood pressure control",
        "prescriber": "Dr. Martinez",
        "start_date": "2025-06-15",
        "pharmacy": "CVS - Main Street"
     }'::jsonb,
     true,
     '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001'),
    
    ('50000000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     'MED',
     'Metformin',
     '{
        "name": "Metformin",
        "dose": "500mg",
        "schedule": "Twice daily with meals",
        "purpose": "Type 2 diabetes management",
        "prescriber": "Dr. Martinez",
        "start_date": "2024-01-10",
        "pharmacy": "CVS - Main Street"
     }'::jsonb,
     true,
     '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001');

-- Contacts
INSERT INTO binder_items (id, circle_id, patient_id, type, title, content_json, is_active, created_by, updated_by) VALUES
    ('50000000-0000-0000-0000-000000000003',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     'CONTACT',
     'Dr. Maria Martinez',
     '{
        "name": "Dr. Maria Martinez",
        "role": "doctor",
        "phone": "(555) 123-4567",
        "email": "dr.martinez@clinic.com",
        "organization": "Main Street Medical Clinic",
        "notes": "Primary care physician. Tuesday/Thursday appointments preferred."
     }'::jsonb,
     true,
     '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001'),
    
    ('50000000-0000-0000-0000-000000000004',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     'CONTACT',
     'Sunny Acres Main Desk',
     '{
        "name": "Sunny Acres Main Desk",
        "role": "other",
        "phone": "(555) 987-6543",
        "organization": "Sunny Acres Assisted Living",
        "notes": "Ask for nursing station for health updates"
     }'::jsonb,
     true,
     '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001');

-- Facility
INSERT INTO binder_items (id, circle_id, patient_id, type, title, content_json, is_active, created_by, updated_by) VALUES
    ('50000000-0000-0000-0000-000000000005',
     '10000000-0000-0000-0000-000000000001',
     '20000000-0000-0000-0000-000000000001',
     'FACILITY',
     'Sunny Acres Assisted Living',
     '{
        "name": "Sunny Acres Assisted Living",
        "type": "nursing_home",
        "address": "123 Sunshine Boulevard, Springfield, IL 62701",
        "phone": "(555) 987-6543",
        "unit_room": "Room 204, Wing B",
        "visiting_hours": "9am-8pm daily, flexible for family",
        "notes": "Check in at front desk. Parking in rear lot."
     }'::jsonb,
     true,
     '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000001');

-- ============================================================================
-- TEST INVITE (for testing join flow)
-- ============================================================================

INSERT INTO circle_invites (id, circle_id, token, role, created_by, expires_at) VALUES
    ('60000000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     'test-invite-token-123',
     'CONTRIBUTOR',
     '00000000-0000-0000-0000-000000000001',
     now() + interval '7 days');

-- ============================================================================
-- OUTPUT SUMMARY
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=== Seed Data Summary ===';
    RAISE NOTICE 'Users: 4 (Alice=Owner, Bob=Admin, Carol=Contributor, Dan=Viewer)';
    RAISE NOTICE 'Circles: 1 (Grandma Care)';
    RAISE NOTICE 'Patients: 1 (Grandma Rose)';
    RAISE NOTICE 'Handoffs: 2 (Doctor visit, Facility call)';
    RAISE NOTICE 'Tasks: 3 (Prescription, Blood work, Visit)';
    RAISE NOTICE 'Binder Items: 5 (2 meds, 2 contacts, 1 facility)';
    RAISE NOTICE 'Invite Token: test-invite-token-123 (valid 7 days)';
END $$;
