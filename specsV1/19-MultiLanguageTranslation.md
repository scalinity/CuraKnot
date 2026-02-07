# Feature Spec 19 — Multi-Language Handoff Translation

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 5 (Expansion)
> Differentiator: Expands addressable market to multilingual families

---

## 1. Problem Statement

The US has 67 million Spanish speakers, plus millions more who speak Chinese, Vietnamese, Tagalog, Korean, and other languages. Multigenerational caregiving families often span language barriers: Spanish-speaking grandparents, English-speaking adult children, or professional caregivers who speak different languages than family members.

Current caregiving apps assume everyone speaks the same language. Multi-language translation enables handoffs, binder content, and tasks to be consumed in each user's preferred language, making CuraKnot inclusive for multicultural families.

---

## 2. Differentiation and Moat

- **Market expansion** — 20%+ of US families are multilingual
- **Professional caregiver inclusion** — hired caregivers often speak different languages
- **Cultural competency signal** — shows respect for diverse families
- **Network effects** — multilingual users invite multilingual circles
- **Premium lever:** Professional medical translation, custom terminology

---

## 3. Goals

- [ ] G1: User-selectable preferred language
- [ ] G2: Real-time translation of handoffs on read
- [ ] G3: Translation of Care Binder content
- [ ] G4: Translation of tasks and reminders
- [ ] G5: Original language always preserved
- [ ] G6: Medical term accuracy with glossary support

---

## 4. Non-Goals

- [ ] NG1: No real-time voice translation
- [ ] NG2: No certified medical translation (disclaimer required)
- [ ] NG3: No translation of scanned documents
- [ ] NG4: No app UI localization (separate effort)

---

## 5. UX Flow

### 5.1 Language Preference Setup

```
┌─────────────────────────────────┐
│ Language Settings               │
│ ═══════════════════════════════│
│                                 │
│ Your Preferred Language:        │
│ [English                   ▼]  │
│                                 │
│ ─── Available Languages ──────│
│ • English                       │
│ • Español (Spanish)             │
│ • 中文 (Chinese)                │
│ • Tiếng Việt (Vietnamese)       │
│ • 한국어 (Korean)               │
│ • Tagalog                       │
│ • Français (French)             │
│                                 │
│ When reading content in other   │
│ languages, I want to:           │
│                                 │
│ (●) Auto-translate to my        │
│     preferred language          │
│                                 │
│ (○) Show original with          │
│     translation option          │
│                                 │
│ (○) Always show original        │
│                                 │
│ [Save Preferences]              │
└─────────────────────────────────┘
```

### 5.2 Translated Handoff View

