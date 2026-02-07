# Feature Spec 17 — Respite Care Finder

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 5 (Expansion)
> Differentiator: Directly addresses caregiver burnout with actionable solutions

---

## 1. Problem Statement

Caregivers desperately need breaks but don't know how to find help. "Respite care" is a term many don't know, and even those who do face fragmented information: adult day programs, in-home respite, overnight facilities, volunteer programs. Finding options, understanding costs, and booking requires hours of research at exactly the moment caregivers have no time.

A Respite Care Finder brings local options into CuraKnot with ratings, availability, and booking integration where possible. This transforms CuraKnot from a documentation tool into an action-enabling platform.

---

## 2. Differentiation and Moat

- **Directly addresses burnout** — the #1 reason caregivers abandon apps
- **Curated local directory** — quality over quantity, with reviews
- **Booking integration** — reduces friction from research to relief
- **Care continuity** — share patient info with respite providers
- **Premium lever:** Priority booking, extended respite coverage analytics

---

## 3. Goals

- [ ] G1: Searchable directory of local respite care options
- [ ] G2: Filter by type, availability, cost, and services
- [ ] G3: User reviews and ratings from circle members
- [ ] G4: Contact integration (call, email, website)
- [ ] G5: Booking integration where providers support it
- [ ] G6: Share relevant patient info with selected providers

---

## 4. Non-Goals

- [ ] NG1: No payment processing in v1
- [ ] NG2: No insurance verification
- [ ] NG3: No quality certification/accreditation verification
- [ ] NG4: No nationwide directory (start with major metros)

---

## 5. UX Flow

### 5.1 Respite Care Discovery

```
┌─────────────────────────────────┐
│ 💆 Find Respite Care            │
│ ═══════════════════════════════│
│                                 │
│ Take a break. You deserve it.   │
│                                 │
│ What type of care?              │
│ [All Types           ▼]        │
│                                 │
│ When do you need it?            │
│ [This Week           ▼]        │
│                                 │
│ Location:                       │
│ [📍 Within 15 miles    ▼]      │
│                                 │
│ [Search]                        │
│                                 │
│ ─── Popular Near You ─────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🏠 Comfort Care Adult Day   │ │
│ │ ⭐ 4.8 (23 reviews)         │ │
│ │ Adult Day Program           │ │
│ │ 2.3 miles · $85/day         │ │
│ │ [View] [Call]               │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 👤 Home Instead             │ │
│ │ ⭐ 4.6 (45 reviews)         │ │
│ │ In-Home Respite             │ │
│ │ Serves your area · $28/hr   │ │
│ │ [View] [Call]               │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

### 5.2 Provider Detail

```
┌─────────────────────────────────┐
│ ← Comfort Care Adult Day        │
│ ═══════════════════════════════│
│                                 │
│ ┌─────────────────────────────┐ │
│ │      [Provider Photo]       │ │
│ └─────────────────────────────┘ │
│                                 │
│ ⭐ 4.8 (23 reviews)             │
│ Adult Day Program               │
│                                 │
│ 📍 456 Care Center Drive        │
│    2.3 miles from home          │
│                                 │
│ 💰 $85/day (scholarships avail) │
│                                 │
│ ⏰ Mon-Fri 7:00 AM - 6:00 PM    │
│                                 │
│ ─── Services ─────────────────│
│ ✓ Meals included                │
│ ✓ Activities & socialization    │
│ ✓ Medication management         │
│ ✓ Transportation available      │
│ ✓ Dementia care program         │
│                                 │
│ ─── From CuraKnot Users ──────│
│                                 │
│ "Mom loves the art activities.  │
│  Staff is patient and kind."    │
│  — Jane, 3 months ago           │
│                                 │
│ [📞 Call] [✉️ Email] [🌐 Website]│
│                                 │
│ [Request Availability]          │
│ [Share Patient Info]            │
└─────────────────────────────────┘
```

### 5.3 Request Availability

```
┌─────────────────────────────────┐
│ Request Availability            │
│ Comfort Care Adult Day          │
│ ═══════════════════════════════│
│                                 │
│ Patient:                        │
│ [Mom (Margaret)          ▼]    │
│                                 │
│ Dates needed:                   │
│ [Feb 17-21, 2026 (5 days) ▼]   │
│                                 │
│ Special considerations:         │
│ ┌─────────────────────────────┐ │
│ │ Mom has mild dementia and   │ │
│ │ needs help with meals. She  │ │
│ │ enjoys music and crafts.    │ │
│ └─────────────────────────────┘ │
│                                 │
│ Include from Care Binder:       │
│ [✓] Medication list             │
│ [✓] Emergency contacts          │
│ [✓] Dietary restrictions        │
│ [ ] Full care summary           │
│                                 │
│ Your contact preference:        │
│ (●) Phone: (555) 123-4567       │
│ (○) Email: jane@email.com       │
│                                 │
│ [Send Request]                  │
└─────────────────────────────────┘
```

### 5.4 My Respite History

```
┌─────────────────────────────────┐
│ My Respite Care                 │
│ ═══════════════════════════════│
│                                 │
│ ─── Upcoming ─────────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Feb 17-21                   │ │
│ │ Comfort Care Adult Day      │ │
│ │ 5 days · Mom                │ │
│ │ Status: Confirmed ✓         │ │
│ │ [View Details] [Cancel]     │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── Past ─────────────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Jan 10-12                   │ │
│ │ Home Instead (In-Home)      │ │
│ │ 3 days · Mom                │ │
│ │ [Leave Review]              │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── Respite This Year ────────│
│ Total days: 8                   │
│ Recommended: 24+ days/year      │
│ [Find More Respite]             │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Provider Directory

