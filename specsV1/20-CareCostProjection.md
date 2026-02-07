# Feature Spec 20 — Care Cost Projection Tool

> Date: 2026-02-05 | Priority: LOW | Phase: 5 (Expansion)
> Differentiator: Financial planning visibility — a major source of caregiver anxiety

---

## 1. Problem Statement

Families are blindsided by care costs. "How long can we afford this?" is a question that keeps caregivers awake at night. The current situation involves no visibility, fragmented costs across multiple providers, and difficulty planning for escalating care needs. When families finally do the math, it's often too late for good options.

A Care Cost Projection tool helps families understand current spending, project future costs based on care trajectory, and make informed decisions about care options before crisis forces their hand.

---

## 2. Differentiation and Moat

- **Addresses major anxiety** — financial stress is a top-3 caregiver concern
- **Proactive planning** — most apps are reactive; this enables foresight
- **Care trajectory awareness** — helps families prepare for what's next
- **Connects to binder data** — leverages existing insurance/billing info
- **Premium lever:** Financial advisor integration, Medicaid planning, cost optimization

---

## 3. Goals

- [ ] G1: Track actual care spending from binder and billing data
- [ ] G2: Estimate monthly care costs at current care level
- [ ] G3: Project costs for different care scenarios (home care vs. facility)
- [ ] G4: Integrate local cost data for care services
- [ ] G5: Provide educational resources on financial planning
- [ ] G6: Connect to financial planning professionals (optional)

---

## 4. Non-Goals

- [ ] NG1: No financial advice (clear disclaimers required)
- [ ] NG2: No investment recommendations
- [ ] NG3: No Medicaid eligibility determination
- [ ] NG4: No direct financial transactions

---

## 5. UX Flow

### 5.1 Cost Overview Dashboard

```
┌─────────────────────────────────┐
│ 💰 Care Costs                   │
│ ═══════════════════════════════│
│                                 │
│ ─── Current Monthly Costs ────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │    $4,850 / month           │ │
│ │    (estimated)              │ │
│ │                             │ │
│ │ ┌───────────────────────┐   │ │
│ │ │ ████████████ Home Care│ $2,400│
│ │ │ ████████ Medications  │ $850│
│ │ │ ████ Medical Supplies │ $400│
│ │ │ ███ Transportation    │ $350│
│ │ │ ██ Other              │ $250│
│ │ │ ██ Insurance Copays   │ $200│
│ │ │ █ Equipment           │ $100│
│ │ └───────────────────────┘   │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Track Actual Spending]         │
│                                 │
│ ─── Coverage Status ──────────│
│                                 │
│ Medicare: Covering 60%          │
│ Secondary: Covering 15%         │
│ Out of Pocket: 25% ($1,212/mo)  │
│                                 │
│ [View Projections →]            │
└─────────────────────────────────┘
```

### 5.2 Care Scenario Projections

```
┌─────────────────────────────────┐
│ Care Cost Projections           │
│ ═══════════════════════════════│
│                                 │
│ Based on current care needs and │
│ local costs in your area.       │
│                                 │
│ ─── Current: Part-Time Home ───│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 20 hrs/week home care       │ │
│ │ $4,850/month                │ │
│ │ $58,200/year                │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── If Needs Increase ────────│
│                                 │
│ Full-Time Home Care (40 hrs)    │
│ ┌─────────────────────────────┐ │
│ │ $7,200/month                │ │
│ │ $86,400/year                │ │
│ │ +$2,350/mo from current     │ │
│ └─────────────────────────────┘ │
│                                 │
│ 24/7 Home Care                  │
│ ┌─────────────────────────────┐ │
│ │ $15,000/month               │ │
│ │ $180,000/year               │ │
│ │ +$10,150/mo from current    │ │
│ └─────────────────────────────┘ │
│                                 │
│ Assisted Living Facility        │
│ ┌─────────────────────────────┐ │
│ │ $5,500/month                │ │
│ │ $66,000/year                │ │
│ │ +$650/mo from current       │ │
│ │ [View facilities near you]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ Memory Care Facility            │
│ ┌─────────────────────────────┐ │
│ │ $8,200/month                │ │
│ │ $98,400/year                │ │
│ │ +$3,350/mo from current     │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Customize Scenarios]           │
└─────────────────────────────────┘
```

