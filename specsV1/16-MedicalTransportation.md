# Feature Spec 16 — Medical Transportation Coordinator

> Date: 2026-02-05 | Priority: LOW | Phase: 5 (Expansion)
> Differentiator: Addresses top-3 caregiving challenge

---

## 1. Problem Statement

Transportation to medical appointments is one of the top three challenges in caregiving. Families coordinate rides among themselves, arrange medical transport services, and often miss appointments due to logistics failures. Currently this coordination happens via text messages, phone calls, and memory.

A transportation coordinator within CuraKnot tracks rides, coordinates pickups among family members, and can integrate with medical transport services like Lyft Healthcare or local paratransit.

---

## 2. Differentiation and Moat

- **Addresses major pain point** — transportation cited in 40%+ of caregiver surveys
- **Coordinates family rides** — distributes burden fairly
- **Integrates with medical transport** — one-tap booking (where available)
- **Prevents missed appointments** — reminders and confirmations
- **Premium lever:** Transport service integration, analytics, recurring rides

---

## 3. Goals

- [ ] G1: Track scheduled transportation for appointments
- [ ] G2: Coordinate who's driving among circle members
- [ ] G3: Send ride reminders to drivers and patients
- [ ] G4: Directory of local medical transport options
- [ ] G5: Integration with ride-share medical transport (Phase 2)
- [ ] G6: Analytics on ride distribution and coverage

---

## 4. Non-Goals

- [ ] NG1: No booking/payment processing in v1
- [ ] NG2: No real-time ride tracking
- [ ] NG3: No insurance billing for transport
- [ ] NG4: No ambulance/emergency transport coordination

---

## 5. UX Flow

### 5.1 Transportation Calendar

```
┌─────────────────────────────────┐
│ 🚗 Transportation               │
│ ═══════════════════════════════│
│                                 │
│ [+ Schedule Ride]               │
│                                 │
│ ─── This Week ─────────────────│
│                                 │
│ Mon, Feb 10                     │
│ ┌─────────────────────────────┐ │
│ │ 🏥 Dr. Smith - Cardiology   │ │
│ │ 📍 123 Medical Center Dr    │ │
│ │ ⏰ Pickup: 9:30 AM          │ │
│ │ 🚗 Driver: Jane             │ │
│ │ ✅ Confirmed                │ │
│ └─────────────────────────────┘ │
│                                 │
│ Wed, Feb 12                     │
│ ┌─────────────────────────────┐ │
│ │ 🏥 Physical Therapy         │ │
│ │ 📍 456 Rehab Way            │ │
│ │ ⏰ Pickup: 2:00 PM          │ │
│ │ 🚗 Driver: Needed!          │ │
│ │ ⚠️ Not confirmed            │ │
│ │                             │ │
│ │ [Volunteer] [Find Service]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── Coming Up ─────────────────│
│ [...]                           │
└─────────────────────────────────┘
```

### 5.2 Schedule Ride

```
┌─────────────────────────────────┐
│ Schedule a Ride                 │
│ ═══════════════════════════════│
│                                 │
│ Appointment:                    │
│ [Dr. Smith - Cardiology   ▼]    │
│ (or enter manually)             │
│                                 │
│ Pickup Location:                │
│ [Home                      ▼]   │
│ [123 Oak Street, Apt 4B   ]     │
│                                 │
│ Destination:                    │
│ [456 Medical Center Dr    ]     │
│                                 │
│ Pickup Time:                    │
│ [Feb 10, 2026 at 9:30 AM  ▼]    │
│                                 │
│ Return Ride Needed?             │
│ [✓] Yes, estimate: 11:00 AM     │
│                                 │
│ Special Needs:                  │
│ [ ] Wheelchair accessible       │
│ [ ] Stretcher transport         │
│ [ ] Oxygen equipment            │
│                                 │
│ [Save & Find Driver]            │
└─────────────────────────────────┘
```

### 5.3 Driver Assignment