- [ ] Search by location (radius from home)
- [ ] Filter by respite type (adult day, in-home, overnight, etc.)
- [ ] Filter by services (dementia care, mobility assistance, etc.)
- [ ] Display pricing (where available)
- [ ] Show availability calendar (where integrated)
- [ ] User-submitted providers

### 6.2 Respite Types

| Type      | Description                       | Typical Duration |
| --------- | --------------------------------- | ---------------- |
| Adult Day | Daytime programs at facilities    | Day              |
| In-Home   | Caregiver comes to patient's home | Hours to days    |
| Overnight | Short-term residential stay       | Days to weeks    |
| Volunteer | Community/faith-based programs    | Hours            |
| Emergency | Crisis respite for urgent needs   | Hours to days    |

### 6.3 Reviews & Ratings

- [ ] Circle members can leave reviews
- [ ] Rate on multiple dimensions (staff, cleanliness, activities)
- [ ] Reviews tied to verified CuraKnot users
- [ ] Flag inappropriate reviews

### 6.4 Booking Integration

- [ ] Request availability form
- [ ] Share selected patient info securely
- [ ] Track request status
- [ ] Confirmation notifications
- [ ] Calendar integration for confirmed respite

### 6.5 Respite Tracking

- [ ] Log respite days used
- [ ] Track by provider and type
- [ ] Annual respite goal/recommendation
- [ ] Remind caregivers to take breaks

---

## 7. Data Model

### 7.1 Respite Providers

```sql
CREATE TABLE IF NOT EXISTS respite_providers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Provider info
    name text NOT NULL,
    provider_type text NOT NULL,  -- ADULT_DAY | IN_HOME | OVERNIGHT | VOLUNTEER | EMERGENCY
    description text,

    -- Location
    address text,
    city text NOT NULL,
    state text NOT NULL,
    zip_code text,
    latitude decimal(10, 8),
    longitude decimal(11, 8),
    service_radius_miles int,  -- For in-home providers

    -- Contact
    phone text,
    email text,
    website text,

    -- Hours
    hours_json jsonb,  -- {"monday": "7:00-18:00", ...}

    -- Pricing
    pricing_model text,  -- HOURLY | DAILY | WEEKLY
    price_min decimal(10, 2),
    price_max decimal(10, 2),
    accepts_medicaid boolean DEFAULT false,
    accepts_medicare boolean DEFAULT false,
    scholarships_available boolean DEFAULT false,

    -- Services
    services_json jsonb,  -- ["meals", "transportation", "dementia_care"]

    -- Verification
    verification_status text NOT NULL DEFAULT 'UNVERIFIED',  -- UNVERIFIED | VERIFIED | FEATURED
    verified_at timestamptz,

    -- Metrics
    avg_rating decimal(2, 1),
    review_count int NOT NULL DEFAULT 0,

    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_respite_providers_location ON respite_providers(city, state);
CREATE INDEX idx_respite_providers_type ON respite_providers(provider_type);
CREATE INDEX idx_respite_providers_geo ON respite_providers(latitude, longitude);
```