### 5.3 Spending Tracker

```
┌─────────────────────────────────┐
│ Track Care Spending             │
│ ═══════════════════════════════│
│                                 │
│ [+ Add Expense]                 │
│                                 │
│ ─── February 2026 ────────────│
│ Total: $4,720                   │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Feb 5 · Home Care Weekly    │ │
│ │ Comfort Keepers             │ │
│ │ $600                        │ │
│ │ [Recurring: Weekly]         │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Feb 3 · Pharmacy            │ │
│ │ CVS - Monthly medications   │ │
│ │ $127.50                     │ │
│ │ [Receipt attached]          │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Feb 1 · Medical Transport   │ │
│ │ Lyft Healthcare             │ │
│ │ $45                         │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── January 2026 ─────────────│
│ Total: $4,950                   │
│ [View Details]                  │
│                                 │
│ [Export for Tax/Records]        │
└─────────────────────────────────┘
```

### 5.4 Financial Planning Resources

```
┌─────────────────────────────────┐
│ Planning Resources              │
│ ═══════════════════════════════│
│                                 │
│ Understanding your options      │
│ can help you plan ahead.        │
│                                 │
│ ─── Coverage Options ─────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🏥 Medicare                 │ │
│ │ What's covered for          │ │
│ │ home health and skilled     │ │
│ │ nursing care.               │ │
│ │ [Learn More]                │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🏛️ Medicaid                 │ │
│ │ Long-term care coverage     │ │
│ │ and eligibility basics.     │ │
│ │ [Learn More]                │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🎖️ VA Benefits              │ │
│ │ Aid & Attendance and        │ │
│ │ other veteran benefits.     │ │
│ │ [Learn More]                │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── Professional Help ────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 👤 Elder Law Attorney       │ │
│ │ Find specialists in         │ │
│ │ Medicaid planning, POA,     │ │
│ │ and asset protection.       │ │
│ │ [Find Near You]             │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📊 Financial Advisor        │ │
│ │ Specialists in long-term    │ │
│ │ care financial planning.    │ │
│ │ [Find Near You]             │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Cost Categories

| Category         | Examples                      | Data Source       |
| ---------------- | ----------------------------- | ----------------- |
| Home Care        | Aides, nurses, companions     | Manual / Billing  |
| Medications      | Prescriptions, OTC            | Binder / Manual   |
| Medical Supplies | Equipment, disposables        | Manual            |
| Transportation   | Rides to appointments         | Manual / Receipts |
| Insurance        | Premiums, copays, deductibles | Binder            |
| Equipment        | Rentals, purchases            | Manual            |
| Facility         | Day programs, respite         | Manual            |
| Professional     | Care managers, advisors       | Manual            |

### 6.2 Cost Estimation

- [ ] Pull insurance info from binder
- [ ] Integrate local cost databases (Genworth, etc.)
- [ ] Adjust for geographic location
- [ ] Factor in typical cost increases (3-5%/year)
- [ ] Compare to national averages

### 6.3 Spending Tracking

- [ ] Manual expense entry
- [ ] Recurring expense support
- [ ] Category assignment
- [ ] Receipt photo attachment
- [ ] Link to binder bills (if exists)
- [ ] Monthly/yearly summaries

### 6.4 Scenario Modeling

- [ ] Current care level baseline
- [ ] Preset scenarios (full-time home, facility, etc.)
- [ ] Custom scenario builder
- [ ] Side-by-side comparison
- [ ] Time-based projections (1yr, 3yr, 5yr)

### 6.5 Resources & Referrals

- [ ] Educational content on coverage options
- [ ] Links to official resources (Medicare.gov, etc.)
- [ ] Professional directory (attorneys, advisors)
- [ ] Local Area Agency on Aging info

---

## 7. Data Model

### 7.1 Care Expenses

```sql
CREATE TABLE IF NOT EXISTS care_expenses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Expense details
    category text NOT NULL,  -- HOME_CARE, MEDICATIONS, SUPPLIES, etc.
    description text NOT NULL,
    vendor_name text,
    amount decimal(10, 2) NOT NULL,
    expense_date date NOT NULL,

    -- Recurrence
    is_recurring boolean NOT NULL DEFAULT false,
    recurrence_rule text,  -- WEEKLY, BIWEEKLY, MONTHLY
    parent_expense_id uuid REFERENCES care_expenses(id),

    -- Coverage
    covered_by_insurance decimal(10, 2) DEFAULT 0,
    out_of_pocket decimal(10, 2),

    -- Attachment
    receipt_storage_key text,

    -- Link to billing
    billing_item_id uuid,  -- Link to billing feature if exists

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_care_expenses_circle ON care_expenses(circle_id, expense_date DESC);
CREATE INDEX idx_care_expenses_category ON care_expenses(circle_id, category, expense_date DESC);
```

### 7.2 Cost Estimates

```sql
CREATE TABLE IF NOT EXISTS care_cost_estimates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,

    -- Estimate details
    scenario_name text NOT NULL,
    scenario_type text NOT NULL,  -- CURRENT | FULL_TIME_HOME | FACILITY | CUSTOM
    is_current boolean NOT NULL DEFAULT false,

    -- Cost breakdown (monthly)
    home_care_hours_weekly int,
    home_care_hourly_rate decimal(10, 2),
    home_care_monthly decimal(10, 2),
    medications_monthly decimal(10, 2),
    supplies_monthly decimal(10, 2),
    transportation_monthly decimal(10, 2),
    facility_monthly decimal(10, 2),
    other_monthly decimal(10, 2),
    total_monthly decimal(10, 2) NOT NULL,

    -- Coverage estimates
    medicare_coverage_pct decimal(5, 2),
    medicaid_coverage_pct decimal(5, 2),
    private_insurance_pct decimal(5, 2),
    out_of_pocket_monthly decimal(10, 2),

    -- Notes
    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_care_cost_estimates_circle ON care_cost_estimates(circle_id, is_current);