```
┌─────────────────────────────────┐
│ ← Handoff                       │
│ ═══════════════════════════════│
│                                 │
│ 🌐 Translated from Spanish      │
│ [View Original]                 │
│                                 │
│ Feb 5, 2026 · 3:30 PM           │
│ By: Maria (Professional Aide)   │
│                                 │
│ ─── Summary ──────────────────│
│                                 │
│ "Mom had a good day today. She  │
│ ate well at lunch and walked    │
│ around the garden for 15        │
│ minutes. Blood pressure was     │
│ normal at 128/82."              │
│                                 │
│ ─── Medications Given ────────│
│                                 │
│ ✓ Lisinopril 10mg - 8:00 AM     │
│ ✓ Metformin 500mg - with lunch  │
│                                 │
│ ─── Questions ────────────────│
│                                 │
│ • Is it okay for her to skip    │
│   afternoon snack if not hungry?│
│                                 │
│ ─── Original (Spanish) ───────│
│ ┌─────────────────────────────┐ │
│ │ "Mamá tuvo un buen día hoy. │ │
│ │ Comió bien en el almuerzo   │ │
│ │ y caminó por el jardín..."  │ │
│ │ [Show Full]                 │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

### 5.3 Writing in Non-English

```
┌─────────────────────────────────┐
│ New Handoff                     │
│ ═══════════════════════════════│
│                                 │
│ 🎤 Recording in: Español        │
│ [Change Language]               │
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │     [Audio Waveform]        │ │
│ │                             │ │
│ │        ◉ 0:45               │ │
│ └─────────────────────────────┘ │
│                                 │
│ Speak naturally in Spanish.     │
│ Other circle members will see   │
│ translations in their language. │
│                                 │
│ [Stop Recording]                │
└─────────────────────────────────┘
```

### 5.4 Circle Language Overview

```
┌─────────────────────────────────┐
│ Circle Language Settings        │
│ ═══════════════════════════════│
│                                 │
│ Circle Languages Used:          │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ English                     │ │
│ │ • Jane (you)                │ │
│ │ • Mike                      │ │
│ │ • Tom                       │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Español                     │ │
│ │ • Maria (Aide)              │ │
│ │ • Rosa (Aunt)               │ │
│ └─────────────────────────────┘ │
│                                 │
│ Translation is automatic when   │
│ members have different language │
│ preferences.                    │
│                                 │
│ ─── Medical Terms ────────────│
│                                 │
│ Custom terms for this circle:   │
│ [+ Add Custom Term]             │
│                                 │
│ • "La presión" = Blood pressure │
│ • "Azúcar" = Blood sugar        │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Supported Languages (Phase 1)

| Language   | Code | Priority  |
| ---------- | ---- | --------- |
| English    | en   | Primary   |
| Spanish    | es   | Primary   |
| Chinese    | zh   | Primary   |
| Vietnamese | vi   | Secondary |
| Korean     | ko   | Secondary |
| Tagalog    | tl   | Secondary |
| French     | fr   | Secondary |

### 6.2 Translation Scope

- [ ] Handoff text content (summary, observations, questions)
- [ ] Binder item names and descriptions
- [ ] Task titles and descriptions
- [ ] Notification text
- [ ] Comments and replies

### 6.3 Translation Features

- [ ] On-read translation (not stored, computed)
- [ ] Original always preserved
- [ ] Toggle between original and translated
- [ ] Medical term glossary support
- [ ] Custom circle terminology

### 6.4 Medical Term Handling

- [ ] Built-in medical glossary per language pair
- [ ] Circle-specific custom terms
- [ ] Flag uncertain translations
- [ ] Never translate medication names

### 6.5 Voice Handoff Integration

- [ ] Detect spoken language automatically
- [ ] Transcribe in original language
- [ ] Store original language metadata
- [ ] Translate on consumption

---

## 7. Data Model

### 7.1 User Language Preferences

```sql
-- Add to users table
ALTER TABLE users
ADD COLUMN IF NOT EXISTS language_preferences_json jsonb DEFAULT '{
    "preferredLanguage": "en",
    "translationMode": "AUTO",
    "showOriginal": false
}'::jsonb;
```

### 7.2 Content Language Metadata

```sql
-- Add to handoffs table
ALTER TABLE handoffs
ADD COLUMN IF NOT EXISTS source_language text DEFAULT 'en';

-- Add to binder_items table
ALTER TABLE binder_items
ADD COLUMN IF NOT EXISTS source_language text DEFAULT 'en';

-- Add to tasks table
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS source_language text DEFAULT 'en';
```

### 7.3 Translation Cache

```sql
CREATE TABLE IF NOT EXISTS translation_cache (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Source
    source_text_hash text NOT NULL,  -- SHA256 of source text
    source_language text NOT NULL,
    target_language text NOT NULL,

    -- Translation
    translated_text text NOT NULL,

    -- Quality
    confidence_score decimal(3, 2),  -- 0.00 to 1.00
    contains_medical_terms boolean NOT NULL DEFAULT false,

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL DEFAULT now() + interval '30 days',

    UNIQUE(source_text_hash, source_language, target_language)
);

CREATE INDEX idx_translation_cache_lookup ON translation_cache(source_text_hash, source_language, target_language);
CREATE INDEX idx_translation_cache_expires ON translation_cache(expires_at);
```