### 7.2 Provider Reviews

```sql
CREATE TABLE IF NOT EXISTS respite_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id uuid NOT NULL REFERENCES respite_providers(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,

    -- Review
    overall_rating int NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),
    staff_rating int CHECK (staff_rating BETWEEN 1 AND 5),
    cleanliness_rating int CHECK (cleanliness_rating BETWEEN 1 AND 5),
    activities_rating int CHECK (activities_rating BETWEEN 1 AND 5),

    review_text text,

    -- Status
    status text NOT NULL DEFAULT 'PUBLISHED',  -- PUBLISHED | FLAGGED | REMOVED

    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(provider_id, user_id)
);
```

### 7.3 Respite Requests

```sql
CREATE TABLE IF NOT EXISTS respite_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    provider_id uuid NOT NULL REFERENCES respite_providers(id),
    created_by uuid NOT NULL,

    -- Request details
    start_date date NOT NULL,
    end_date date NOT NULL,
    special_considerations text,

    -- Shared info
    share_medications boolean NOT NULL DEFAULT false,
    share_contacts boolean NOT NULL DEFAULT false,
    share_dietary boolean NOT NULL DEFAULT false,
    share_full_summary boolean NOT NULL DEFAULT false,

    -- Contact preference
    contact_method text NOT NULL,  -- PHONE | EMAIL
    contact_value text NOT NULL,

    -- Status
    status text NOT NULL DEFAULT 'PENDING',  -- PENDING | CONFIRMED | DECLINED | CANCELLED
    provider_response text,
    responded_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.4 Respite Log

```sql
CREATE TABLE IF NOT EXISTS respite_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    provider_id uuid REFERENCES respite_providers(id),

    -- Log entry
    start_date date NOT NULL,
    end_date date NOT NULL,
    provider_name text NOT NULL,  -- Stored for history even if provider deleted
    provider_type text NOT NULL,

    -- Notes
    notes text,

    -- Review prompt
    review_prompted boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_respite_log_circle ON respite_log(circle_id, start_date DESC);
```

---

## 8. RLS & Security

- [ ] respite_providers: Readable by all authenticated users
- [ ] respite_reviews: Readable by all; writable by authenticated users
- [ ] respite_requests: Readable/writable by circle members
- [ ] respite_log: Readable/writable by circle members
- [ ] Shared patient info only sent with explicit consent

---

## 9. Edge Functions

### 9.1 search-respite-providers

```typescript
// POST /functions/v1/search-respite-providers

interface SearchRequest {
  latitude: number;
  longitude: number;
  radiusMiles: number;
  providerType?: string;
  services?: string[];
  minRating?: number;
}

interface SearchResponse {
  providers: {
    id: string;
    name: string;
    providerType: string;
    distance: number;
    avgRating: number;
    reviewCount: number;
    priceRange: string;
  }[];
  totalCount: number;
}
```

### 9.2 submit-respite-request

```typescript
// POST /functions/v1/submit-respite-request

interface SubmitRequestRequest {
  providerId: string;
  patientId: string;
  startDate: string;
  endDate: string;
  specialConsiderations?: string;
  shareInfo: {
    medications: boolean;
    contacts: boolean;
    dietary: boolean;
    fullSummary: boolean;
  };
  contactMethod: "PHONE" | "EMAIL";
  contactValue: string;
}

interface SubmitRequestResponse {
  requestId: string;
  status: string;
}
```

### 9.3 prompt-respite-reminders (Cron)

```typescript
// Runs weekly
// Reminds caregivers to take breaks

async function promptRespiteReminders(): Promise<{
  remindersSent: number;
}>;
```

---

## 10. iOS Implementation Notes

### 10.1 Respite Finder View

```swift
struct RespiteFinderView: View {
    @StateObject private var viewModel = RespiteFinderViewModel()
    @State private var searchRadius = 15.0
    @State private var selectedType: RespiteType?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Encouraging header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Take a Break")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("You deserve it. Finding respite care helps you stay strong for your loved one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(12)

