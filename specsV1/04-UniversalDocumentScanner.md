# Feature Spec 04 — Universal Document Scanner with AI Auto-Filing

> Date: 2026-02-05 | Priority: HIGH | Phase: 1 (Foundation)
> Differentiator: Single capture point for paper chaos; extends OCR investment

---

## 1. Problem Statement

Caregiving involves constant paperwork: discharge summaries, prescriptions, lab results, insurance EOBs, facility notices, and appointment confirmations. This paper arrives continuously and must be organized, but manual filing is tedious and often skipped. Documents end up in drawers, lost, or photographed without context.

CuraKnot already has OCR infrastructure for medication reconciliation. Extending this to universal document scanning with AI-powered classification creates a single capture point that automatically routes documents to the correct location.

---

## 2. Differentiation and Moat

- **Leverages existing OCR investment** — incremental effort, major value add
- **AI classification** — automatic routing reduces cognitive load
- **Single capture point** — scan anything, CuraKnot figures out where it goes
- **Creates structured data** — extracted info populates binder, creates tasks
- **Premium lever:** Advanced OCR, multi-page documents, historical search

---

## 3. Goals

- [ ] G1: Scan any document (camera or photo library import)
- [ ] G2: AI classifies document type (medication, lab result, bill, discharge, etc.)
- [ ] G3: AI extracts key fields based on document type
- [ ] G4: Auto-route to appropriate destination (Binder, Billing, create Handoff draft)
- [ ] G5: User confirms classification and extracted data before finalizing
- [ ] G6: Store original image with provenance; searchable by extracted text

---

## 4. Non-Goals

- [ ] NG1: No real-time document editing (just capture and classify)
- [ ] NG2: No EHR integration or medical record standards (FHIR, etc.)
- [ ] NG3: No automated insurance claim filing
- [ ] NG4: No handwriting recognition beyond printed text
- [ ] NG5: No guaranteed 100% accuracy — always requires user confirmation

---

## 5. UX Flow

### 5.1 Capture Flow

1. **Entry:** Binder → Scan Document OR Care Inbox → Scan
2. **Capture:** Camera with document overlay guides OR import from photos
3. **Processing:** "Analyzing document..." with progress indicator
4. **Classification:** AI suggests document type with confidence
5. **Extraction:** AI extracts relevant fields based on type
6. **Review:** User confirms/edits classification and fields
7. **Route:** Document saved to appropriate location

### 5.2 Classification Categories

| Category           | Auto-Route To      | Extracted Fields                     |
| ------------------ | ------------------ | ------------------------------------ |
| Medication List    | Binder > Meds      | Med names, doses, schedules          |
| Prescription       | Binder > Meds      | Med name, dose, prescriber, pharmacy |
| Lab Results        | Handoff draft      | Test names, values, date, provider   |
| Discharge Summary  | Handoff draft      | Diagnosis, instructions, follow-ups  |
| Appointment Notice | Binder > Contacts  | Provider, date, time, location       |
| Insurance EOB      | Billing            | Claim #, amount, date, status        |
| Bill/Invoice       | Billing            | Vendor, amount, due date             |
| Facility Notice    | Handoff draft      | Facility, subject, key points        |
| ID/Insurance Card  | Binder > Insurance | Member ID, group #, phone            |
| Other              | Care Inbox         | Raw text extraction                  |

### 5.3 Review Screen

