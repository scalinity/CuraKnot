# Feature Spec 12 — Secure Condition Photo Tracking

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 3 (Workflow Expansion)
> Differentiator: Visual documentation with clinical utility — privacy-first design

---

## 1. Problem Statement

Clinicians frequently ask "Is it better or worse?" about wounds, rashes, swelling, or other visual conditions. Caregivers rely on memory or show random phone photos without context. A systematic photo tracking feature with timestamps, annotations, and secure sharing provides definitive answers and improves clinical communication.

---

## 2. Differentiation and Moat

- **Clinical utility** — definitive "before and after" evidence
- **Privacy-first** — sensitive photos with appropriate controls
- **Structured tracking** — not random photos, organized by condition
- **Secure sharing** — time-limited links for clinicians
- **Premium lever:** Advanced comparison views, measurement tools

---

## 3. Goals

- [ ] G1: Capture photos linked to specific conditions/concerns
- [ ] G2: Timeline view showing progression over time
- [ ] G3: Side-by-side comparison of photos
- [ ] G4: Annotation tools for marking areas of concern
- [ ] G5: Secure sharing with clinicians via time-limited links
- [ ] G6: Privacy controls (blur in timeline, require auth to view)

---

## 4. Non-Goals

- [ ] NG1: No AI diagnosis or analysis of photos
- [ ] NG2: No wound measurement (Phase 2)
- [ ] NG3: No integration with clinical imaging systems
- [ ] NG4: No video tracking

---

## 5. UX Flow

### 5.1 Condition Setup

```
┌─────────────────────────────────┐
│ Track a Condition               │
│ ═══════════════════════════════│
│                                 │
│ What are you tracking?          │
│                                 │
│ [Wound/Incision]  [Rash]        │
│ [Swelling]        [Bruise]      │
│ [Skin Change]     [Other]       │
│                                 │
│ Location on body:               │
│ [Left leg           ]           │
│                                 │
│ Description:                    │
│ [Surgical incision from hip  ]  │
│ [replacement                 ]  │
│                                 │
│ Start date:                     │
│ [February 1, 2026       ▼]      │
│                                 │
│ [Start Tracking]                │
└─────────────────────────────────┘
```

### 5.2 Photo Capture

```
┌─────────────────────────────────┐
│ ← Left Leg Incision             │
│ ═══════════════════════════════│
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │     [Camera Preview]        │ │
│ │                             │ │
│ │      ┌───────────┐          │ │
│ │      │  Guide    │          │ │
│ │      │  Frame    │          │ │
│ │      └───────────┘          │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ Tips:                           │
│ • Use consistent lighting       │
│ • Include a reference (coin)    │
│ • Capture the same angle        │
│                                 │
│        [📷 Capture]             │
│                                 │
│ Previous: 2 days ago            │
│ [View Previous] [Compare]       │
└─────────────────────────────────┘
```

### 5.3 Timeline View

```
┌─────────────────────────────────┐
│ ← Left Leg Incision             │
│ ═══════════════════════════════│
│                                 │
│ Status: Tracking (14 days)      │
│ Photos: 5                       │
│                                 │
│ [Share with Clinician]          │
│                                 │
│ ─── February 2026 ─────────────│
│                                 │
│ Feb 7 ──────────────────────── │
│ ┌──────┐                        │
│ │[Photo]│ Looking better.       │
│ │      │ Redness reduced.       │
│ └──────┘                        │
│                                 │
│ Feb 5 ──────────────────────── │
│ ┌──────┐                        │
│ │[Photo]│ Some redness around   │
│ │      │ edges. No drainage.    │
│ └──────┘                        │
│                                 │
│ Feb 3 ──────────────────────── │
│ ┌──────┐                        │
│ │[Photo]│ First photo after     │
│ │      │ coming home.           │
│ └──────┘                        │
│                                 │
│ [📷 Add Photo]                  │
└─────────────────────────────────┘
```

### 5.4 Comparison View

