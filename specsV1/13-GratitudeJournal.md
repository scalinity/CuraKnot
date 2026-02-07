# Feature Spec 13 — Gratitude & Milestone Journal

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 4 (Lifestyle & Emotional)
> Differentiator: Emotional resilience in a clinically-focused category

---

## 1. Problem Statement

Caregiving is emotionally exhausting. Every app in the space focuses on clinical data — medications, symptoms, appointments. But caregiving also has moments of joy: "Dad smiled when the grandkids visited." "Mom remembered my birthday." These moments sustain caregivers through difficult times but are never captured.

A Gratitude & Milestone Journal adds emotional dimension to CuraKnot, combating compassion fatigue and reminding caregivers why they do this work.

---

## 2. Differentiation and Moat

- **Unique in category** — no caregiving app has emotional wellness features
- **Low implementation effort** — builds on existing handoff infrastructure
- **High emotional ROI** — creates loyalty and word-of-mouth
- **Reduces burnout** — validated psychological benefit of gratitude
- **Premium lever:** Photo memories, milestone celebrations, exportable journals

---

## 3. Goals

- [ ] G1: Dedicated space for positive moments and gratitude entries
- [ ] G2: Milestone tracking and celebrations (care journey markers)
- [ ] G3: Optional prompts to encourage regular entries
- [ ] G4: Private option (only visible to author) or shared with circle
- [ ] G5: Exportable "memory book" PDF
- [ ] G6: Integration with photos for visual memories

---

## 4. Non-Goals

- [ ] NG1: No gamification (no streaks, points, badges)
- [ ] NG2: No social sharing outside circle
- [ ] NG3: No AI-generated content
- [ ] NG4: No mandatory entries (always optional)

---

## 5. UX Flow

### 5.1 Journal Entry

```
┌─────────────────────────────────┐
│ ✨ Gratitude Journal            │
│ ═══════════════════════════════│
│                                 │
│ [Good Moment]  [Milestone]      │
│                                 │
│ What made you smile today?      │
│ ┌─────────────────────────────┐ │
│ │ Mom recognized me today     │ │
│ │ when I walked in. She said  │ │
│ │ my name and reached for     │ │
│ │ my hand. It was brief but   │ │
│ │ wonderful.                  │ │
│ └─────────────────────────────┘ │
│                                 │
│ [📷 Add Photo]                  │
│                                 │
│ Who can see this?               │
│ (○) Just me                     │
│ (●) Share with circle           │
│                                 │
│ [Save Memory]                   │
└─────────────────────────────────┘
```

### 5.2 Milestone Entry

```
┌─────────────────────────────────┐
│ 🎉 Record a Milestone           │
│ ═══════════════════════════════│
│                                 │
│ Milestone Type:                 │
│ [Anniversary] [Progress]        │
│ [First]       [Achievement]     │
│                                 │
│ Title:                          │
│ [1 Year Since Diagnosis   ]     │
│                                 │
│ Reflection:                     │
│ ┌─────────────────────────────┐ │
│ │ It's been one year since    │ │
│ │ Mom's Alzheimer's diagnosis.│ │
│ │ We've learned so much and   │ │
│ │ grown closer as a family... │ │
│ └─────────────────────────────┘ │
│                                 │
│ [📷 Add Photo]                  │
│                                 │
│ [Save Milestone]                │
└─────────────────────────────────┘
```

### 5.3 Journal View

