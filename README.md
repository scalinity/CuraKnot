# CuraKnot

**Software for families who care.**

---

## The Problem

Thirty million Americans are family caregivers. They manage medications, coordinate appointments, track symptoms, and carry mental loads that do not fit in any calendar. Most of this work happens in text messages, phone calls, and memory.

The result is predictable: information falls through cracks. What the morning aide noticed does not reach the evening nurse. The medication change from last week's appointment does not make it into the family group chat. The question about dosage gets forgotten.

Caregiving is hard enough without adding communication failure.

---

## What CuraKnot Is

CuraKnot is a handoff operating system for family caregiving. It turns every care interaction into:

1. **A structured brief** — Voice note becomes extracted summary
2. **A shared timeline** — All family members see what happened
3. **Clear next actions** — Tasks with owners, due dates, reminders

The core loop is simple: record what happened, see what everyone else recorded, know what needs doing.

This is not a replacement for phone calls or visits. It is what happens between them.

---

## What We Built

We built CuraKnot because caregiving software tends toward either:

- **Medical-grade platforms** — Designed for institutions, unusable by families
- **Consumer wellness apps** — Focused on the patient, treating caregivers as afterthoughts

CuraKnot sits in the middle: serious enough to be useful, simple enough to actually get used.

### Core Features

| Feature | Purpose |
|---------|---------|
| **Care Circles** | Private spaces for families to coordinate |
| **Voice Handoffs** | 20-60 second recordings → AI-extracted summaries |
| **Shared Timeline** | Chronological view of all care events |
| **Task Management** | Actions extracted from handoffs, assigned, tracked |
| **Care Binder** | Medications, contacts, documents, insurance — searchable |
| **PDF Export** | Care summaries for doctor visits |

### Technical Approach

- **Voice capture**: Works offline, syncs when connected
- **Transcription**: OpenAI Whisper via Edge Functions
- **Structured extraction**: Claude identifies key fields (what changed, what is next, concerns, medications)
- **Real-time sync**: Supabase Realtime keeps family members current
- **Privacy**: Row Level Security enforces that you see only your circles

---

## Design Philosophy

### Handoff-First

Everything begins with capturing what happened. The rest — viewing, searching, tasking — builds from that. A good handoff system makes recording faster than texting.

### Structure Over Chat

Care coordination is not a conversation. It is a stream of facts, decisions, and action items. CuraKnot optimizes for clarity, not dialogue.

### Low Cognitive Load

Family caregivers are exhausted. The interface defaults wherever possible, minimizes taps, and does not require learning new conventions.

### Privacy by Design

Care information is sensitive. Sharing is explicit, not implied. Users control what each member sees.

---

## Project Structure

```
CuraKnot/
├── ios/                    # SwiftUI iOS application
│   ├── CuraKnot/
│   │   ├── App/           # Entry point, dependency injection
│   │   ├── Core/          # Models, services, networking
│   │   ├── Features/      # Feature modules
│   │   │   ├── Circles/   # Circle creation and management
│   │   │   ├── Handoff/   # Voice capture and review
│   │   │   ├── Timeline/  # Event feed with filtering
│   │   │   ├── Tasks/     # Task creation and assignment
│   │   │   └── Binder/    # Medication lists, contacts, docs
│   │   └── Resources/     # Assets, localizations
│   └── CuraKnotTests/
│
├── supabase/               # Backend infrastructure
│   ├── functions/         # Edge Functions
│   │   ├── transcribe/   # Whisper transcription
│   │   ├── extract-brief/ # Claude structured extraction
│   │   └── export-pdf/   # PDF generation
│   ├── migrations/       # Database schema
│   └── config.toml       # Supabase configuration
│
└── docs/                   # Architecture and specifications
```

---

## What We Are Proud Of

1. **Voice-first capture**: One tap to record, works without connectivity
2. **Extraction that works**: Claude reliably pulls out what changed, what is next, and what to watch
3. **Offline resilience**: No connectivity does not mean no progress
4. **Family-friendly permissions**: Roles match actual family dynamics (primary, backup, out-of-town)

---

## What We Would Do Differently

If we built this again:

- **Smarter task extraction**: Currently tasks are suggested; we would make them more automatic
- **Calendar integration**: Sync with Apple Calendar, Google Calendar
- **EHR lightweight connection**: Not a full integration, but structured export that loads into patient portals

---

## Getting Started

```bash
git clone https://github.com/scalinity/CuraKnot.git
cd CuraKnot

# Start Supabase
supabase start

# Apply migrations
supabase db push

# Open iOS project
cd ios && open CuraKnot.xcodeproj
```

Configure Supabase credentials in the iOS app. Development builds connect to local Supabase.

---

## Why This Matters

Family caregiving is invisible infrastructure. It keeps people healthy, out of hospitals, and connected. But it is fragile — dependent on memory, timing, and the availability of whoever knows what.

Good software cannot replace a family. But it can make family caregiving less fragile. That is what we are building.

---

**CuraKnot: Software for families who care.**
