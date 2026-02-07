# Feature Spec 14 — Family Video Message Board

> Date: 2026-02-05 | Priority: MEDIUM | Phase: 4 (Lifestyle & Emotional)
> Differentiator: Emotional connection layer — no competitor has secure family video

---

## 1. Problem Statement

Out-of-town family members want to stay connected but can't always help operationally. A phone call might be too much for the patient; a text feels impersonal. Grandchildren want to say "Hi Grandma!" but there's no easy, private way to share these moments.

A family video message board enables asynchronous, low-pressure connection. Family members can record short video messages that the patient (or caregivers) can watch anytime. This reduces isolation and lets everyone contribute emotionally even when they can't contribute operationally.

---

## 2. Differentiation and Moat

- **Unique in category** — no caregiving app has video messaging
- **Reduces patient isolation** — major quality-of-life issue
- **Enables distant family participation** — broader circle engagement
- **Creates emotional value** — beyond operational utility
- **Premium lever:** Longer videos, more storage, compilation exports

---

## 3. Goals

- [ ] G1: Record and share short video messages within circle
- [ ] G2: Simple playback interface optimized for elderly patients
- [ ] G3: Notification when new videos arrive
- [ ] G4: Basic moderation (circle members can flag/remove)
- [ ] G5: Storage management with retention policies
- [ ] G6: Optional compilation export for special occasions

---

## 4. Non-Goals

- [ ] NG1: No real-time video calling (use FaceTime/Zoom)
- [ ] NG2: No live streaming
- [ ] NG3: No editing tools beyond trim
- [ ] NG4: No public sharing

---

## 5. UX Flow

### 5.1 Video Board View

```
┌─────────────────────────────────┐
│ 💬 Family Messages for Mom       │
│ ═══════════════════════════════│
│                                 │
│ [Record a Message]              │
│                                 │
│ ─── New ───────────────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ [Video Thumbnail]           │ │
│ │        ▶️                    │ │
│ │                             │ │
│ │ From: Emma (Granddaughter)  │ │
│ │ "Hi Grandma! I miss you!"   │ │
│ │ Today · 0:32                │ │
│ └─────────────────────────────┘ │
│                                 │
│ ─── This Week ─────────────────│
│                                 │
│ ┌──────┐ ┌──────┐ ┌──────┐     │
│ │ [▶️] │ │ [▶️] │ │ [▶️] │     │
│ │ Mike │ │ Sarah│ │ Tom  │     │
│ └──────┘ └──────┘ └──────┘     │
│                                 │
│ ─── Earlier ───────────────────│
│ [...]                           │
└─────────────────────────────────┘
```

### 5.2 Recording View

```
┌─────────────────────────────────┐
│ Record a Message                │
│ ═══════════════════════════════│
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │     [Camera Preview]        │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ For: [Mom             ▼]        │
│                                 │
│ Caption (optional):             │
│ [Hi Grandma! Miss you!   ]      │
│                                 │
│ Max length: 60 seconds          │
│                                 │
│        [🔴 Record]              │
│                                 │
│ Tips:                           │
│ • Speak clearly and smile       │
│ • Good lighting helps           │
│ • Keep it short and sweet       │
└─────────────────────────────────┘
```

### 5.3 Playback View (Optimized for Patients)

```
┌─────────────────────────────────┐
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │                             │ │
│ │     [Full Screen Video]     │ │
│ │                             │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│        From: Emma               │
│   "Hi Grandma! I miss you!"     │
│                                 │
│   [◀️ Previous] [▶️ Next]       │
│                                 │
│        [❤️ Send Love]           │
│                                 │
└─────────────────────────────────┘
```

---

## 6. Functional Requirements

### 6.1 Video Recording

- [ ] Maximum duration: 60 seconds (configurable by plan)
- [ ] Front and rear camera support
- [ ] Basic trim before posting
- [ ] Caption/message text (optional)
- [ ] Select target patient

### 6.2 Video Playback

- [ ] Simple, large UI optimized for elderly
- [ ] Auto-play option
- [ ] Previous/next navigation
- [ ] "Send Love" reaction (heart)
- [ ] Loop option for favorite videos

### 6.3 Storage & Retention