```
┌─────────────────────────────────┐
│ ✨ Memories                      │
│ ═══════════════════════════════│
│                                 │
│ [All] [Good Moments] [Milestones]│
│                                 │
│ ─── February 2026 ─────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Feb 5 · Good Moment         │ │
│ │ Mom recognized me today     │ │
│ │ when I walked in...         │ │
│ │                 — Jane 💜   │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── January 2026 ──────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🎉 Jan 15 · Milestone       │ │
│ │ 1 Year Since Diagnosis      │ │
│ │                             │ │
│ │ [Photo]                     │ │
│ │                             │ │
│ │ It's been one year...       │ │
│ └─────────────────────────────┘ │
│                                 │
│ [+ New Entry]                   │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Entry Types

| Type        | Purpose             | Fields                            |
| ----------- | ------------------- | --------------------------------- |
| Good Moment | Daily gratitude/joy | Text, optional photo              |
| Milestone   | Significant markers | Title, type, text, optional photo |

### 6.2 Milestone Types

- **Anniversary** — Diagnosis date, care start, etc.
- **Progress** — First walk, eating independently, etc.
- **First** — First smile in weeks, first outing, etc.
- **Achievement** — Completed PT, reached a goal, etc.
- **Memory** — Special moment worth marking

### 6.3 Privacy Controls

- [ ] Private entries (only author can see)
- [ ] Shared entries (visible to circle)
- [ ] Default privacy setting per user
- [ ] Change visibility after creation

### 6.4 Prompts (Optional)

- [ ] Weekly prompt: "What made you smile this week?"
- [ ] Configurable prompt timing
- [ ] Can dismiss or disable prompts
- [ ] Gentle, never guilt-inducing

### 6.5 Photo Integration

- [ ] Attach photos to entries
- [ ] Photos stored with standard privacy controls
- [ ] Thumbnail preview in journal view
- [ ] Full-screen view on tap

### 6.6 Export

- [ ] Generate PDF "memory book"
- [ ] Include selected date range
- [ ] Include or exclude private entries
- [ ] Professional layout with photos
- [ ] CuraKnot branding (subtle)

---

## 7. Data Model

### 7.1 Journal Entries

```sql
CREATE TABLE IF NOT EXISTS journal_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Entry content
    entry_type text NOT NULL,  -- GOOD_MOMENT | MILESTONE
    title text,  -- Required for milestones
    content text NOT NULL,
    milestone_type text,  -- ANNIVERSARY | PROGRESS | FIRST | ACHIEVEMENT | MEMORY

    -- Photos
    photo_storage_keys text[],

    -- Privacy
    visibility text NOT NULL DEFAULT 'CIRCLE',  -- PRIVATE | CIRCLE

    -- Metadata
    entry_date date NOT NULL DEFAULT CURRENT_DATE,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_journal_entries_patient ON journal_entries(patient_id, entry_date DESC);
CREATE INDEX idx_journal_entries_author ON journal_entries(created_by, entry_date DESC);
```

### 7.2 Journal Prompts (System)

```sql
CREATE TABLE IF NOT EXISTS journal_prompts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_text text NOT NULL,
    prompt_type text NOT NULL,  -- GOOD_MOMENT | MILESTONE
    is_active boolean NOT NULL DEFAULT true
);

-- Seed prompts
INSERT INTO journal_prompts (prompt_text, prompt_type) VALUES
('What made you smile this week?', 'GOOD_MOMENT'),
('What small victory happened recently?', 'GOOD_MOMENT'),
('What are you grateful for in your caregiving journey?', 'GOOD_MOMENT'),
('Has anything improved recently?', 'MILESTONE'),
('Any special moments worth remembering?', 'GOOD_MOMENT');
```

### 7.3 User Preferences

```sql
-- Add to users table
ALTER TABLE users
ADD COLUMN IF NOT EXISTS journal_settings_json jsonb DEFAULT '{
    "promptsEnabled": true,
    "promptFrequency": "WEEKLY",
    "defaultVisibility": "CIRCLE"
}'::jsonb;
```

---

## 8. RLS & Security

- [ ] CIRCLE visibility: Readable by circle members
- [ ] PRIVATE visibility: Only readable by author
- [ ] All entries writable only by author
- [ ] Photos follow entry visibility

---

## 9. Edge Functions

### 9.1 generate-memory-book

```typescript
// POST /functions/v1/generate-memory-book

interface MemoryBookRequest {
  patientId: string;
  dateFrom?: string;
  dateTo?: string;
  includePrivate: boolean;
  includePhotos: boolean;
}