```
┌─────────────────────────────────┐
│ Who Can Drive?                  │
│ Feb 10 · Dr. Smith              │
│ ═══════════════════════════════│
│                                 │
│ Circle Members:                 │
│ ┌─────────────────────────────┐ │
│ │ Jane (you)                  │ │
│ │ Rides given: 8 this month   │ │
│ │ [I'll Drive]                │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ Mike                        │ │
│ │ Rides given: 2 this month   │ │
│ │ [Ask Mike]                  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── Or ────────────────────────│
│                                 │
│ External Services:              │
│ [Find Medical Transport]        │
│ [Local Paratransit Info]        │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Ride Management

- [ ] Create rides linked to appointments or standalone
- [ ] Track pickup/destination addresses
- [ ] Support round-trip rides
- [ ] Special needs flags (wheelchair, oxygen, etc.)
- [ ] Recurring ride support

### 6.2 Driver Coordination

- [ ] Circle members can volunteer
- [ ] Request specific member to drive
- [ ] Track ride counts per member (fairness)
- [ ] Driver confirmation workflow
- [ ] Backup driver assignment

### 6.3 Reminders

- [ ] Reminder to patient (day before, morning of)
- [ ] Reminder to driver (day before, hour before)
- [ ] Confirmation request to driver
- [ ] Alert if ride unconfirmed 24h before

### 6.4 Transport Services Directory

- [ ] Curated list of local medical transport options
- [ ] Contact information and hours
- [ ] Service types (wheelchair, stretcher, etc.)
- [ ] User can add local services

### 6.5 Analytics (Premium)

- [ ] Rides per member per month
- [ ] Missed rides tracking
- [ ] Coverage gaps identification
- [ ] Fair distribution suggestions

---

## 7. Data Model

### 7.1 Scheduled Rides

```sql
CREATE TABLE IF NOT EXISTS scheduled_rides (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Ride details
    purpose text NOT NULL,
    appointment_id uuid,  -- Link to binder appointment if exists
    pickup_address text NOT NULL,
    pickup_time timestamptz NOT NULL,
    destination_address text NOT NULL,
    destination_name text,

    -- Return ride
    needs_return boolean NOT NULL DEFAULT false,
    return_time timestamptz,

    -- Special needs
    wheelchair_accessible boolean NOT NULL DEFAULT false,
    stretcher_required boolean NOT NULL DEFAULT false,
    oxygen_required boolean NOT NULL DEFAULT false,
    other_needs text,

    -- Driver
    driver_type text NOT NULL DEFAULT 'FAMILY',  -- FAMILY | EXTERNAL_SERVICE
    driver_user_id uuid,
    external_service_name text,
    confirmation_status text NOT NULL DEFAULT 'UNCONFIRMED',  -- UNCONFIRMED | CONFIRMED | DECLINED

    -- Status
    status text NOT NULL DEFAULT 'SCHEDULED',  -- SCHEDULED | COMPLETED | CANCELLED | MISSED

    -- Recurrence
    recurrence_rule text,
    parent_ride_id uuid REFERENCES scheduled_rides(id),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_scheduled_rides_patient ON scheduled_rides(patient_id, pickup_time);
CREATE INDEX idx_scheduled_rides_driver ON scheduled_rides(driver_user_id, pickup_time);
```

### 7.2 Transport Services

```sql
CREATE TABLE IF NOT EXISTS transport_services (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid REFERENCES circles(id) ON DELETE CASCADE,  -- NULL for system-wide

    -- Service info
    name text NOT NULL,
    service_type text NOT NULL,  -- PARATRANSIT | MEDICAL_TRANSPORT | RIDESHARE | VOLUNTEER
    phone text,
    website text,
    hours text,
    service_area text,

    -- Capabilities
    wheelchair_accessible boolean NOT NULL DEFAULT false,
    stretcher_available boolean NOT NULL DEFAULT false,
    oxygen_allowed boolean NOT NULL DEFAULT false,

    -- Notes
    notes text,
    is_active boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.3 Ride Statistics

```sql
CREATE TABLE IF NOT EXISTS ride_statistics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    month date NOT NULL,  -- First of month

    rides_given int NOT NULL DEFAULT 0,
    rides_scheduled int NOT NULL DEFAULT 0,
    rides_cancelled int NOT NULL DEFAULT 0,

    UNIQUE(circle_id, user_id, month)
);
```

---

## 8. RLS & Security

- [ ] scheduled_rides: Readable by circle members; writable by contributors+
- [ ] transport_services: System services readable by all; circle services by circle members
- [ ] ride_statistics: Readable by circle members

---

## 9. Edge Functions

### 9.1 send-ride-reminders (Cron)

```typescript
// Runs hourly
// Sends reminders for upcoming rides

async function sendRideReminders(): Promise<{
  remindersSent: number;
  alertsSent: number; // For unconfirmed rides
}>;
```

### 9.2 update-ride-statistics (Cron)

```typescript
// Runs daily
// Updates ride counts per member

async function updateRideStatistics(): Promise<void>;
```

---

## 10. iOS Implementation Notes

### 10.1 Transportation View

```swift
struct TransportationView: View {
    @StateObject private var viewModel = TransportationViewModel()
    @State private var showingScheduleRide = false

    var body: some View {
        NavigationStack {
            List {
                // Unconfirmed rides alert
                if !viewModel.unconfirmedRides.isEmpty {
                    Section {
                        ForEach(viewModel.unconfirmedRides) { ride in
                            UnconfirmedRideAlert(ride: ride)
                        }
                    } header: {
                        Label("Needs Driver", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                // Upcoming rides
                ForEach(viewModel.upcomingRidesGrouped, id: \.date) { group in
                    Section(group.dateHeader) {
                        ForEach(group.rides) { ride in
                            RideRow(ride: ride)
                        }
                    }
                }
            }
            .navigationTitle("Transportation")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Schedule Ride", systemImage: "plus") {
                        showingScheduleRide = true
                    }
                }
            }
            .sheet(isPresented: $showingScheduleRide) {
                ScheduleRideSheet()
            }
        }
    }
}
```

### 10.2 Ride Row

```swift
struct RideRow: View {
    let ride: ScheduledRide

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(.blue)
                Text(ride.purpose)
                    .font(.headline)
                Spacer()
                ConfirmationBadge(status: ride.confirmationStatus)
            }

            HStack {
                Image(systemName: "mappin")
                    .foregroundStyle(.secondary)
                Text(ride.destinationName ?? ride.destinationAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("Pickup: \(ride.pickupTime, style: .time)")
                    .font(.subheadline)
            }

            HStack {
                Image(systemName: "car")
                    .foregroundStyle(.secondary)
                if let driver = ride.driverName {
                    Text("Driver: \(driver)")
                        .font(.subheadline)
                } else {
                    Text("Driver: Needed!")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            // Special needs badges
            if ride.hasSpecialNeeds {
                HStack {
                    if ride.wheelchairAccessible {
                        Badge("Wheelchair", systemImage: "figure.roll")
                    }
                    if ride.oxygenRequired {
                        Badge("Oxygen", systemImage: "lungs")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

---

## 11. Metrics

| Metric                       | Target         | Measurement                   |
| ---------------------------- | -------------- | ----------------------------- |
| Transportation adoption      | 20% of circles | Circles with ≥1 ride          |
| Ride confirmation rate       | 90%            | Confirmed / scheduled         |
| Missed ride rate             | <5%            | Missed / scheduled            |
| Driver distribution fairness | Gini < 0.3     | Ride distribution coefficient |
| External service usage       | 15% of rides   | External / total rides        |

---

## 12. Risks & Mitigations

| Risk                        | Impact | Mitigation                         |
| --------------------------- | ------ | ---------------------------------- |
| Ride coordination failures  | High   | Multiple reminders; backup drivers |
| Driver burden imbalance     | Medium | Fair distribution analytics        |
| External service complexity | Medium | Start with directory only          |
| Address accuracy            | Medium | Use Maps integration; verify       |

---

## 13. Dependencies

- Calendar sync (for appointment linking)
- Push notifications
- Maps integration (addresses)
- Task system (for ride reminders)

---

## 14. Testing Requirements

- [ ] Unit tests for ride scheduling logic
- [ ] Unit tests for statistics calculation
- [ ] Integration tests for reminders
- [ ] UI tests for scheduling flow

---

## 15. Rollout Plan

1. **Alpha:** Basic ride scheduling
2. **Beta:** Driver coordination; reminders
3. **GA:** Transport directory; statistics
4. **Post-GA:** Ride-share integration; booking

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI + Maps
- Baseline: `./CuraKnot-spec.md`
- Related: Calendar Sync, Binder Appointments, Tasks
