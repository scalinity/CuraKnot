# Feature Spec 11 — Care Network Directory & Instant Sharing

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 3 (Workflow Expansion)
> Differentiator: One-tap sharing of complete care team — drives referrals

---

## 1. Problem Statement

Caregivers repeatedly answer the same question: "Who are the doctors? What's the pharmacy number? Which facility?" New family members, ER visits, and provider changes all require sharing the same information. Currently this info is scattered across binder items with no unified view or sharing mechanism.

A Care Network Directory consolidates all providers into a beautiful, shareable artifact. One-tap sharing reduces friction and creates word-of-mouth referrals.

---

## 2. Differentiation and Moat

- **Unified view** — all providers in one place
- **Beautiful PDF export** — professional document for sharing
- **Secure link sharing** — no app required to view
- **Viral vector** — recipients see CuraKnot in action
- **Emergency utility** — quick reference in crisis
- **Premium lever:** Custom branding, provider notes, appointment history

---

## 3. Goals

- [ ] G1: Consolidated view of all care team contacts
- [ ] G2: Generate beautiful PDF of care network
- [ ] G3: Secure web link for sharing (no login required)
- [ ] G4: Quick copy of individual provider info
- [ ] G5: Filter by provider type
- [ ] G6: Edit inline for quick updates

---

## 4. Non-Goals

- [ ] NG1: No provider search/discovery
- [ ] NG2: No appointment booking
- [ ] NG3: No provider ratings/reviews
- [ ] NG4: No insurance network verification

---

## 5. UX Flow

### 5.1 Directory View

```
┌─────────────────────────────────┐
│ Mom's Care Team                 │
│ ═══════════════════════════════│
│                                 │
│ [Share PDF] [Share Link]        │
│                                 │
│ 🩺 MEDICAL PROVIDERS            │
│ ┌─────────────────────────────┐ │
│ │ Dr. Sarah Johnson           │ │
│ │ Primary Care Physician      │ │
│ │ 📞 (555) 123-4567           │ │
│ │ 📍 123 Medical Center Dr    │ │
│ │ [Call] [Directions] [Copy]  │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ Dr. Michael Chen            │ │
│ │ Cardiologist                │ │
│ │ 📞 (555) 234-5678           │ │
│ │ [Call] [Directions] [Copy]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ 🏥 FACILITIES                   │
│ ┌─────────────────────────────┐ │
│ │ Sunrise Senior Care         │ │
│ │ Assisted Living Facility    │ │
│ │ 📞 Main: (555) 345-6789     │ │
│ │ 📞 Nurse: (555) 345-6790    │ │
│ │ [Call] [Directions]         │ │
│ └─────────────────────────────┘ │
│                                 │
│ 💊 PHARMACY                     │
│ ┌─────────────────────────────┐ │
│ │ CVS Pharmacy #4521          │ │
│ │ 📞 (555) 456-7890           │ │
│ │ 📍 456 Main Street          │ │
│ │ [Call] [Directions]         │ │
│ └─────────────────────────────┘ │
│                                 │
│ 🚨 EMERGENCY CONTACTS          │
│ [...]                           │
└─────────────────────────────────┘
```

### 5.2 Share Options

```
┌─────────────────────────────────┐
│ Share Care Team                 │
│ ═══════════════════════════════│
│                                 │
│ 📄 PDF Document                 │
│ Beautiful formatted PDF with    │
│ all provider information.       │
│                                 │
│ [Download PDF] [Share via...]   │
│                                 │
│ 🔗 Secure Link                  │
│ Anyone with this link can view  │
│ for 7 days. No login required.  │
│                                 │
│ Expires: February 12, 2026      │
│ [Copy Link] [Share via...]      │
│                                 │
│ ⚙️ What to Include:             │
│ [✓] Medical Providers           │
│ [✓] Facilities                  │
│ [✓] Pharmacy                    │
│ [✓] Emergency Contacts          │
│ [ ] Insurance Information       │
│                                 │
│ [Generate]                      │
└─────────────────────────────────┘
```

### 5.3 Web View (Recipient)

```
┌─────────────────────────────────┐
│ Care Team for Mary Smith        │
│ Shared by Jane Smith            │
│ ═══════════════════════════════│
│                                 │
│ [Provider cards...]             │
│                                 │
│ ─────────────────────────────── │
│ This information was shared     │
│ via CuraKnot - the caregiving   │
│ app that keeps families         │
│ coordinated.                    │
│                                 │
│ [Learn More About CuraKnot]     │
│                                 │
│ Link expires: Feb 12, 2026      │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Directory Aggregation

- [ ] Pull contacts from Binder (type: CONTACT, FACILITY)
- [ ] Group by provider type
- [ ] Sort within groups (alphabetical or custom)
- [ ] Include phone, address, notes
- [ ] Show last updated date

### 6.2 Provider Types

| Type              | Icon | Includes                           |
| ----------------- | ---- | ---------------------------------- |
| Medical Providers | 🩺   | Doctors, specialists, NPs, PAs     |
| Facilities        | 🏥   | Hospitals, nursing homes, rehab    |
| Pharmacy          | 💊   | Pharmacies                         |
| Home Care         | 🏠   | Home health, aides, PT/OT          |
| Emergency         | 🚨   | Emergency contacts, poison control |
| Insurance         | 🛡️   | Insurance contacts (optional)      |

### 6.3 PDF Generation

- [ ] Professional layout with patient name and date
- [ ] Sections by provider type
- [ ] Contact details with icons
- [ ] QR code linking to secure web version
- [ ] CuraKnot branding (subtle)

### 6.4 Secure Link Sharing

- [ ] Token-based URL (reuse share_links infrastructure)
- [ ] Configurable expiration (1, 7, 30 days)
- [ ] Revocable from settings
- [ ] Access audit logging
- [ ] Mobile-friendly web view

### 6.5 Quick Actions

- [ ] One-tap call from card
- [ ] One-tap directions (opens Maps)
- [ ] Copy all details to clipboard
- [ ] Quick edit (opens binder item)

---

## 7. Data Model

### 7.1 Network Exports

```sql
CREATE TABLE IF NOT EXISTS care_network_exports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Content
    included_types text[] NOT NULL,  -- MEDICAL, FACILITY, PHARMACY, etc.
    content_snapshot_json jsonb NOT NULL,  -- Snapshot of provider data
    provider_count int NOT NULL,

    -- PDF
    pdf_storage_key text,

    -- Share link (optional)
    share_link_id uuid REFERENCES share_links(id),

    created_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.2 Reuse share_links

