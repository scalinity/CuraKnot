import SwiftUI

// MARK: - Wellness Settings View

/// Settings for wellness preferences including reminder configuration
struct WellnessSettingsView: View {
    @State private var preferences: WellnessPreferences?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    private let wellnessService: WellnessService

    private let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    init(wellnessService: WellnessService) {
        self.wellnessService = wellnessService
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if let prefs = preferences {
                    reminderSection(prefs: prefs)
                    alertSection(prefs: prefs)
                    privacySection(prefs: prefs)
                }
            }
            .navigationTitle("Wellness Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadPreferences()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Reminder Section

    @ViewBuilder
    private func reminderSection(prefs: WellnessPreferences) -> some View {
        Section {
            Toggle("Weekly Reminders", isOn: Binding(
                get: { prefs.enableWeeklyReminders },
                set: { newValue in
                    var updated = prefs
                    updated.enableWeeklyReminders = newValue
                    preferences = updated
                    Task { await savePreferences(updated) }
                }
            ))

            if prefs.enableWeeklyReminders {
                Picker("Reminder Day", selection: Binding(
                    get: { prefs.reminderDayOfWeek ?? 0 },
                    set: { newValue in
                        var updated = prefs
                        updated.reminderDayOfWeek = newValue
                        preferences = updated
                        Task { await savePreferences(updated) }
                    }
                )) {
                    ForEach(0..<7, id: \.self) { day in
                        Text(dayNames[day]).tag(day)
                    }
                }

                Picker("Reminder Time", selection: Binding(
                    get: { extractHour(from: prefs.reminderTime) },
                    set: { newValue in
                        var updated = prefs
                        updated.reminderTime = formatTimeString(hour: newValue)
                        preferences = updated
                        Task { await savePreferences(updated) }
                    }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if prefs.enableWeeklyReminders {
                let dayName = dayNames[prefs.reminderDayOfWeek ?? 0]
                let timeStr = formatHour(extractHour(from: prefs.reminderTime))
                Text("You'll receive a gentle reminder to complete your weekly check-in on \(dayName) at \(timeStr).")
            } else {
                Text("Check-in reminders are disabled. You can still complete check-ins manually.")
            }
        }
    }

    // MARK: - Alert Section

    @ViewBuilder
    private func alertSection(prefs: WellnessPreferences) -> some View {
        Section {
            Toggle("Burnout Alerts", isOn: Binding(
                get: { prefs.enableBurnoutAlerts },
                set: { newValue in
                    var updated = prefs
                    updated.enableBurnoutAlerts = newValue
                    preferences = updated
                    Task { await savePreferences(updated) }
                }
            ))
        } header: {
            Text("Alerts")
        } footer: {
            Text("When enabled, you'll receive gentle alerts if we detect signs of potential burnout based on your check-ins and activity patterns.")
        }
    }

    // MARK: - Privacy Section

    @ViewBuilder
    private func privacySection(prefs: WellnessPreferences) -> some View {
        Section {
            Toggle("Share Capacity with Circle", isOn: Binding(
                get: { prefs.shareCapacityWithCircle },
                set: { newValue in
                    var updated = prefs
                    updated.shareCapacityWithCircle = newValue
                    preferences = updated
                    Task { await savePreferences(updated) }
                }
            ))
        } header: {
            Text("Privacy")
        } footer: {
            if prefs.shareCapacityWithCircle {
                Text("Your capacity level (but not your detailed wellness data) will be visible to circle members. This helps your circle understand when you may need extra support.")
            } else {
                Text("Your wellness data is completely private. Only you can see your check-ins, scores, and notes.")
            }
        }

        Section {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Data is Private")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Wellness data is never shared with your care circle unless you enable capacity sharing above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes Are Encrypted")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Personal notes are encrypted using AES-256-GCM and can only be read by you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func formatHour(_ hour: Int) -> String {
        let hour12 = hour % 12
        let displayHour = hour12 == 0 ? 12 : hour12
        let period = hour < 12 ? "AM" : "PM"
        return "\(displayHour):00 \(period)"
    }

    private func extractHour(from timeString: String?) -> Int {
        guard let time = timeString else { return 9 }
        let components = time.split(separator: ":")
        return Int(components.first ?? "9") ?? 9
    }

    private func formatTimeString(hour: Int) -> String {
        String(format: "%02d:00:00", hour)
    }

    private func loadPreferences() async {
        isLoading = true
        do {
            try await wellnessService.fetchPreferences()
            preferences = wellnessService.preferences
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func savePreferences(_ prefs: WellnessPreferences) async {
        isSaving = true
        do {
            try await wellnessService.updatePreferences(prefs)
        } catch {
            errorMessage = error.localizedDescription
            // Reload to revert changes
            await loadPreferences()
        }
        isSaving = false
    }
}