                    // Filters
                    VStack(spacing: 12) {
                        Picker("Type", selection: $selectedType) {
                            Text("All Types").tag(nil as RespiteType?)
                            ForEach(RespiteType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type as RespiteType?)
                            }
                        }

                        HStack {
                            Text("Within \(Int(searchRadius)) miles")
                            Slider(value: $searchRadius, in: 5...50, step: 5)
                        }
                    }
                    .padding()

                    // Results
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.providers) { provider in
                            NavigationLink(value: provider) {
                                ProviderCard(provider: provider)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Find Respite Care")
            .navigationDestination(for: RespiteProvider.self) { provider in
                ProviderDetailView(provider: provider)
            }
            .task {
                await viewModel.search(radius: searchRadius, type: selectedType)
            }
        }
    }
}
```

### 10.2 Provider Card

```swift
struct ProviderCard: View {
    let provider: RespiteProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: provider.type.icon)
                    .foregroundStyle(.blue)
                Text(provider.name)
                    .font(.headline)
                Spacer()
            }

            HStack {
                RatingStars(rating: provider.avgRating)
                Text("(\(provider.reviewCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(provider.type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                if let distance = provider.distance {
                    Text("\(String(format: "%.1f", distance)) miles")
                }
                if let priceRange = provider.priceRange {
                    Text("·")
                    Text(priceRange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}
```

### 10.3 Respite Request Sheet

```swift
struct RespiteRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RespiteRequestViewModel
    let provider: RespiteProvider

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PatientPicker(selection: $viewModel.selectedPatient)

                    DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $viewModel.endDate, displayedComponents: .date)
                }

                Section("Special Considerations") {
                    TextEditor(text: $viewModel.specialConsiderations)
                        .frame(minHeight: 100)
                }

                Section("Share from Care Binder") {
                    Toggle("Medication list", isOn: $viewModel.shareMedications)
                    Toggle("Emergency contacts", isOn: $viewModel.shareContacts)
                    Toggle("Dietary restrictions", isOn: $viewModel.shareDietary)
                    Toggle("Full care summary", isOn: $viewModel.shareFullSummary)
                }

                Section("How should they contact you?") {
                    Picker("Contact Method", selection: $viewModel.contactMethod) {
                        Text("Phone").tag(ContactMethod.phone)
                        Text("Email").tag(ContactMethod.email)
                    }
                    .pickerStyle(.segmented)

                    TextField("Contact", text: $viewModel.contactValue)
                }
            }
            .navigationTitle("Request Availability")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Request") {
                        viewModel.submitRequest()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}
```

---

## 11. Metrics

| Metric                | Target          | Measurement                 |
| --------------------- | --------------- | --------------------------- |
| Respite finder usage  | 30% of circles  | Circles that search         |
| Requests submitted    | 20% of searches | Requests / searches         |
| Confirmed bookings    | 50% of requests | Confirmed / submitted       |
| Respite days per year | 12+ days        | Average per caregiver       |
| Provider review rate  | 30%             | Reviews / completed respite |

---

## 12. Risks & Mitigations

| Risk                    | Impact | Mitigation                         |
| ----------------------- | ------ | ---------------------------------- |
| Provider data freshness | High   | Regular verification; user reports |
| Liability concerns      | High   | Clear disclaimers; no guarantees   |
| Low provider coverage   | Medium | Start with major metros; grow      |
| Booking integration     | Medium | Manual request fallback            |

---

## 13. Dependencies

- Location services
- Provider data partnerships/curation
- Maps integration for distance
- Calendar sync (for confirmed respite)

---

## 14. Testing Requirements

- [ ] Unit tests for search filtering
- [ ] Integration tests for request flow
- [ ] Location-based search testing
- [ ] UI tests for discovery flow

---

## 15. Rollout Plan

1. **Alpha:** Directory search; provider details
2. **Beta:** Reviews; request flow
3. **GA:** Booking confirmations; respite tracking
4. **Post-GA:** Provider partnerships; availability calendars

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI + MapKit
- Baseline: `./CuraKnot-spec.md`
- Related: Caregiver Wellness, Calendar Sync