### 7.4 Medical Glossary

```sql
CREATE TABLE IF NOT EXISTS medical_glossary (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid REFERENCES circles(id) ON DELETE CASCADE,  -- NULL for system-wide

    -- Term
    source_language text NOT NULL,
    source_term text NOT NULL,
    target_language text NOT NULL,
    target_term text NOT NULL,

    -- Context
    category text,  -- MEDICATION | CONDITION | PROCEDURE | MEASUREMENT
    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(circle_id, source_term, source_language, target_language)
);

CREATE INDEX idx_medical_glossary_lookup ON medical_glossary(source_term, source_language, target_language);
```

---

## 8. RLS & Security

- [ ] translation_cache: System-managed, not user-accessible
- [ ] medical_glossary: System entries readable by all; circle entries by circle members
- [ ] User language preferences follow standard user access
- [ ] Translated content inherits source content RLS

---

## 9. Edge Functions

### 9.1 translate-content

```typescript
// POST /functions/v1/translate-content

interface TranslateRequest {
  text: string;
  sourceLanguage: string;
  targetLanguage: string;
  circleId?: string; // For custom glossary lookup
  contentType: "HANDOFF" | "BINDER" | "TASK" | "NOTIFICATION";
}

interface TranslateResponse {
  translatedText: string;
  confidenceScore: number;
  medicalTermsFound: string[];
  disclaimer: boolean; // True if medical content
}
```

### 9.2 detect-language

```typescript
// POST /functions/v1/detect-language

interface DetectLanguageRequest {
  text: string;
}

interface DetectLanguageResponse {
  detectedLanguage: string;
  confidence: number;
  alternatives: {
    language: string;
    confidence: number;
  }[];
}
```

### 9.3 cleanup-translation-cache (Cron)

```typescript
// Runs daily
// Removes expired translations

async function cleanupTranslationCache(): Promise<{
  entriesRemoved: number;
}>;
```

---

## 10. iOS Implementation Notes

### 10.1 Translation Service

```swift
actor TranslationService {
    private let supabase: SupabaseClient
    private let cache = NSCache<NSString, TranslatedContent>()

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        circleId: String? = nil,
        contentType: ContentType
    ) async throws -> TranslatedContent {
        // Check local cache first
        let cacheKey = "\(text.hashValue)-\(sourceLanguage)-\(targetLanguage)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Call Edge Function
        let response = try await supabase.functions.invoke(
            "translate-content",
            options: .init(body: [
                "text": text,
                "sourceLanguage": sourceLanguage,
                "targetLanguage": targetLanguage,
                "circleId": circleId as Any,
                "contentType": contentType.rawValue
            ])
        )

        let result: TranslatedContent = try response.decode()
        cache.setObject(result, forKey: cacheKey)
        return result
    }
}
```

### 10.2 Translated Handoff View

```swift
struct TranslatedHandoffView: View {
    let handoff: Handoff
    @StateObject private var viewModel: TranslatedHandoffViewModel
    @State private var showingOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Translation banner
            if handoff.sourceLanguage != viewModel.userLanguage {
                HStack {
                    Image(systemName: "globe")
                    Text("Translated from \(handoff.sourceLanguage.displayName)")
                        .font(.caption)
                    Spacer()
                    Button(showingOriginal ? "Show Translation" : "View Original") {
                        showingOriginal.toggle()
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            // Content
            if showingOriginal {
                OriginalContentView(handoff: handoff)
            } else {
                TranslatedContentView(
                    handoff: handoff,
                    translation: viewModel.translation
                )
            }

            // Medical disclaimer
            if viewModel.translation?.containsMedicalTerms == true {
                MedicalTranslationDisclaimer()
            }
        }
        .task {
            await viewModel.loadTranslation(for: handoff)
        }
    }
}

struct MedicalTranslationDisclaimer: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("This translation contains medical terms. Please verify critical information with a healthcare provider.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}
```

