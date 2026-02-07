# Feature Spec 18 — Legal Document Vault

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 5 (Expansion)
> Differentiator: Trust-building feature for serious caregiving situations

---

## 1. Problem Statement

When a medical emergency strikes, families scramble to find critical legal documents: Power of Attorney, Healthcare Proxy, Advance Directives, HIPAA authorizations, DNR orders. These papers are often in a filing cabinet, a lawyer's office, or "somewhere." This scramble happens at the worst possible moment and can delay critical medical decisions.

A Legal Document Vault provides secure, organized storage with appropriate access controls, expiration tracking, and one-tap sharing with healthcare providers when it matters most.

---

## 2. Differentiation and Moat

- **Critical trust feature** — families with serious situations need this
- **Emergency access** — documents available when needed most
- **Expiration tracking** — POAs and proxies can expire
- **Appropriate access controls** — role-based visibility
- **Premium lever:** Lawyer integration, notarization tracking, estate planning

---

## 3. Goals

- [ ] G1: Secure storage for legal documents with categorization
- [ ] G2: Role-based access controls (not all members see all docs)
- [ ] G3: Expiration date tracking with renewal reminders
- [ ] G4: Quick sharing with healthcare providers
- [ ] G5: Document verification status tracking
- [ ] G6: Integration with Emergency Card feature

---

## 4. Non-Goals

- [ ] NG1: No legal advice or document generation
- [ ] NG2: No notarization services
- [ ] NG3: No estate planning tools
- [ ] NG4: No automatic document validation

---

## 5. UX Flow

### 5.1 Legal Document Vault View

```
┌─────────────────────────────────┐
│ ⚖️ Legal Documents              │
│ ═══════════════════════════════│
│                                 │
│ [+ Add Document]                │
│                                 │
│ ─── Healthcare Decisions ──────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📄 Healthcare Power of Atty │ │
│ │ Agent: Jane Smith           │ │
│ │ Executed: Jan 15, 2024      │ │
│ │ ✓ Valid                     │ │
│ │ [View] [Share]              │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📄 HIPAA Authorization      │ │
│ │ Authorizes: Jane, Mike      │ │
│ │ Expires: Jan 15, 2025       │ │
│ │ ⚠️ Expires in 45 days       │ │
│ │ [View] [Share] [Renew]      │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📄 Advance Directive        │ │
│ │ Living Will                 │ │
│ │ Executed: Mar 10, 2023      │ │
│ │ ✓ Valid                     │ │
│ │ [View] [Share]              │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── Financial/Legal ──────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📄 Durable Power of Attorney│ │
│ │ Agent: Jane Smith           │ │
│ │ Executed: Jan 15, 2024      │ │
│ │ ✓ Valid                     │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Emergency Access Settings]     │
└─────────────────────────────────┘
```

### 5.2 Add Legal Document

```
┌─────────────────────────────────┐
│ Add Legal Document              │
│ ═══════════════════════════════│
│                                 │
│ Document Type:                  │
│ [Healthcare Power of Attorney▼] │
│                                 │
│ ─── Common Types ─────────────│
│ • Healthcare Power of Attorney  │
│ • Durable Power of Attorney     │
│ • Advance Directive/Living Will │
│ • HIPAA Authorization           │
│ • DNR/POLST Order               │
│ • Guardianship Papers           │
│ • Will/Trust (reference only)   │
│ • Other Legal Document          │
│                                 │
│ Document Title:                 │
│ [Healthcare POA - Mom        ]  │
│                                 │
│ [📷 Scan Document]              │
│ [📁 Import from Files]          │
│                                 │
│ Execution Date:                 │
│ [January 15, 2024         ▼]   │
│                                 │
│ Expiration Date (if any):       │
│ [None                     ▼]   │
│                                 │
│ Agent/Representative:           │
│ [Jane Smith               ]     │
│                                 │
│ [Continue]                      │
└─────────────────────────────────┘
```

### 5.3 Access Controls

```
┌─────────────────────────────────┐
│ Who Can Access This Document?   │
│ Healthcare POA - Mom            │
│ ═══════════════════════════════│
│                                 │
│ This document may contain       │
│ sensitive legal information.    │
│ Choose who can view it.         │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ [✓] Jane (you) - Owner      │ │
│ │     Full access             │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ [✓] Mike - Admin            │ │
│ │     Can view and share      │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ [ ] Sarah - Contributor     │ │
│ │     No access               │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ [ ] Tom - Viewer            │ │
│ │     No access               │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Save Document]                 │
└─────────────────────────────────┘
```