```
┌─────────────────────────────────┐
│ Compare Photos                  │
│ ═══════════════════════════════│
│                                 │
│ ┌─────────────┐ ┌─────────────┐ │
│ │             │ │             │ │
│ │   Feb 3     │ │   Feb 7     │ │
│ │             │ │             │ │
│ │  [Photo]    │ │  [Photo]    │ │
│ │             │ │             │ │
│ └─────────────┘ └─────────────┘ │
│   Day 1          Day 5          │
│                                 │
│ [← Previous] [Slider] [Next →]  │
│                                 │
│ [Share Comparison]              │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Condition Tracking

- [ ] Create tracked conditions with type, location, description
- [ ] Support multiple concurrent conditions
- [ ] Archive resolved conditions
- [ ] Link conditions to handoffs (e.g., "mentioned in discharge notes")

### 6.2 Photo Capture

- [ ] Camera integration with guide frame
- [ ] Import from photo library
- [ ] Required note/observation with each photo
- [ ] Optional annotation (draw on photo)
- [ ] Automatic date/time metadata
- [ ] Lighting quality detection (suggest retake)

### 6.3 Photo Storage & Privacy

- [ ] Encrypted storage in Supabase
- [ ] Thumbnails blurred by default in timeline (configurable)
- [ ] Require Face ID/Touch ID to view full photos
- [ ] Photos excluded from device photo library
- [ ] No cloud backup sync (stays in CuraKnot only)

### 6.4 Comparison Tools

- [ ] Side-by-side comparison view
- [ ] Slider comparison (swipe to reveal)
- [ ] Select any two photos to compare
- [ ] Comparison annotations

### 6.5 Secure Sharing

- [ ] Generate time-limited share link (reuse share_links)
- [ ] Include selected photos and notes
- [ ] Clinician can view without login
- [ ] Access audit logging
- [ ] Revocable links

### 6.6 Condition Types

| Type           | Use Case                  | Typical Duration |
| -------------- | ------------------------- | ---------------- |
| Wound/Incision | Surgical sites, cuts      | Weeks            |
| Rash           | Skin reactions, allergies | Days-weeks       |
| Swelling       | Edema, injuries           | Days-weeks       |
| Bruise         | Falls, injuries           | Days             |
| Skin Change    | Moles, discoloration      | Ongoing          |
| Pressure Area  | Bedsore prevention        | Ongoing          |

---

## 7. Data Model

### 7.1 Tracked Conditions

```sql
CREATE TABLE IF NOT EXISTS tracked_conditions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Condition details
    condition_type text NOT NULL,  -- WOUND, RASH, SWELLING, etc.
    body_location text NOT NULL,
    description text,
    start_date date NOT NULL,

    -- Status
    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | RESOLVED | ARCHIVED
    resolved_date date,
    resolution_notes text,

    -- Privacy
    require_biometric boolean NOT NULL DEFAULT true,
    blur_thumbnails boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 7.2 Condition Photos

```sql
CREATE TABLE IF NOT EXISTS condition_photos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    condition_id uuid NOT NULL REFERENCES tracked_conditions(id) ON DELETE CASCADE,
    circle_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    created_by uuid NOT NULL,

    -- Photo storage
    storage_key text NOT NULL,  -- Encrypted storage
    thumbnail_key text,

    -- Metadata
    captured_at timestamptz NOT NULL DEFAULT now(),
    notes text NOT NULL,

    -- Annotations
    annotations_json jsonb,  -- Drawn annotations

    -- Quality
    lighting_quality text,  -- GOOD | FAIR | POOR

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_condition_photos_condition ON condition_photos(condition_id, captured_at DESC);
```

### 7.3 Photo Shares

```sql
-- Reuse share_links with object_type = 'condition_photos'
-- Additional table for which photos are included

CREATE TABLE IF NOT EXISTS condition_share_photos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    share_link_id uuid NOT NULL REFERENCES share_links(id) ON DELETE CASCADE,
    condition_photo_id uuid NOT NULL REFERENCES condition_photos(id) ON DELETE CASCADE,
    include_annotations boolean NOT NULL DEFAULT true,
    UNIQUE(share_link_id, condition_photo_id)
);
```

---

## 8. RLS & Security

- [ ] tracked_conditions: Readable by circle members; writable by contributors+
- [ ] condition_photos: Same access as tracked_conditions
- [ ] Photos encrypted at rest
- [ ] Share links have strict TTL (24h default, max 7 days)
- [ ] Biometric required by default to view photos
- [ ] No caching of photos in web views
- [ ] Audit log for all photo access

---

## 9. Edge Functions

### 9.1 generate-condition-share

```typescript
// POST /functions/v1/generate-condition-share

interface GenerateShareRequest {
  conditionId: string;
  photoIds: string[];
  expirationHours: number; // Max 168 (7 days)
  includeAnnotations: boolean;
}

interface GenerateShareResponse {
  shareUrl: string;
  expiresAt: string;
}
```

