import SwiftUI

// MARK: - Create Meeting View

struct CreateMeetingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let service: FamilyMeetingService
    let subscriptionManager: SubscriptionManager
    let onCreated: () -> Void

    @State private var title = ""
    @State private var scheduledDate = Date()
    @State private var format: MeetingFormat = .video
    @State private var meetingLink = ""
    @State private var isRecurring = false
    @State private var recurrenceRule = "WEEKLY"
    @State private var isCreating = false
    @State private var error: Error?
    @State private var showError = false

    private var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 200
    }

    private var isMeetingLinkValid: Bool {
        guard !meetingLink.isEmpty else { return true }
        guard let url = URL(string: meetingLink),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meeting Details") {
                    TextField("Meeting Title", text: $title)
                        .accessibilityLabel("Meeting title")
                        .accessibilityHint("Enter a title for the meeting")
                        .onChange(of: title) { _, newValue in
                            if newValue.count > 200 {
                                title = String(newValue.prefix(200))
                            }
                        }

                    DatePicker(
                        "Date & Time",
                        selection: $scheduledDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityLabel("Meeting date and time")
                    .accessibilityHint("Select when the meeting will take place")
                }

                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(MeetingFormat.allCases, id: \.self) { fmt in
                            Label(fmt.displayName, systemImage: fmt.icon)
                                .tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Meeting format")

                    if format == .video {
                        TextField("Meeting Link (optional)", text: $meetingLink)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .accessibilityLabel("Meeting link")
                            .accessibilityHint("Enter an optional video call URL")

                        if !meetingLink.isEmpty && !isMeetingLinkValid {
                            Text("Please enter a valid URL (https://...)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if subscriptionManager.currentPlan == .family {
                    Section("Recurring") {
                        Toggle("Repeat Meeting", isOn: $isRecurring)
                            .accessibilityLabel("Repeat meeting")
                            .accessibilityHint("Enable to schedule this meeting on a recurring basis")

                        if isRecurring {
                            Picker("Frequency", selection: $recurrenceRule) {
                                Text("Weekly").tag("WEEKLY")
                                Text("Biweekly").tag("BIWEEKLY")
                                Text("Monthly").tag("MONTHLY")
                            }
                            .accessibilityLabel("Recurrence frequency")
                        }
                    }
                }
            }
            .navigationTitle("New Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createMeeting()
                    }
                    .disabled(!isTitleValid || !isMeetingLinkValid || isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { error = nil }
            } message: {
                if let error {
                    let nsError = error as NSError
                    Text(nsError.domain.hasPrefix("FamilyMeeting") || nsError.domain == "CreateMeetingView"
                         ? error.localizedDescription
                         : "An unexpected error occurred. Please try again.")
                }
            }
            .onChange(of: error != nil) { _, hasError in
                showError = hasError
            }
        }
    }

    private func createMeeting() {
        guard let circle = appState.currentCircle,
              let patient = appState.currentPatient,
              let currentUser = appState.currentUser else { return }
        let userId = currentUser.id

        guard let circleUUID = UUID(uuidString: circle.id),
              let patientUUID = UUID(uuidString: patient.id),
              let userUUID = UUID(uuidString: userId) else {
            self.error = NSError(
                domain: "CreateMeetingView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid circle, patient, or user identifier"]
            )
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        isCreating = true

        Task {
            do {
                _ = try await service.createMeeting(
                    circleId: circleUUID,
                    patientId: patientUUID,
                    createdBy: userUUID,
                    title: trimmedTitle,
                    scheduledAt: scheduledDate,
                    format: format,
                    meetingLink: meetingLink.isEmpty ? nil : meetingLink,
                    recurrenceRule: isRecurring ? recurrenceRule : nil,
                    attendeeUserIds: []
                )
                onCreated()
                dismiss()
            } catch {
                self.error = error
                isCreating = false
            }
        }
    }
}