### 5.4 Share with Provider

```
┌─────────────────────────────────┐
│ Share Document                  │
│ Healthcare POA - Mom            │
│ ═══════════════════════════════│
│                                 │
│ Share with:                     │
│                                 │
│ (●) Healthcare Provider         │
│     Secure link, expires in 24h │
│                                 │
│ (○) Specific Email              │
│     Send directly               │
│                                 │
│ (○) Print Copy                  │
│     For in-person visits        │
│                                 │
│ ─── Secure Link Settings ─────│
│                                 │
│ Link expires after:             │
│ [24 hours               ▼]     │
│                                 │
│ Require access code:            │
│ [✓] Yes                         │
│ Code: 847291                    │
│                                 │
│ Include:                        │
│ [✓] Document                    │
│ [✓] Verification info           │
│ [ ] Related documents           │
│                                 │
│ [Generate Share Link]           │
└─────────────────────────────────┘
```

### 5.5 Emergency Access Settings

```
┌─────────────────────────────────┐
│ Emergency Access Settings       │
│ ═══════════════════════════════│
│                                 │
│ In an emergency, which documents│
│ should be accessible from the   │
│ Emergency Card?                 │
│                                 │
│ [✓] Healthcare Power of Attorney│
│ [✓] Advance Directive           │
│ [✓] HIPAA Authorization         │
│ [✓] DNR/POLST Order             │
│ [ ] Durable Power of Attorney   │
│ [ ] Will/Trust                  │
│                                 │
│ Emergency access requires:      │
│ (●) Biometric authentication    │
│ (○) PIN code                    │
│ (○) No additional auth          │
│                                 │
│ [Save Settings]                 │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Document Types

| Type                | Category   | Typical Expiration   |
| ------------------- | ---------- | -------------------- |
| Healthcare POA      | Healthcare | None (until revoked) |
| Durable POA         | Financial  | None (until revoked) |
| Advance Directive   | Healthcare | None                 |
| HIPAA Authorization | Healthcare | 1 year typical       |
| DNR/POLST           | Healthcare | Varies by state      |
| Guardianship        | Legal      | Court-ordered term   |
| Will                | Estate     | None                 |
| Trust               | Estate     | None                 |

### 6.2 Document Storage

- [ ] Encrypted storage at rest
- [ ] OCR for searchable text
- [ ] Multiple file formats (PDF, images)
- [ ] Version history for updates
- [ ] Audit log for access

### 6.3 Access Controls

- [ ] Per-document member access
- [ ] Minimum: Owner always has access
- [ ] Role suggestions based on document type
- [ ] Access audit trail

### 6.4 Expiration Management

- [ ] Track expiration dates
- [ ] Reminder notifications (90, 60, 30, 7 days)
- [ ] Renewal workflow
- [ ] Mark as renewed/replaced

### 6.5 Sharing

- [ ] Time-limited secure links
- [ ] Access code protection
- [ ] Print-ready PDF generation
- [ ] Share audit logging

### 6.6 Emergency Integration

- [ ] Link to Emergency Card
- [ ] Quick access in emergencies
- [ ] Biometric protection option

---

## 7. Data Model

### 7.1 Legal Documents

```sql
CREATE TABLE IF NOT EXISTS legal_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Document info
    document_type text NOT NULL,  -- HEALTHCARE_POA, DURABLE_POA, ADVANCE_DIRECTIVE, etc.
    title text NOT NULL,
    description text,

    -- Storage
    storage_key text NOT NULL,
    file_type text NOT NULL,  -- PDF, IMAGE
    file_size_bytes bigint,
    ocr_text text,  -- Searchable extracted text

    -- Dates
    execution_date date,
    expiration_date date,

    -- Parties
    principal_name text,  -- Person granting authority
    agent_name text,  -- Person receiving authority
    alternate_agent_name text,

    -- Verification
    notarized boolean NOT NULL DEFAULT false,
    notarized_date date,
    witness_names text[],

    -- Status
    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | EXPIRED | REVOKED | SUPERSEDED
    superseded_by uuid REFERENCES legal_documents(id),

    -- Emergency access
    include_in_emergency boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_legal_documents_patient ON legal_documents(patient_id, document_type);
