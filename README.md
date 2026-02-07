# CuraKnot

**A handoff operating system for family caregiving.**

> Turn every care interaction into a structured brief, shared timeline, and clear next actions for a care circle.

![Swift](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17+-blue?logo=apple&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Backend-3FCF8E?logo=supabase&logoColor=white)
![License](https://img.shields.io/badge/License-Proprietary-yellow)

---

## Table of Contents

- [Motivation](#motivation)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Core Concepts](#core-concepts)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## Motivation

Family caregivers face a fragmented reality: medical appointments, medication schedules, symptom observations, insurance calls, and constant information handoffs between family members. Critical information gets lost in text messages, phone calls, and memory gaps.

**CuraKnot** is a handoff operating system for family caregiving. It turns every care interaction into a structured brief, shared timeline, and clear next actions for a care circle.

- **Primary value:** Reduce handoff loss (what changed, what is next, who owns it)
- **Core loop:** Record 20-60s voice note → transcription → structured brief → timeline + tasks + notifications
- **Users:** Family caregivers coordinating around one or more patients

---

## Features

### Core Features (MVP)

| Feature | Description |
|---------|-------------|
| **Care Circles** | Invite-based membership with roles (Primary, Backup, Out-of-town) |
| **Voice Handoffs** | 20-60s voice notes converted to structured briefs via AI transcription |
| **Shared Timeline** | Chronological feed of all care events with filtering and search |
| **Task Management** | Create/assign tasks from handoffs with reminders and due dates |
| **Care Binder** | Structured reference data: medications, contacts, documents, insurance |
| **Care Summary Export** | PDF export for clinician visits or facility conversations |
| **Offline Support** | Capture handoffs offline, sync when connectivity restored |

### User Personas

| Persona | Description | Key Needs |
|---------|-------------|-----------|
| **Primary Caregiver** | Does most communication | Capture + delegation, quick entry |
| **Backup Caregiver** | Helps intermittently | Concise briefs, clear tasks |
| **Out-of-town Family** | Wants updates without noise | Limited actions, high-level view |
| **Professional Helper** | Home aide/doula (Phase 2) | Constrained permissions |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **iOS Client** | SwiftUI, Swift 5.9+, iOS 17+ |
| **Backend** | Supabase (PostgreSQL, Edge Functions, Auth, Realtime) |
| **Voice** | Whisper transcription via Edge Functions |
| **AI** | Claude for structured brief extraction |
| **Authentication** | Sign in with Apple, Google OAuth |
| **Notifications** | APNs with local notifications for reminders |
| **Storage** | Supabase Storage for voice notes and attachments |

---

## Architecture

```
                    ┌─────────────────────────────────┐
                    │         iOS Client (SwiftUI)     │
                    │                                  │
                    │  • Voice capture & transcription │
                    │  • Handoff creation             │
                    │  • Timeline view                │
                    │  • Task management              │
                    │  • Binder (meds, contacts, docs) │
                    └──────────────┬──────────────────┘
                                   │
                         HTTPS / WSS
                                   │
                    ┌──────────────▼──────────────────┐
                    │       Supabase Platform           │
                    │                                  │
                    │  Auth (Apple, Google)            │
                    │  PostgreSQL + Row Level Security  │
                    │  Edge Functions (Deno/TypeScript) │
                    │  Realtime (WebSocket)             │
                    │  Storage (Audio/Media)           │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │       External Services          │
                    │                                  │
                    │  OpenAI Whisper — Transcription  │
                    │  Anthropic Claude — Brief extract│
                    └─────────────────────────────────┘
```

### Data Flow

1. User records voice note (works offline)
2. On reconnect, audio uploads to Supabase Storage
3. Edge Function triggers Whisper transcription
4. Claude extracts structured fields from transcript
5. Handoff created in database with tasks
6. Circle members notified via push
7. Timeline updates in real-time via WebSocket

---

## Getting Started

### Prerequisites

- Xcode 15+
- Node.js 18+ (for Edge Functions)
- Supabase CLI
- Apple Developer account

### Installation

```bash
# Clone the repository
git clone https://github.com/scalinity/CuraKnot.git
cd CuraKnot

# Start local Supabase
supabase start

# Apply migrations
supabase db push

# Open iOS project
cd ios
open CuraKnot.xcodeproj
```

### Environment Configuration

```bash
# Supabase local URL (default)
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=your-anon-key

# Production (when deploying)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

### Running the App

```bash
# In Xcode, select a simulator and run (Cmd+R)
# Default: iPhone 17 Pro simulator
```

### Building Edge Functions

```bash
# Deploy all functions
supabase functions deploy

# Deploy specific function
supabase functions deploy generate-brief
```

---

## Project Structure

```
CuraKnot/
├── ios/                          # iOS app
│   ├── CuraKnot/                # Main app target
│   │   ├── App/                 # App entry, DI container
│   │   ├── Core/               # Models, services, extensions
│   │   ├── Features/           # Feature modules
│   │   │   ├── Circles/        # Care circle management
│   │   │   ├── Handoff/        # Voice handoff capture
│   │   │   ├── Timeline/        # Shared timeline view
│   │   │   ├── Tasks/          # Task management
│   │   │   ├── Binder/         # Care binder (meds, contacts)
│   │   │   └── Settings/       # User and circle settings
│   │   └── Resources/          # Assets, strings
│   └── CuraKnotTests/          # Unit tests
│
├── supabase/                     # Backend
│   ├── functions/               # Edge Functions
│   │   ├── generate-brief/     # Voice → structured brief
│   │   ├── create-task/        # Task creation handler
│   │   └── export-summary/     # PDF summary generator
│   │
│   ├── migrations/             # Database migrations
│   ├── config.toml            # Supabase configuration
│   └── .env.example           # Environment template
│
├── docs/                        # Documentation
│   ├── CLAUDE.md              # AI coding instructions
│   ├── runbooks.md            # Operational procedures
│   └── architecture.md        # Architecture decisions
│
└── specsV1/                    # Product specifications
```

---

## Core Concepts

### Care Circle

A shared space for coordinating care around one or more patients. Features:

- **Members:** Users with roles and permissions
- **Patients:** Care recipients with conditions and facilities
- **Handoffs:** Structured briefs from voice notes
- **Tasks:** Actionable items from handoffs
- **Binder:** Reference data (meds, contacts, docs, insurance)

### Roles & Permissions

| Role | Permissions |
|------|-------------|
| **Primary** | Full access: create handoffs, manage tasks, edit binder, invite members |
| **Backup** | Create handoffs, manage assigned tasks, view all |
| **Out-of-town** | View handoffs, limited task assignment |
| **Viewer** | Read-only access (future Phase 2) |

### Handoff Structure

A handoff extracted from voice contains:

```typescript
interface Handoff {
  id: string;
  circleId: string;
  patientId: string;
  authorId: string;

  // Extracted content
  summary: string;           // 2-3 sentence summary
  whatChanged: string[];      // Key status changes
  whatNext: string[];        // Action items
  concerns: string[];        // Items to watch
  medications: string[];      // Medication changes/notes
  appointments: string[];    // Upcoming appointments

  // Audio
  audioUrl: string;
  transcription: string;

  // Metadata
  createdAt: Date;
  source: 'voice' | 'text';
}
```

### Tasks

```typescript
interface Task {
  id: string;
  circleId: string;
  handoffId?: string;        // Link to source handoff
  patientId: string;

  title: string;
  description?: string;
  assigneeId?: string;
  dueDate?: Date;
  reminderAt?: Date;

  status: 'pending' | 'in_progress' | 'completed' | 'cancelled';
  priority: 'low' | 'medium' | 'high' | 'urgent';

  createdAt: Date;
  completedAt?: Date;
}
```

---

## Security

### Data Protection

- **Row Level Security (RLS):** All tables enforce user-level data isolation
- **Encryption:** Voice notes encrypted at rest via Supabase Storage
- **Audit Logging:** Immutable log of sensitive actions

### Privacy Features

- **Explicit sharing:** Users control what circle members see
- **Minimal data retention:** Voice notes can be auto-deleted after processing
- **No third-party sharing:** Care data never sold or shared

### Offline Security

- Local encryption of pending handoffs
- Secure token storage in Keychain
- No caching of sensitive data in plaintext

---

## Contributing

CuraKnot is a proprietary project. For contribution guidelines, contact the repository owner.

---

## License

Proprietary. All rights reserved.

---

<p align="center">
  <em>Building the operating system for family caregiving — because care should not be complicated.</em>
</p>
