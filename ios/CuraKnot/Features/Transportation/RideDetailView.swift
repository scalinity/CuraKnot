import SwiftUI

// MARK: - Ride Detail View

struct RideDetailView: View {
    @EnvironmentObject var appState: AppState
    let ride: ScheduledRide
    @ObservedObject var service: TransportationService

    @State private var showingDriverAssignment = false
    @State private var showingCancelConfirm = false
    @State private var showingCompleteConfirm = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var currentUserId: String? {
        appState.currentUser?.id
    }

    private var isCurrentUserDriver: Bool {
        guard let userId = currentUserId else { return false }
        return ride.driverUserId == userId
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Header
                statusHeader

                // Ride Details
                detailsCard

                // Special Needs
                if ride.hasSpecialNeeds {
                    specialNeedsCard
                }

                // Driver Section
                driverCard

                // Actions
                if ride.status == .scheduled {
                    actionsSection
                }
            }
            .padding()
        }
        .navigationTitle("Ride Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDriverAssignment) {
            DriverAssignmentView(ride: ride, service: service)
        }
        .alert("Cancel Ride?", isPresented: $showingCancelConfirm) {
            Button("Keep Ride", role: .cancel) {}
            Button("Cancel Ride", role: .destructive) {
                cancelRide()
            }
        } message: {
            Text("This will cancel the scheduled ride. Circle members will be notified.")
        }
        .alert("Complete Ride?", isPresented: $showingCompleteConfirm) {
            Button("Not Yet", role: .cancel) {}
            Button("Mark Complete") {
                completeRide()
            }
        } message: {
            Text("Mark this ride as completed.")
        }
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: ride.confirmationStatus.icon)
                    .font(.title2)
                Text(ride.confirmationStatus.displayName)
                    .font(.headline)
            }
            .foregroundStyle(ride.confirmationStatus.color)

            Text(ride.status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ride.confirmationStatus.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ride Details")
                .font(.headline)

            detailRow(icon: "building.2", label: "Purpose", value: ride.purpose)
            detailRow(icon: "mappin", label: "Pickup", value: ride.pickupAddress)
            detailRow(icon: "clock", label: "Pickup Time", value: ride.pickupTime.formatted(date: .abbreviated, time: .shortened))
            detailRow(icon: "mappin.circle", label: "Destination", value: ride.destinationName ?? ride.destinationAddress)

            if ride.destinationName != nil {
                detailRow(icon: "map", label: "Address", value: ride.destinationAddress)
            }

            if ride.needsReturn {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(.blue)
                    Text("Return ride needed")
                        .font(.subheadline)
                    if let returnTime = ride.returnTime {
                        Spacer()
                        Text(returnTime, style: .time)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Special Needs Card

    private var specialNeedsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Special Needs")
                .font(.headline)

            HStack(spacing: 8) {
                if ride.wheelchairAccessible {
                    SpecialNeedsBadge(text: "Wheelchair", icon: "figure.roll")
                }
                if ride.stretcherRequired {
                    SpecialNeedsBadge(text: "Stretcher", icon: "bed.double")
                }
                if ride.oxygenRequired {
                    SpecialNeedsBadge(text: "Oxygen", icon: "lungs")
                }
            }

            if let otherNeeds = ride.otherNeeds, !otherNeeds.isEmpty {
                Text(otherNeeds)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Driver Card

    private var driverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Driver")
                .font(.headline)

            if ride.driverType == .externalService {
                HStack {
                    Image(systemName: "building.2")
                        .foregroundStyle(.blue)
                    Text(ride.externalServiceName ?? "External Service")
                }
            } else if let driverName = ride.driverName {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.blue)
                    Text(driverName)
                    Spacer()
                    ConfirmationBadge(status: ride.confirmationStatus)
                }
            } else if ride.driverUserId != nil {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Assigned (pending confirmation)")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "person.fill.questionmark")
                        .foregroundStyle(.orange)
                    Text("No driver assigned")
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Volunteer / Assign Driver
            if ride.needsDriver {
                Button {
                    volunteerAsDriver()
                } label: {
                    Label("I'll Drive", systemImage: "car.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

                Button {
                    showingDriverAssignment = true
                } label: {
                    Label("Ask Someone", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
            }

            // Confirm / Decline (for requested driver)
            if isCurrentUserDriver && ride.confirmationStatus == .unconfirmed {
                HStack(spacing: 12) {
                    Button {
                        confirmRide()
                    } label: {
                        Label("Confirm", systemImage: "checkmark")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        declineRide()
                    } label: {
                        Label("Decline", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            // Complete
            if ride.confirmationStatus == .confirmed && ride.pickupTime <= Date() {
                Button {
                    showingCompleteConfirm = true
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }

            // Cancel
            Button(role: .destructive) {
                showingCancelConfirm = true
            } label: {
                Label("Cancel Ride", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func volunteerAsDriver() {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                try await service.volunteerAsDriver(rideId: ride.id, circleId: ride.circleId)
                guard !Task.isCancelled else { return }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func confirmRide() {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                try await service.confirmRide(rideId: ride.id, circleId: ride.circleId)
                guard !Task.isCancelled else { return }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func declineRide() {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                try await service.declineRide(rideId: ride.id, circleId: ride.circleId)
                guard !Task.isCancelled else { return }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelRide() {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                try await service.cancelRide(rideId: ride.id, circleId: ride.circleId)
                guard !Task.isCancelled else { return }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func completeRide() {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                try await service.completeRide(rideId: ride.id, circleId: ride.circleId)
                guard !Task.isCancelled else { return }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