### 10.3 Language Settings View

```swift
struct LanguageSettingsView: View {
    @StateObject private var viewModel = LanguageSettingsViewModel()

    var body: some View {
        Form {
            Section("Your Language") {
                Picker("Preferred Language", selection: $viewModel.preferredLanguage) {
                    ForEach(SupportedLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
            }

            Section("Translation Behavior") {
                Picker("When reading other languages", selection: $viewModel.translationMode) {
                    Text("Auto-translate").tag(TranslationMode.auto)
                    Text("Show original, offer translation").tag(TranslationMode.onDemand)
                    Text("Always show original").tag(TranslationMode.off)
                }
            }

            if viewModel.translationMode != .off {
                Section {
                    Toggle("Show original alongside translation", isOn: $viewModel.showOriginal)
                } footer: {
                    Text("When enabled, you'll see both the original text and the translation.")
                }
            }
        }
        .navigationTitle("Language Settings")
    }
}
```

### 10.4 Custom Glossary Editor

```swift
struct GlossaryEditorView: View {
    let circleId: String
    @StateObject private var viewModel: GlossaryEditorViewModel

    var body: some View {
        List {
            Section {
                ForEach(viewModel.customTerms) { term in
                    GlossaryTermRow(term: term)
                }
                .onDelete { viewModel.deleteTerms(at: $0) }

                Button("Add Custom Term", systemImage: "plus") {
                    viewModel.showingAddTerm = true
                }
            } header: {
                Text("Circle-Specific Terms")
            } footer: {
                Text("Add terms specific to your loved one's care. These will be used during translation.")
            }

            Section("System Medical Glossary") {
                Text("CuraKnot includes a built-in medical glossary covering common conditions, medications, and procedures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Medical Glossary")
        .sheet(isPresented: $viewModel.showingAddTerm) {
            AddGlossaryTermSheet(circleId: circleId)
        }
    }
}
```

---

## 11. Metrics

| Metric                | Target            | Measurement                     |
| --------------------- | ----------------- | ------------------------------- |
| Multilingual circles  | 15% of circles    | Circles with 2+ languages       |
| Translation usage     | 80%               | Auto-translate enabled          |
| Translation accuracy  | 95%+              | User corrections / translations |
| Custom glossary usage | 20% of ml circles | Circles with custom terms       |
| Language coverage     | 7 languages       | Supported languages             |

---

## 12. Risks & Mitigations

| Risk                   | Impact   | Mitigation                        |
| ---------------------- | -------- | --------------------------------- |
| Medical mistranslation | Critical | Disclaimer; glossary; flag terms  |
| Translation latency    | Medium   | Aggressive caching; async loading |
| Translation costs      | Medium   | Cache reuse; rate limiting        |
| Unsupported languages  | Low      | Clear language list; request form |

---

## 13. Dependencies

- Translation API (Google Translate, DeepL, or similar)
- Language detection API
- Medical terminology database
- ASR language detection (existing)

---

## 14. Testing Requirements

- [ ] Unit tests for translation service
- [ ] Integration tests for cache behavior
- [ ] Medical term accuracy testing
- [ ] UI tests for language switching
- [ ] Performance testing for translation latency

---

## 15. Rollout Plan

1. **Alpha:** English ↔ Spanish only; basic translation
2. **Beta:** Add Chinese, Vietnamese; caching
3. **GA:** Full language support; custom glossary
4. **Post-GA:** Voice detection; document translation

---

### Linkage

- Product: CuraKnot
- Stack: Translation API + Supabase + iOS SwiftUI
- Baseline: `./CuraKnot-spec.md`
- Related: Voice Handoffs, Care Binder, Tasks
