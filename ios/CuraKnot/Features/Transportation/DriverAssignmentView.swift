import SwiftUI

// MARK: - Driver Assignment View

struct DriverAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    let ride: ScheduledRide
    @ObservedObject var service: TransportationService

    @State private var members: [CircleMemberInfo] = []
    @State private var isLoading = false
    @State private var isRequesting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // Circle Members
                Section("Circle Members") {
                    if isLoading {
                        ProgressView("Loading members...")
                    } else if members.isEmpty {
                        Text("No members available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            memberRow(member)
                        }
                    }
                }

                // External Services
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Label("Find Medical Transport", systemImage: "bus.fill")
                    }

                    Button {
                        // Show paratransit info
                    } label: {
                        Label("Local Paratransit Info", systemImage: "info.circle")
                    }
                } header: {
                    Text("Or")
                } footer: {
                    Text("External services can be found in the Transport Directory.")
                }
            }
            .navigationTitle("Who Can Drive?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                guard !Task.isCancelled else { return }
                await loadMembers()
            }
        }
    }

    // MARK: - Member Row

    private func memberRow(_ member: CircleMemberInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.displayName)
                        .font(.body)
                    if member.id == appState.currentUser?.id {
                        Text("(you)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Rides given: \(member.ridesThisMonth) this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if member.id == appState.currentUser?.id {
                Button("I'll Drive") {
                    volunteerSelf()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRequesting)
            } else {
                Button("Ask \(member.displayName.components(separatedBy: " ").first ?? member.displayName)") {
                    requestDriver(member: member)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRequesting)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func volunteerSelf() {
        guard let circleId = appState.currentCircle?.id else { return }
        Task {
            isRequesting = true
            defer { isRequesting = false }
            do {
                try await service.volunteerAsDriver(rideId: ride.id, circleId: circleId)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestDriver(member: CircleMemberInfo) {
        guard let circleId = appState.currentCircle?.id else { return }
        Task {
            isRequesting = true
            defer { isRequesting = false }
            do {
                try await service.requestDriver(rideId: ride.id, circleId: circleId, driverUserId: member.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Load Members

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }

        guard let circleId = appState.currentCircle?.id else { return }

        do {
            let fetchedMembers = try await service.fetchCircleMembers(circleId: circleId)
            guard !Task.isCancelled else { return }
            members = fetchedMembers
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Failed to load members: \(error.localizedDescription)"
        }
    }
}