- [ ] Videos stored in Supabase Storage
- [ ] Compression for reasonable file sizes
- [ ] Retention policy: 90 days default
- [ ] Manual "save forever" option
- [ ] Storage quota per circle (by plan)

### 6.4 Notifications

- [ ] Push notification when new video arrives
- [ ] Configurable notification preferences
- [ ] Digest option (daily summary)

### 6.5 Moderation

- [ ] Any circle member can flag inappropriate content
- [ ] Admin/owner can remove videos
- [ ] Audit log of removals

### 6.6 Compilation Export

- [ ] Combine selected videos into single file
- [ ] Add transitions and title cards
- [ ] Export for special occasions (birthday, anniversary)

---

## 7. Data Model

### 7.1 Video Messages

```sql
CREATE TABLE IF NOT EXISTS video_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id uuid NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    patient_id uuid NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    created_by uuid NOT NULL,

    -- Video
    storage_key text NOT NULL,
    thumbnail_key text,
    duration_seconds int NOT NULL,
    file_size_bytes bigint NOT NULL,

    -- Content
    caption text,

    -- Status
    status text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | FLAGGED | REMOVED
    flagged_by uuid,
    flagged_at timestamptz,
    removed_by uuid,
    removed_at timestamptz,
    removal_reason text,

    -- Retention
    save_forever boolean NOT NULL DEFAULT false,
    expires_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_video_messages_patient ON video_messages(patient_id, created_at DESC);
CREATE INDEX idx_video_messages_circle ON video_messages(circle_id, created_at DESC);
CREATE INDEX idx_video_messages_expires ON video_messages(expires_at) WHERE expires_at IS NOT NULL;
```

### 7.2 Video Reactions

```sql
CREATE TABLE IF NOT EXISTS video_reactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    video_message_id uuid NOT NULL REFERENCES video_messages(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    reaction_type text NOT NULL DEFAULT 'LOVE',  -- LOVE (❤️)
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(video_message_id, user_id)
);
```

### 7.3 Video Views

```sql
CREATE TABLE IF NOT EXISTS video_views (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    video_message_id uuid NOT NULL REFERENCES video_messages(id) ON DELETE CASCADE,
    viewed_by uuid NOT NULL,
    viewed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_video_views_video ON video_views(video_message_id);
```

---

## 8. RLS & Security

- [ ] video_messages: Readable by circle members; writable by contributors+
- [ ] Videos stored with signed URLs only
- [ ] No public access
- [ ] Moderation audit trail
- [ ] Storage encryption at rest

---

## 9. Edge Functions

### 9.1 process-video-upload

```typescript
// POST /functions/v1/process-video-upload
// Handles video processing after upload

interface ProcessVideoRequest {
  storageKey: string;
  circleId: string;
  patientId: string;
  caption?: string;
}

interface ProcessVideoResponse {
  videoMessageId: string;
  thumbnailKey: string;
  duration: number;
}
```

### 9.2 cleanup-expired-videos (Cron)

```typescript
// Runs daily
// Removes videos past retention date

async function cleanupExpiredVideos(): Promise<{
  videosRemoved: number;
  storageFreed: number;
}>;
```

### 9.3 generate-video-compilation

```typescript
// POST /functions/v1/generate-video-compilation

interface CompilationRequest {
  videoIds: string[];
  title: string;
  includeTransitions: boolean;
}

interface CompilationResponse {
  compilationUrl: string; // Signed URL
  expiresAt: string;
}
```

---

## 10. iOS Implementation Notes

### 10.1 Video Board View

```swift
struct VideoBoardView: View {
    @StateObject private var viewModel = VideoBoardViewModel()
    @State private var showingRecorder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Record button
                    Button {
                        showingRecorder = true
                    } label: {
                        Label("Record a Message", systemImage: "video.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // New videos
                    if !viewModel.newVideos.isEmpty {
                        VideoSection(title: "New", videos: viewModel.newVideos)
                    }

                    // This week
                    if !viewModel.thisWeekVideos.isEmpty {
                        VideoSection(title: "This Week", videos: viewModel.thisWeekVideos)
                    }

                    // Earlier
                    if !viewModel.earlierVideos.isEmpty {
                        VideoSection(title: "Earlier", videos: viewModel.earlierVideos)
                    }
                }
            }
            .navigationTitle("Family Messages")
        }
        .fullScreenCover(isPresented: $showingRecorder) {
            VideoRecorderView()
        }
    }
}
```

