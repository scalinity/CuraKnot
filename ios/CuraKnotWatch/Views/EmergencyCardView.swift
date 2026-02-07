import SwiftUI
import WatchKit

// MARK: - Emergency Card View
// CRITICAL: Must work fully offline with <100ms display time

struct EmergencyCardView: View {
    @EnvironmentObject var dataManager: WatchDataManager

    var card: WatchEmergencyCard? {
        dataManager.emergencyCard
    }

    var body: some View {
        Group {
            if let card = card {
                EmergencyCardContent(card: card)
            } else {
                EmergencyCardEmpty()
            }
        }
        .navigationTitle("Emergency")
    }
}

// MARK: - Emergency Card Content

private struct EmergencyCardContent: View {
    let card: WatchEmergencyCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                EmergencyHeader(card: card)

                // Allergies (High Priority - Orange)
                if !card.allergies.isEmpty {
                    EmergencySection(
                        title: "ALLERGIES",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    ) {
                        ForEach(card.allergies, id: \.self) { allergy in
                            Text("• \(allergy)")
                                .foregroundStyle(.orange)
                                .font(.body.bold())
                        }
                    }
                }

                // Conditions
                if !card.conditions.isEmpty {
                    EmergencySection(
                        title: "CONDITIONS",
                        icon: "heart.text.square.fill",
                        color: .red
                    ) {
                        ForEach(card.conditions, id: \.self) { condition in
                            Text("• \(condition)")
                        }
                    }
                }

                // Medications
                if !card.medications.isEmpty {
                    EmergencySection(
                        title: "MEDICATIONS",
                        icon: "pills.fill",
                        color: .blue
                    ) {
                        ForEach(card.medications) { med in
                            Text("• \(med.displayText)")
                                .font(.caption)
                        }
                    }
                }

                // Emergency Contacts
                if !card.emergencyContacts.isEmpty {
                    EmergencySection(
                        title: "EMERGENCY CONTACTS",
                        icon: "phone.fill",
                        color: .green
                    ) {
                        ForEach(card.emergencyContacts) { contact in
                            EmergencyContactRow(contact: contact)
                        }
                    }
                }

                // Physician
                if let physician = card.physician {
                    EmergencySection(
                        title: "PHYSICIAN",
                        icon: "stethoscope",
                        color: .purple
                    ) {
                        EmergencyContactRow(contact: physician)
                    }
                }

                // Notes
                if let notes = card.notes, !notes.isEmpty {
                    EmergencySection(
                        title: "NOTES",
                        icon: "note.text",
                        color: .secondary
                    ) {
                        Text(notes)
                            .font(.caption)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Emergency Header

private struct EmergencyHeader: View {
    let card: WatchEmergencyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Star of Life
                Image(systemName: "staroflife.fill")
                    .font(.title2)
                    .foregroundStyle(.red)

                Text(card.patientName)
                    .font(.title3.bold())
            }

            // DOB
            if let dob = card.dateOfBirth {
                HStack {
                    Text("DOB:")
                        .foregroundStyle(.secondary)
                    Text(dob, format: .dateTime.month().day().year())
                }
                .font(.caption)
            }

            // Blood Type
            if let bloodType = card.bloodType, !bloodType.isEmpty {
                HStack {
                    Text("Blood Type:")
                        .foregroundStyle(.secondary)
                    Text(bloodType)
                        .foregroundStyle(.red)
                        .fontWeight(.bold)
                }
                .font(.caption)
            }
        }
        .padding(.bottom, 8)
        .accessibilityIdentifier("EmergencyHeader")
    }
}

// MARK: - Emergency Section

private struct EmergencySection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(color)
            }

            content()
        }
    }
}

// MARK: - Emergency Contact Row

private struct EmergencyContactRow: View {
    let contact: WatchContact

    var body: some View {
        if contact.canCall {
            Button {
                callContact()
            } label: {
                ContactContent()
            }
            .buttonStyle(.plain)
        } else {
            ContactContent()
        }
    }

    @ViewBuilder
    private func ContactContent() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline)

                if let role = contact.role {
                    Text(role)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if contact.canCall {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("EmergencyContact_\(contact.id)")
    }

    private func callContact() {
        guard let url = contact.phoneURL else { return }

        // Play haptic before calling
        WKInterfaceDevice.current().play(.click)

        // Open phone URL
        WKApplication.shared().openSystemURL(url)
    }
}

// MARK: - Emergency Card Empty

private struct EmergencyCardEmpty: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "staroflife")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No Emergency Card")
                .font(.headline)

            Text("Set up an emergency card in the iPhone app")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    EmergencyCardView()
        .environmentObject(WatchDataManager.shared)
}