interface MemoryBookResponse {
  pdfUrl: string; // Signed URL
  entryCount: number;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Journal Entry View

```swift
struct JournalEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = JournalEntryViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry Type", selection: $viewModel.entryType) {
                        Text("Good Moment").tag(EntryType.goodMoment)
                        Text("Milestone").tag(EntryType.milestone)
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.entryType == .milestone {
                    Section {
                        TextField("Title", text: $viewModel.title)
                        Picker("Type", selection: $viewModel.milestoneType) {
                            ForEach(MilestoneType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                    }
                }

                Section(viewModel.entryType == .goodMoment ? "What made you smile?" : "Reflection") {
                    TextEditor(text: $viewModel.content)
                        .frame(minHeight: 150)
                }

                Section {
                    PhotoPicker(selectedPhotos: $viewModel.photos)
                }

                Section("Privacy") {
                    Picker("Who can see this?", selection: $viewModel.visibility) {
                        Text("Just me").tag(Visibility.private)
                        Text("Share with circle").tag(Visibility.circle)
                    }
                }
            }
            .navigationTitle(viewModel.entryType == .goodMoment ? "Good Moment" : "Milestone")
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
        }
    }
}
```

### 10.2 Journal List View

```swift
struct JournalListView: View {
    @StateObject private var viewModel = JournalListViewModel()
    @State private var showingNewEntry = false
    @State private var filter: EntryFilter = .all

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.groupedEntries, id: \.month) { group in
                    Section(group.monthHeader) {
                        ForEach(group.entries) { entry in
                            JournalEntryRow(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("Memories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Entry", systemImage: "plus") {
                        showingNewEntry = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        Button("Generate Memory Book") {
                            viewModel.generateMemoryBook()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewEntry) {
                JournalEntrySheet()
            }
        }
    }
}
```

### 10.3 Entry Row

```swift
struct JournalEntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if entry.entryType == .milestone {
                    Text("🎉")
                }
                Text(entry.entryDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(entry.entryType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if entry.visibility == .private {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let title = entry.title {
                Text(title)
                    .font(.headline)
            }

            Text(entry.content)
                .lineLimit(3)

            if !entry.photos.isEmpty {
                HStack {
                    ForEach(entry.photos.prefix(3), id: \.self) { photo in
                        Image(photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Text("— \(entry.authorName)")
                .font(.caption)
                .foregroundStyle(.purple)
        }
        .padding(.vertical, 4)
    }
}
```

---

## 11. Metrics

| Metric              | Target               | Measurement          |
| ------------------- | -------------------- | -------------------- |
| Journal adoption    | 25% of active users  | Users with ≥1 entry  |
| Entries per user    | 2+ per month         | Active journal users |
| Milestone entries   | 20% of entries       | Milestones / total   |
| Memory book exports | 10% of journal users | Exports per month    |
| User sentiment      | Positive feedback    | Survey/reviews       |

---

## 12. Risks & Mitigations

| Risk               | Impact | Mitigation                                        |
| ------------------ | ------ | ------------------------------------------------- |
| Feature unused     | Low    | Gentle prompts; discoverable UI                   |
| Feels forced       | Medium | Always optional; no gamification                  |
| Privacy concerns   | Medium | Clear visibility controls; default private option |
| Content moderation | Low    | Circle-only; no public sharing                    |

---

## 13. Dependencies

- Photo storage infrastructure (existing)
- PDF generation (existing)
- User preferences (existing)

---

## 14. Testing Requirements

- [ ] Unit tests for privacy filtering
- [ ] Integration tests for entry CRUD
- [ ] Integration tests for PDF generation
- [ ] UI tests for entry creation
- [ ] User acceptance testing

---

## 15. Rollout Plan

1. **Alpha:** Basic entry creation and list
2. **Beta:** Photo support; milestones
3. **GA:** Memory book export; prompts
4. **Post-GA:** Widgets; sharing outside circle

---

### Linkage

- Product: CuraKnot
- Stack: Supabase + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Caregiver Wellness, Photo storage