```

### 7.3 Local Cost Data

```sql
CREATE TABLE IF NOT EXISTS local_care_costs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Location
    state text NOT NULL,
    metro_area text,
    zip_code_prefix text,  -- First 3 digits

    -- Care types (annual costs)
    home_health_aide_hourly decimal(10, 2),
    homemaker_services_hourly decimal(10, 2),
    adult_day_health_daily decimal(10, 2),
    assisted_living_monthly decimal(10, 2),
    nursing_home_semi_private_daily decimal(10, 2),
    nursing_home_private_daily decimal(10, 2),
    memory_care_monthly decimal(10, 2),

    -- Metadata
    data_source text NOT NULL,  -- GENWORTH, CMS, USER_REPORTED
    data_year int NOT NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(state, metro_area, zip_code_prefix, data_year)
);

CREATE INDEX idx_local_care_costs_location ON local_care_costs(state, zip_code_prefix);
```

### 7.4 Financial Resources

```sql
CREATE TABLE IF NOT EXISTS financial_resources (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Resource info
    title text NOT NULL,
    resource_type text NOT NULL,  -- ARTICLE, CALCULATOR, DIRECTORY, OFFICIAL_LINK
    category text NOT NULL,  -- MEDICARE, MEDICAID, VA, TAX, PLANNING
    description text,
    url text,

    -- Content
    content_markdown text,

    -- Targeting
    states text[],  -- NULL for national
    is_featured boolean NOT NULL DEFAULT false,

    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

---

## 8. RLS & Security

- [ ] care_expenses: Readable/writable by circle members
- [ ] care_cost_estimates: Readable/writable by circle members
- [ ] local_care_costs: Readable by all authenticated users
- [ ] financial_resources: Readable by all authenticated users
- [ ] Financial data treated as sensitive (not logged)

---

## 9. Edge Functions

### 9.1 estimate-care-costs

```typescript
// POST /functions/v1/estimate-care-costs

interface EstimateCostsRequest {
  circleId: string;
  patientId: string;
  zipCode: string;
  scenarios: {
    type:
      | "CURRENT"
      | "FULL_TIME_HOME"
      | "TWENTY_FOUR_SEVEN"
      | "ASSISTED_LIVING"
      | "MEMORY_CARE"
      | "NURSING_HOME";
    homeCarehours?: number;
  }[];
}

interface EstimateCostsResponse {
  scenarios: {
    type: string;
    monthlyTotal: number;
    yearlyTotal: number;
    breakdown: {
      category: string;
      amount: number;
    }[];
    comparedToCurrent: number; // Difference from current
  }[];
  localCostData: {
    source: string;
    year: number;
    areaName: string;
  };
}
```

### 9.2 generate-expense-report

```typescript
// POST /functions/v1/generate-expense-report

interface ExpenseReportRequest {
  circleId: string;
  patientId: string;
  startDate: string;
  endDate: string;
  format: "PDF" | "CSV";
  includeReceipts: boolean;
}

interface ExpenseReportResponse {
  reportUrl: string; // Signed URL
  totalExpenses: number;
  byCategory: Record<string, number>;
}
```

### 9.3 update-local-costs (Cron)

```typescript
// Runs monthly
// Updates local care cost data from external sources

async function updateLocalCosts(): Promise<{
  areasUpdated: number;
  dataSource: string;
}>;
```

---

## 10. iOS Implementation Notes

### 10.1 Cost Dashboard View

```swift
struct CareCostDashboardView: View {
    @StateObject private var viewModel = CareCostDashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Monthly summary card
                    MonthlyCostCard(
                        total: viewModel.currentMonthlyTotal,
                        breakdown: viewModel.costBreakdown
                    )

                    // Coverage status
                    CoverageStatusCard(
                        medicarePercent: viewModel.medicarePercent,
                        otherInsurancePercent: viewModel.otherInsurancePercent,
                        outOfPocketAmount: viewModel.outOfPocketAmount
                    )

                    // Quick actions
                    HStack(spacing: 12) {
                        NavigationLink(destination: ExpenseTrackerView()) {
                            QuickActionCard(
                                icon: "plus.circle",
                                title: "Track Spending",
                                color: .blue
                            )
                        }

                        NavigationLink(destination: CostProjectionsView()) {
                            QuickActionCard(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Projections",
                                color: .green
                            )
                        }
                    }

                    // Resources link
                    NavigationLink(destination: FinancialResourcesView()) {
                        ResourcesCard()
                    }
                }
                .padding()
            }
            .navigationTitle("Care Costs")
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
}
```

### 10.2 Monthly Cost Card

```swift
struct MonthlyCostCard: View {
    let total: Decimal
    let breakdown: [CostCategory: Decimal]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Monthly Costs")
                .font(.headline)

            Text(total, format: .currency(code: "USD"))
                .font(.system(size: 36, weight: .bold))

            Text("estimated")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Breakdown chart
            VStack(alignment: .leading, spacing: 8) {
                ForEach(breakdown.sorted(by: { $0.value > $1.value }), id: \.key) { category, amount in
                    HStack {
                        Rectangle()
                            .fill(category.color)
                            .frame(width: CGFloat(truncating: (amount / total * 100) as NSNumber), height: 8)
                            .cornerRadius(4)

                        Text(category.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(amount, format: .currency(code: "USD"))
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}
```

### 10.3 Cost Projections View

```swift
struct CostProjectionsView: View {
    @StateObject private var viewModel = CostProjectionsViewModel()

    var body: some View {
        List {
            Section {
                Text("Based on current care needs and local costs in \(viewModel.areaName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Current Care Level") {
                ScenarioCard(
                    scenario: viewModel.currentScenario,
                    isCurrent: true
                )
            }

            Section("If Care Needs Increase") {
                ForEach(viewModel.projectedScenarios) { scenario in
                    ScenarioCard(
                        scenario: scenario,
                        currentMonthly: viewModel.currentScenario.monthlyTotal
                    )
                }
            }

            Section {
                Button("Customize Scenarios") {
                    viewModel.showingCustomScenario = true
                }
            }
        }
        .navigationTitle("Cost Projections")
        .sheet(isPresented: $viewModel.showingCustomScenario) {
            CustomScenarioSheet()
        }
    }
}

struct ScenarioCard: View {
    let scenario: CareScenario
    var isCurrent: Bool = false
    var currentMonthly: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(scenario.name)
                    .font(.headline)
                if isCurrent {
                    Text("Current")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .cornerRadius(4)
                }
            }

            if let description = scenario.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text(scenario.monthlyTotal, format: .currency(code: "USD"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("/month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(scenario.yearlyTotal, format: .currency(code: "USD"))
                        .font(.subheadline)
                    Text("/year")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let current = currentMonthly, !isCurrent {
                let diff = scenario.monthlyTotal - current
                HStack {
                    Image(systemName: diff > 0 ? "arrow.up" : "arrow.down")
                    Text("\(diff > 0 ? "+" : "")\(diff, format: .currency(code: "USD"))/mo from current")
                }
                .font(.caption)
                .foregroundStyle(diff > 0 ? .red : .green)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### 10.4 Expense Entry Sheet

```swift
struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AddExpenseViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $viewModel.category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }

                    TextField("Description", text: $viewModel.description)

                    TextField("Vendor/Provider", text: $viewModel.vendorName)
                }

                Section {
                    TextField("Amount", value: $viewModel.amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)

                    DatePicker("Date", selection: $viewModel.expenseDate, displayedComponents: .date)
                }

                Section {
                    Toggle("Recurring Expense", isOn: $viewModel.isRecurring)

                    if viewModel.isRecurring {
                        Picker("Frequency", selection: $viewModel.recurrenceRule) {
                            Text("Weekly").tag(RecurrenceRule.weekly)
                            Text("Every 2 Weeks").tag(RecurrenceRule.biweekly)
                            Text("Monthly").tag(RecurrenceRule.monthly)
                        }
                    }
                }

                Section("Insurance Coverage") {
                    TextField("Amount Covered", value: $viewModel.coveredByInsurance, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)

                    HStack {
                        Text("Out of Pocket")
                        Spacer()
                        Text(viewModel.outOfPocket, format: .currency(code: "USD"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Attach Receipt", systemImage: "camera") {
                        viewModel.showingReceiptCapture = true
                    }

                    if viewModel.receiptImage != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Receipt attached")
                        }
                    }
                }
            }
            .navigationTitle("Add Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .sheet(isPresented: $viewModel.showingReceiptCapture) {
                ReceiptCaptureSheet(image: $viewModel.receiptImage)
            }
        }
    }
}
```

---

## 11. Metrics

| Metric              | Target         | Measurement                      |
| ------------------- | -------------- | -------------------------------- |
| Cost tool adoption  | 25% of circles | Circles that view costs          |
| Expense tracking    | 15% of circles | Circles with ≥1 expense          |
| Projection usage    | 60%            | Of adopters who view projections |
| Resource engagement | 40%            | Click-through to resources       |
| Report exports      | 20%            | Monthly export rate              |

---

## 12. Risks & Mitigations

| Risk                    | Impact   | Mitigation                         |
| ----------------------- | -------- | ---------------------------------- |
| Inaccurate projections  | High     | Clear disclaimers; data sources    |
| Financial advice claims | Critical | Not financial advice disclaimer    |
| Stale cost data         | Medium   | Regular updates; data date display |
| User financial anxiety  | Medium   | Supportive framing; resources      |

---

## 13. Dependencies

- Local cost data sources (Genworth, CMS)
- PDF generation (existing)
- Billing feature (optional link)
- Insurance info from binder

---

## 14. Testing Requirements

- [ ] Unit tests for cost calculations
- [ ] Integration tests for expense CRUD
- [ ] Report generation testing
- [ ] UI tests for expense entry
- [ ] Cost projection accuracy validation

---

## 15. Rollout Plan

1. **Alpha:** Expense tracking; manual summaries
2. **Beta:** Cost projections; local data
3. **GA:** Resources; report export
4. **Post-GA:** Advisor referrals; Medicaid planning tools

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Billing & Claims, Care Binder, Insurance