```
┌─────────────────────────────────┐
│ Document Scanned                │
│ ═══════════════════════════════│
│ [Document Preview Image]        │
│                                 │
│ Detected Type: Prescription     │
│ Confidence: 94%    [Change ▼]   │
│                                 │
│ Extracted Information:          │
│ ├─ Medication: Lisinopril       │
│ ├─ Dose: 10mg                   │
│ ├─ Frequency: Once daily        │
│ ├─ Prescriber: Dr. Smith        │
│ └─ Pharmacy: CVS #1234          │
│                                 │
│ Route to: Binder > Medications  │
│                                 │
│ [Cancel]           [Confirm]    │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Document Capture

- [ ] Camera capture with document edge detection
- [ ] Auto-crop and perspective correction
- [ ] Multi-page capture with page management
- [ ] Import from Photos library
- [ ] Import from Files app
- [ ] Minimum resolution requirements for OCR quality

### 6.2 OCR Processing

- [ ] On-device OCR for privacy (Vision framework)
- [ ] Cloud OCR fallback for complex documents (Edge Function)
- [ ] Support for English; Spanish in Phase 2
- [ ] Handle poor quality scans gracefully (re-scan suggestion)
- [ ] Extract full text for search indexing

### 6.3 AI Classification

- [ ] Document type classification (multi-class)
- [ ] Confidence score per classification
- [ ] User feedback loop for model improvement
- [ ] Fallback to "Other" with manual routing

### 6.4 Field Extraction by Type

**Medication-related:**

- Medication name (generic and brand)
- Dose and unit
- Frequency/schedule
- Prescriber name
- Pharmacy name
- Start/end dates
- Refills remaining

**Financial:**

- Vendor/provider name
- Amount
- Currency
- Due date
- Account/claim number
- Status indicators

**Appointment:**

- Provider name
- Specialty
- Date and time
- Location/address
- Phone number
- Preparation instructions

**Lab Results:**

- Test names
- Values with units
- Reference ranges
- Collection date
- Ordering provider

### 6.5 Routing Rules

```typescript
interface RoutingDecision {
  documentType: DocumentType;
  confidence: number;
  destination:
    | { type: "BINDER"; section: BinderSection }
    | { type: "BILLING" }
    | { type: "HANDOFF_DRAFT"; template: HandoffTemplate }
    | { type: "INBOX" };
  extractedFields: Record<string, ExtractedValue>;
  requiresConfirmation: boolean;
}
```

### 6.6 Storage and Search

- [ ] Original image stored in Supabase Storage
- [ ] Extracted text stored for full-text search
- [ ] Link to created entities (binder items, handoffs, billing)
- [ ] Provenance chain: document → extracted data → entity

---

## 7. Data Model

### 7.1 Scanned Documents

```sql
CREATE TABLE IF NOT EXISTS scanned_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid REFERENCES patients(id) ON DELETE SET NULL,
    created_by uuid NOT NULL,

    -- Storage
    storage_keys text[] NOT NULL,  -- One per page
    page_count int NOT NULL DEFAULT 1,

    -- OCR Results
    ocr_text text,  -- Full extracted text
    ocr_confidence float,
    ocr_provider text,  -- VISION | CLOUD

    -- Classification
    document_type text,  -- PRESCRIPTION | LAB_RESULT | BILL | etc.
    classification_confidence float,
    classification_source text,  -- AI | USER_OVERRIDE

    -- Extracted Fields
    extracted_fields_json jsonb,
    extraction_confidence float,

    -- Routing
    routed_to_type text,  -- BINDER | BILLING | HANDOFF | INBOX
    routed_to_id uuid,  -- ID of created entity
    routed_at timestamptz,
    routed_by uuid,

    -- Status
    status text NOT NULL DEFAULT 'PENDING',  -- PENDING | PROCESSING | READY | ROUTED | FAILED
    error_message text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Full-text search index
CREATE INDEX idx_scanned_documents_ocr_text
ON scanned_documents USING gin(to_tsvector('english', ocr_text));
```

### 7.2 Document Type Definitions

```sql
CREATE TABLE IF NOT EXISTS document_type_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    type_key text NOT NULL UNIQUE,
    display_name text NOT NULL,
    route_to text NOT NULL,
    extraction_schema_json jsonb NOT NULL,  -- Expected fields
    classification_keywords text[],
    icon text,
    sort_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true
);

-- Seed data
INSERT INTO document_type_definitions (type_key, display_name, route_to, extraction_schema_json, icon) VALUES
('PRESCRIPTION', 'Prescription', 'BINDER_MEDS', '{"fields": ["med_name", "dose", "frequency", "prescriber"]}', 'pill'),
('LAB_RESULT', 'Lab Results', 'HANDOFF_DRAFT', '{"fields": ["test_name", "value", "date", "provider"]}', 'flask'),
('DISCHARGE', 'Discharge Summary', 'HANDOFF_DRAFT', '{"fields": ["diagnosis", "instructions", "followups"]}', 'building'),
('BILL', 'Bill/Invoice', 'BILLING', '{"fields": ["vendor", "amount", "due_date"]}', 'dollarsign'),
('EOB', 'Insurance EOB', 'BILLING', '{"fields": ["claim_number", "amount", "date"]}', 'shield'),
('APPOINTMENT', 'Appointment Notice', 'BINDER_CONTACTS', '{"fields": ["provider", "date", "time", "location"]}', 'calendar'),
('INSURANCE_CARD', 'Insurance Card', 'BINDER_INSURANCE', '{"fields": ["member_id", "group_number", "phone"]}', 'creditcard'),
('OTHER', 'Other Document', 'INBOX', '{"fields": []}', 'doc');
```

### 7.3 Provenance Links

```sql
-- Add provenance to existing tables
ALTER TABLE binder_items
ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES scanned_documents(id);

ALTER TABLE financial_items
ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES scanned_documents(id);

ALTER TABLE handoffs
ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES scanned_documents(id);
```

---

## 8. RLS & Security

- [ ] scanned_documents: readable by circle members; writable by contributors+
- [ ] OCR text may contain PHI — same access controls as handoffs
- [ ] Storage objects via signed URLs only
- [ ] No permanent public URLs for scanned documents
- [ ] Audit logging for document access

---

## 9. Edge Functions

### 9.1 classify-document

```typescript
// POST /functions/v1/classify-document
// Classifies document and extracts fields