### 9.2 resolve-condition-share

```typescript
// GET /functions/v1/condition-share/{token}
// Public endpoint

interface ResolveResponse {
  conditionType: string;
  bodyLocation: string;
  photos: {
    capturedAt: string;
    notes: string;
    imageUrl: string; // Short-lived signed URL
    annotations?: object;
  }[];
  expiresAt: string;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Photo Capture View

```swift
struct ConditionPhotoCaptureView: View {
    @StateObject private var viewModel: PhotoCaptureViewModel
    let condition: TrackedCondition

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: viewModel.captureSession)

            // Guide frame overlay
            GuideFrameOverlay()

            // Controls
            VStack {
                Spacer()

                // Tips
                Text("Use consistent lighting and angle")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                // Capture button
                Button {
                    viewModel.capturePhoto()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(lineWidth: 3)
                                .foregroundColor(.gray)
                        )
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(item: $viewModel.capturedImage) { image in
            PhotoReviewSheet(
                image: image,
                condition: condition,
                onSave: viewModel.savePhoto
            )
        }
    }
}
```

### 10.2 Biometric Gate

```swift
struct BiometricGatedView<Content: View>: View {
    @State private var isUnlocked = false
    let content: () -> Content

    var body: some View {
        Group {
            if isUnlocked {
                content()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "faceid")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("Photos are protected")
                        .font(.headline)

                    Button("Unlock with Face ID") {
                        authenticate()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            if !isUnlocked {
                authenticate()
            }
        }
    }

    func authenticate() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "View condition photos") { success, _ in
            DispatchQueue.main.async {
                isUnlocked = success
            }
        }
    }
}
```

### 10.3 Comparison View

```swift
struct PhotoComparisonView: View {
    let photos: [ConditionPhoto]
    @State private var leftIndex = 0
    @State private var rightIndex = 1

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                PhotoCard(photo: photos[leftIndex])
                PhotoCard(photo: photos[rightIndex])
            }

            // Date labels
            HStack {
                Text(photos[leftIndex].capturedAt, style: .date)
                Spacer()
                Text(photos[rightIndex].capturedAt, style: .date)
            }
            .font(.caption)

            // Navigation
            HStack {
                Button("← Earlier") {
                    if leftIndex > 0 { leftIndex -= 1 }
                }
                .disabled(leftIndex == 0)

                Spacer()

                Button("Later →") {
                    if rightIndex < photos.count - 1 { rightIndex += 1 }
                }
                .disabled(rightIndex == photos.count - 1)
            }

            Button("Share Comparison", systemImage: "square.and.arrow.up") {
                // Share selected photos
            }
        }
        .padding()
    }
}
```

---

## 11. Metrics

| Metric                      | Target          | Measurement                     |
| --------------------------- | --------------- | ------------------------------- |
| Condition tracking adoption | 15% of users    | Users with ≥1 tracked condition |
| Photos per condition        | 3+              | Average photos                  |
| Comparison usage            | 50% of trackers | Users who use compare           |
| Sharing usage               | 30% of trackers | Users who share with clinicians |
| Clinician feedback          | Survey          | Reported usefulness             |

---

## 12. Risks & Mitigations

| Risk               | Impact   | Mitigation                        |
| ------------------ | -------- | --------------------------------- |
| Privacy breach     | Critical | Encryption; biometric; short TTLs |
| Inappropriate use  | Medium   | Medical condition types only      |
| Storage costs      | Medium   | Retention policies; compression   |
| Poor photo quality | Low      | Guidance; quality detection       |

---

## 13. Dependencies

- Camera APIs
- Biometric authentication (LocalAuthentication)
- Supabase encrypted storage
- Share links infrastructure

---

## 14. Testing Requirements

- [ ] Unit tests for photo metadata
- [ ] Integration tests for storage and retrieval
- [ ] Security testing for access controls
- [ ] UI tests for capture flow
- [ ] Privacy review

---

## 15. Rollout Plan

1. **Alpha:** Basic photo capture and timeline
2. **Beta:** Comparison views; biometric protection
3. **GA:** Secure sharing with clinicians
4. **Post-GA:** Annotations; measurement tools

---

### Linkage

- Product: CuraKnot
- Stack: iOS Camera + LocalAuthentication + Supabase Storage
- Baseline: `./CuraKnot-spec.md`
- Related: Document Scanner, Share Links, Handoffs