```sql
-- Existing table, add network export support
-- object_type = 'care_network'
-- object_id = care_network_exports.id
```

---

## 8. RLS & Security

- [ ] care_network_exports: Readable by circle members; writable by contributors+
- [ ] PDF via signed URLs only
- [ ] Share link access logged
- [ ] No login required for share link view
- [ ] Sensitive info (SSN, insurance #) excluded from shares

---

## 9. Edge Functions

### 9.1 generate-care-network-pdf

```typescript
// POST /functions/v1/generate-care-network-pdf

interface GeneratePDFRequest {
  patientId: string;
  includedTypes: string[];
}

interface GeneratePDFResponse {
  exportId: string;
  pdfUrl: string; // Signed URL
}
```

### 9.2 resolve-care-network-link

```typescript
// GET /functions/v1/care-network/{token}
// Public endpoint - returns network data for web view

interface ResolveResponse {
  patientFirstName: string;
  sharedBy: string;
  providers: ProviderCard[];
  expiresAt: string;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Directory View

```swift
struct CareNetworkDirectoryView: View {
    @StateObject private var viewModel = CareNetworkViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.providerGroups) { group in
                    Section {
                        ForEach(group.providers) { provider in
                            ProviderCard(provider: provider)
                        }
                    } header: {
                        Label(group.typeName, systemImage: group.icon)
                    }
                }
            }
            .navigationTitle("\(viewModel.patientName)'s Care Team")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Share", systemImage: "square.and.arrow.up") {
                        Button("Download PDF", systemImage: "doc") {
                            viewModel.generatePDF()
                        }
                        Button("Create Share Link", systemImage: "link") {
                            viewModel.showShareOptions = true
                        }
                    }
                }
            }
        }
    }
}
```

### 10.2 Provider Card

```swift
struct ProviderCard: View {
    let provider: BinderContact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.name)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Call", systemImage: "phone") {
                        call(provider.phone)
                    }
                    Button("Directions", systemImage: "map") {
                        openMaps(provider.address)
                    }
                    Button("Copy Info", systemImage: "doc.on.doc") {
                        copyToClipboard(provider)
                    }
                    Button("Edit", systemImage: "pencil") {
                        editProvider(provider)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            if let specialty = provider.specialty {
                Text(specialty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let phone = provider.phone {
                Label(phone, systemImage: "phone")
                    .font(.caption)
            }

            if let address = provider.address {
                Label(address, systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### 10.3 Share Sheet

```swift
struct CareNetworkShareSheet: View {
    @ObservedObject var viewModel: CareNetworkViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Include") {
                    ForEach(ProviderType.allCases, id: \.self) { type in
                        Toggle(type.displayName, isOn: binding(for: type))
                    }
                }

                Section("PDF") {
                    Button("Generate & Download PDF") {
                        viewModel.generatePDF()
                    }

                    Button("Share PDF via...") {
                        viewModel.sharePDF()
                    }
                }

                Section("Secure Link") {
                    Picker("Expires in", selection: $viewModel.linkExpiration) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }

                    Button("Create Link") {
                        viewModel.createShareLink()
                    }

                    if let link = viewModel.shareLink {
                        HStack {
                            Text(link)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button("Copy") {
                                UIPasteboard.general.string = link
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share Care Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

---

## 11. Metrics

| Metric           | Target                 | Measurement                       |
| ---------------- | ---------------------- | --------------------------------- |
| Directory views  | 40% of binder users    | Users viewing directory/month     |
| PDF downloads    | 20% of directory users | PDFs generated/month              |
| Link shares      | 15% of directory users | Links created/month               |
| Link conversions | 5% of link views       | Visitors who learn about CuraKnot |
| Time savings     | Survey feedback        | User-reported value               |

---

## 12. Risks & Mitigations

| Risk                    | Impact | Mitigation                           |
| ----------------------- | ------ | ------------------------------------ |
| Stale information       | Medium | Show last updated; prompt for review |
| Privacy via share links | Medium | Expiration; revocation; access logs  |
| Missing providers       | Low    | Prompt to add; import from handoffs  |
| PDF formatting issues   | Low    | Test across devices; fallback text   |

---

## 13. Dependencies

- Binder contacts (existing)
- Share links infrastructure (existing)
- PDF generation (Edge Function)
- Supabase Storage

---

## 14. Testing Requirements

- [ ] Unit tests for provider aggregation
- [ ] Integration tests for PDF generation
- [ ] Integration tests for share link flow
- [ ] UI tests for directory and sharing
- [ ] Cross-browser testing for web view

---

## 15. Rollout Plan

1. **Alpha:** Directory view with quick actions
2. **Beta:** PDF generation
3. **GA:** Share links with web view
4. **Post-GA:** Provider search; import suggestions

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI + Edge Functions
- Baseline: `./CuraKnot-spec.md`
- Related: Binder Contacts, Share Links, Emergency Card