interface ClassifyRequest {
  documentId: string;
  ocrText: string;
  imageUrls?: string[]; // For vision-based classification
}

interface ClassifyResponse {
  documentType: string;
  confidence: number;
  extractedFields: Record<
    string,
    {
      value: string;
      confidence: number;
      source: "OCR" | "INFERRED";
    }
  >;
  suggestedRouting: {
    destination: string;
    reason: string;
  };
}
```

### 9.2 ocr-document (fallback)

```typescript
// POST /functions/v1/ocr-document
// Cloud OCR for complex documents

interface OCRRequest {
  storageKeys: string[];
  language?: string;
}

interface OCRResponse {
  pages: {
    text: string;
    confidence: number;
    blocks: OCRBlock[];
  }[];
}
```

### 9.3 route-document

```typescript
// POST /functions/v1/route-document
// Creates target entity from extracted fields

interface RouteRequest {
  documentId: string;
  confirmedType: string;
  confirmedFields: Record<string, string>;
  destination: string;
}

interface RouteResponse {
  success: boolean;
  createdEntityId: string;
  createdEntityType: string;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Document Scanner View

```swift
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var scannedImages: [UIImage]

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Extract images from scan
            for i in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: i)
                // Process image
            }
        }
    }
}
```

### 10.2 On-Device OCR

```swift
import Vision

func performOCR(on image: UIImage) async throws -> String {
    guard let cgImage = image.cgImage else { throw OCRError.invalidImage }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]

    let handler = VNImageRequestHandler(cgImage: cgImage)
    try handler.perform([request])

    let text = request.results?
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")

    return text ?? ""
}
```

### 10.3 Processing Flow

```swift
class DocumentProcessor {
    func process(_ images: [UIImage]) async throws -> ProcessedDocument {
        // 1. Upload images to storage
        let storageKeys = try await uploadImages(images)

        // 2. Perform on-device OCR
        let ocrTexts = try await images.asyncMap { try await performOCR(on: $0) }
        let combinedText = ocrTexts.joined(separator: "\n---\n")

        // 3. Call classification Edge Function
        let classification = try await classifyDocument(
            ocrText: combinedText,
            storageKeys: storageKeys
        )

        // 4. Return for user review
        return ProcessedDocument(
            storageKeys: storageKeys,
            ocrText: combinedText,
            classification: classification
        )
    }
}
```

### 10.4 UI Components

- DocumentScannerSheet: VisionKit scanner wrapper
- ProcessingView: Loading state with progress
- ClassificationReviewView: Confirm type and fields
- FieldEditorView: Edit extracted fields
- RoutingConfirmationView: Confirm destination

---

## 11. Metrics

| Metric                  | Target                | Measurement                       |
| ----------------------- | --------------------- | --------------------------------- |
| Scan adoption           | 50% of active circles | Circles with ≥1 scan/month        |
| Classification accuracy | 90%                   | AI correct / user confirmed       |
| Extraction accuracy     | 85%                   | Fields correct / total fields     |
| Routing success         | 95%                   | Successfully routed / total scans |
| Time to route           | <2 minutes            | From capture to routing           |
| Search usage            | 20% of users          | Users searching scanned docs      |

---

## 12. Risks & Mitigations

| Risk                      | Impact | Mitigation                                 |
| ------------------------- | ------ | ------------------------------------------ |
| OCR quality on poor scans | High   | Re-scan prompts; cloud fallback            |
| Classification errors     | Medium | Always require confirmation                |
| Extraction errors         | Medium | Editable fields; learn from corrections    |
| Privacy concerns          | High   | On-device OCR primary; clear data handling |
| Storage costs             | Medium | Retention policies; compression            |

---

## 13. Dependencies

- VisionKit (document scanning)
- Vision framework (on-device OCR)
- Supabase Storage
- LLM API for classification (existing)
- Existing Binder, Billing, Handoff infrastructure

---

## 14. Testing Requirements

- [ ] Unit tests for OCR text processing
- [ ] Unit tests for classification logic
- [ ] Unit tests for field extraction
- [ ] Integration tests for Edge Functions
- [ ] UI tests for scan flow
- [ ] Manual testing with real documents

---

## 15. Rollout Plan

1. **Alpha:** Basic scan + manual classification
2. **Beta:** AI classification + extraction for medications
3. **GA:** Full document type support
4. **Post-GA:** Multi-language, handwriting recognition

---

### Linkage

- Product: CuraKnot
- Stack: VisionKit + Vision + Supabase Edge Functions
- Baseline: `./CuraKnot-spec.md`
- Related: Med Reconciliation (shared OCR), Care Inbox, Billing