CREATE INDEX idx_legal_documents_expiration ON legal_documents(expiration_date) WHERE expiration_date IS NOT NULL;
```

### 7.2 Document Access

```sql
CREATE TABLE IF NOT EXISTS legal_document_access (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,

    -- Permissions
    can_view boolean NOT NULL DEFAULT true,
    can_share boolean NOT NULL DEFAULT false,
    can_edit boolean NOT NULL DEFAULT false,

    granted_by uuid NOT NULL,
    granted_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(document_id, user_id)
);
```

### 7.3 Document Shares

```sql
CREATE TABLE IF NOT EXISTS legal_document_shares (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    shared_by uuid NOT NULL,

    -- Share settings
    share_token text NOT NULL UNIQUE,
    access_code text,  -- Optional PIN
    expires_at timestamptz NOT NULL,

    -- Tracking
    view_count int NOT NULL DEFAULT 0,
    last_viewed_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_legal_document_shares_token ON legal_document_shares(share_token);
```

### 7.4 Document Audit Log

```sql
CREATE TABLE IF NOT EXISTS legal_document_audit (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    user_id uuid,  -- NULL for external access via share link

    action text NOT NULL,  -- VIEWED | SHARED | DOWNLOADED | PRINTED | UPDATED | DELETED
    details_json jsonb,

    ip_address inet,
    user_agent text,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_legal_document_audit_document ON legal_document_audit(document_id, created_at DESC);
```

---

## 8. RLS & Security

- [ ] legal_documents: Readable by members with explicit access
- [ ] legal_document_access: Managed by Owner/Admin only
- [ ] legal_document_shares: Created by members with share permission
- [ ] legal_document_audit: Readable by Owner/Admin
- [ ] Documents encrypted at rest
- [ ] Share links use time-limited signed URLs
- [ ] All access logged for audit

---

## 9. Edge Functions

### 9.1 generate-document-share

```typescript
// POST /functions/v1/generate-document-share

interface GenerateShareRequest {
  documentId: string;
  expirationHours: number;
  requireAccessCode: boolean;
}

interface GenerateShareResponse {
  shareUrl: string;
  accessCode?: string;
  expiresAt: string;
}
```

### 9.2 resolve-document-share

```typescript
// GET /functions/v1/document-share/{token}
// Public endpoint with optional access code

interface ResolveShareRequest {
  accessCode?: string;
}

interface ResolveShareResponse {
  documentType: string;
  title: string;
  documentUrl: string; // Short-lived signed URL
  patientName: string;
  executionDate?: string;
  expirationDate?: string;
}
```

### 9.3 send-expiration-reminders (Cron)

```typescript
// Runs daily
// Sends reminders for expiring documents

async function sendExpirationReminders(): Promise<{
  remindersSent: number;
  documentsExpiring: {
    documentId: string;
    daysUntilExpiration: number;
  }[];
}>;
```

---

## 10. iOS Implementation Notes

### 10.1 Legal Vault View

```swift
struct LegalVaultView: View {
    @StateObject private var viewModel = LegalVaultViewModel()
    @State private var showingAddDocument = false

    var body: some View {
        NavigationStack {
            List {
                // Expiration warnings
                if !viewModel.expiringDocuments.isEmpty {
                    Section {
                        ForEach(viewModel.expiringDocuments) { doc in
                            ExpirationWarningRow(document: doc)
                        }
                    } header: {
                        Label("Attention Needed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                // Healthcare documents
                Section("Healthcare Decisions") {
                    ForEach(viewModel.healthcareDocuments) { doc in
                        LegalDocumentRow(document: doc)
                    }
                }

                // Financial/Legal documents
                Section("Financial & Legal") {
                    ForEach(viewModel.financialDocuments) { doc in
                        LegalDocumentRow(document: doc)
                    }
                }

                // Estate documents
                if !viewModel.estateDocuments.isEmpty {
                    Section("Estate Planning") {
                        ForEach(viewModel.estateDocuments) { doc in
                            LegalDocumentRow(document: doc)
                        }
                    }
                }
            }
            .navigationTitle("Legal Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") {
                        showingAddDocument = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink(destination: EmergencyAccessSettingsView()) {
                        Label("Emergency Settings", systemImage: "cross.case")
                    }
                }
            }
            .sheet(isPresented: $showingAddDocument) {
                AddLegalDocumentSheet()
            }
        }
    }
}
```

### 10.2 Legal Document Row

```swift
struct LegalDocumentRow: View {
    let document: LegalDocument

    var body: some View {
        NavigationLink(value: document) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.headline)

                    if let agent = document.agentName {
                        Text("Agent: \(agent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        if let execDate = document.executionDate {
                            Text("Executed: \(execDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                DocumentStatusBadge(document: document)
            }
        }
    }
}

struct DocumentStatusBadge: View {
    let document: LegalDocument

    var body: some View {
        Group {
            if document.status == .expired {
                Label("Expired", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let daysUntil = document.daysUntilExpiration, daysUntil <= 90 {
                Label("Expires \(daysUntil)d", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("Valid", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}
```

### 10.3 Share Document Sheet

```swift
struct ShareDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ShareDocumentViewModel
    let document: LegalDocument

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Share Method", selection: $viewModel.shareMethod) {
                        Text("Secure Link").tag(ShareMethod.secureLink)
                        Text("Email Directly").tag(ShareMethod.email)
                        Text("Print").tag(ShareMethod.print)
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.shareMethod == .secureLink {
                    Section("Link Settings") {
                        Picker("Expires After", selection: $viewModel.expirationHours) {
                            Text("1 hour").tag(1)
                            Text("24 hours").tag(24)
                            Text("7 days").tag(168)
                        }

                        Toggle("Require Access Code", isOn: $viewModel.requireAccessCode)

                        if viewModel.requireAccessCode {
                            HStack {
                                Text("Code")
                                Spacer()
                                Text(viewModel.accessCode)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if viewModel.shareMethod == .email {
                    Section("Recipient") {
                        TextField("Email Address", text: $viewModel.recipientEmail)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                    }
                }
            }
            .navigationTitle("Share Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        viewModel.share()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .sheet(item: $viewModel.generatedShareLink) { link in
                ShareLinkResultSheet(link: link)
            }
        }
    }
}
```

### 10.4 Biometric Access Gate

```swift
struct LegalDocumentDetailView: View {
    let document: LegalDocument
    @State private var isUnlocked = false

    var body: some View {
        Group {
            if isUnlocked {
                DocumentContentView(document: document)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.doc.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("Protected Document")
                        .font(.headline)

                    Text("This legal document requires authentication to view.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Unlock with Face ID") {
                        authenticate()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .navigationTitle(document.title)
        .onAppear {
            authenticate()
        }
    }

    func authenticate() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "View legal document") { success, _ in
            DispatchQueue.main.async {
                isUnlocked = success
            }
        }
    }
}
```

---

## 11. Metrics

| Metric                | Target         | Measurement                |
| --------------------- | -------------- | -------------------------- |
| Vault adoption        | 20% of circles | Circles with ≥1 document   |
| Documents per circle  | 3+             | Average documents          |
| Share usage           | 30% of vaults  | Circles that share docs    |
| Emergency card link   | 80% of vaults  | Docs linked to emergency   |
| Expiration compliance | 90%            | Renewals before expiration |

---

## 12. Risks & Mitigations

| Risk                  | Impact   | Mitigation                         |
| --------------------- | -------- | ---------------------------------- |
| Document validity     | Critical | Disclaimer: not legal verification |
| Privacy breach        | Critical | Encryption; biometric; audit logs  |
| User error (deletion) | High     | Soft delete; recovery period       |
| Expiration missed     | Medium   | Multiple reminders; push notif     |

---

## 13. Dependencies

- Document scanner (existing)
- Biometric authentication
- Encrypted storage
- Share links infrastructure
- Emergency Card feature

---

## 14. Testing Requirements

- [ ] Unit tests for access control logic
- [ ] Integration tests for share flow
- [ ] Security testing for encryption
- [ ] UI tests for document upload
- [ ] Expiration reminder testing

---

## 15. Rollout Plan

1. **Alpha:** Basic document storage and viewing
2. **Beta:** Access controls; sharing
3. **GA:** Expiration tracking; emergency integration
4. **Post-GA:** Lawyer directory; notarization tracking

---

### Linkage

- Product: CuraKnot
- Stack: Supabase Storage + LocalAuthentication + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Emergency Card, Document Scanner, Share Links