### 10.2 Video Recorder

```swift
struct VideoRecorderView: View {
    @StateObject private var viewModel = VideoRecorderViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: viewModel.captureSession)

            VStack {
                // Top bar
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                    Spacer()
                    Text(viewModel.recordingDuration)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .cornerRadius(8)
                    Spacer()
                    Button {
                        viewModel.flipCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .foregroundStyle(.white)
                    }
                }
                .padding()

                Spacer()

                // Record button
                Button {
                    viewModel.toggleRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(viewModel.isRecording ? .white : .red)
                            .frame(width: viewModel.isRecording ? 30 : 60, height: viewModel.isRecording ? 30 : 60)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
                    }
                }
                .padding(.bottom, 40)

                // Time limit indicator
                Text("Max: 60 seconds")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom)
            }
        }
        .sheet(item: $viewModel.recordedVideo) { video in
            VideoReviewSheet(video: video, onPost: viewModel.postVideo)
        }
    }
}
```

### 10.3 Patient-Friendly Playback

```swift
struct PatientPlaybackView: View {
    @StateObject private var viewModel: PatientPlaybackViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Large video player
            VideoPlayer(player: viewModel.player)
                .aspectRatio(16/9, contentMode: .fit)
                .cornerRadius(16)

            // Simple info
            VStack(spacing: 8) {
                Text("From: \(viewModel.currentVideo.authorName)")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let caption = viewModel.currentVideo.caption {
                    Text("\"\(caption)\"")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Large, easy-to-tap navigation
            HStack(spacing: 40) {
                Button {
                    viewModel.previousVideo()
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 60))
                }
                .disabled(!viewModel.hasPrevious)

                Button {
                    viewModel.sendLove()
                } label: {
                    VStack {
                        Image(systemName: viewModel.hasReacted ? "heart.fill" : "heart")
                            .font(.system(size: 50))
                            .foregroundStyle(.red)
                        Text("Send Love")
                            .font(.caption)
                    }
                }

                Button {
                    viewModel.nextVideo()
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 60))
                }
                .disabled(!viewModel.hasNext)
            }
            .padding()
        }
        .padding()
    }
}
```

---

## 11. Metrics

| Metric               | Target         | Measurement                   |
| -------------------- | -------------- | ----------------------------- |
| Video board adoption | 20% of circles | Circles with ≥1 video         |
| Videos per circle    | 3+ per month   | Active circles                |
| View rate            | 80%            | Videos viewed / videos posted |
| Reaction rate        | 50%            | Videos with reactions         |
| Contributor breadth  | 3+ people      | Unique posters per circle     |

---

## 12. Risks & Mitigations

| Risk                  | Impact | Mitigation                                    |
| --------------------- | ------ | --------------------------------------------- |
| Storage costs         | High   | Retention limits; compression; quotas         |
| Inappropriate content | Medium | Moderation tools; audit trail                 |
| Low adoption          | Medium | Gentle prompts; easy recording                |
| Technical complexity  | Medium | Standard video APIs; Edge Function processing |

---

## 13. Dependencies

- Video recording APIs (AVFoundation)
- Video playback (AVPlayer)
- Supabase Storage (video files)
- Push notifications

---

## 14. Testing Requirements

- [ ] Unit tests for video metadata
- [ ] Integration tests for upload flow
- [ ] Integration tests for retention cleanup
- [ ] UI tests for recorder and player
- [ ] Performance testing (video processing)

---

## 15. Rollout Plan

1. **Alpha:** Basic recording and playback
2. **Beta:** Reactions; retention policies
3. **GA:** Patient-optimized playback; notifications
4. **Post-GA:** Compilation exports; longer videos

---

### Linkage

- Product: CuraKnot
- Stack: AVFoundation + AVPlayer + Supabase Storage
- Baseline: `./CuraKnot-spec.md`
- Related: Gratitude Journal, Circle features
