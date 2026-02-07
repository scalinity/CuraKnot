import SwiftUI

// MARK: - Transportation View

struct TransportationView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var showingScheduleRide = false
    @State private var showingDirectory = false
    @State private var showingAnalytics = false
    @State private var errorMessage: String?

    private var service: TransportationService {
        container.transportationService
    }

    var body: some View {
        NavigationStack {
            Group {
                if !service.hasAccess {
                    upgradePromptView
                } else if service.isLoading && service.rides.isEmpty {
                    ProgressView("Loading rides...")
                } else {
                    rideListView
                }
            }
            .navigationTitle("Transportation")
            .toolbar {
                if service.hasAccess {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingDirectory = true
                            } label: {
                                Label("Transport Directory", systemImage: "book")
                            }

                            if service.hasAnalyticsAccess {
                                Button {
                                    showingAnalytics = true
                                } label: {
                                    Label("Ride Analytics", systemImage: "chart.bar")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")

                        Button {
                            showingScheduleRide = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Schedule new ride")
                    }
                }
            }
            .sheet(isPresented: $showingScheduleRide) {
                ScheduleRideSheet(service: service)
            }
            .sheet(isPresented: $showingDirectory) {
                TransportDirectoryView(service: service)
            }
            .sheet(isPresented: $showingAnalytics) {
                RideAnalyticsView(service: service)
            }
            .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .refreshable {
                await loadRides()
            }
            .task {
                guard !Task.isCancelled else { return }
                await loadRides()
            }
        }
    }

    // MARK: - Ride List

    private var rideListView: some View {
        List {
            // Unconfirmed rides alert section
            if !service.unconfirmedRides.isEmpty {
                Section {
                    ForEach(service.unconfirmedRides) { ride in
                        NavigationLink {
                            RideDetailView(ride: ride, service: service)
                        } label: {
                            UnconfirmedRideRow(ride: ride)
                        }
                    }
                } header: {
                    Label("Needs Driver", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            // Upcoming rides grouped by date
            if service.upcomingRidesGrouped.isEmpty && service.unconfirmedRides.isEmpty {
                Section {
                    emptyStateView
                }
            } else {
                ForEach(service.upcomingRidesGrouped) { group in
                    Section(group.dateHeader) {
                        ForEach(group.rides) { ride in
                            NavigationLink {
                                RideDetailView(ride: ride, service: service)
                            } label: {
                                RideRow(ride: ride)
                            }
                        }
                    }
                }
            }

            // Past rides
            if !service.pastRides.isEmpty {
                Section("Past Rides") {
                    ForEach(service.pastRides.prefix(10)) { ride in
                        NavigationLink {
                            RideDetailView(ride: ride, service: service)
                        } label: {
                            RideRow(ride: ride)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.side")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Upcoming Rides")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Schedule rides to coordinate transportation for medical appointments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingScheduleRide = true
            } label: {
                Label("Schedule Ride", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Upgrade Prompt

    private var upgradePromptView: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.side")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Medical Transportation")
                .font(.title2)
                .fontWeight(.bold)

            Text("Coordinate rides to appointments, track driver fairness, and browse local transport services.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                featureRow("Schedule rides linked to appointments", icon: "calendar.badge.clock")
                featureRow("Coordinate drivers among family", icon: "person.2")
                featureRow("Automated reminders", icon: "bell.badge")
                featureRow("Transport service directory", icon: "book")
            }
            .padding(.horizontal, 32)

            Text("Available on Plus plan")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func featureRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Load

    private func loadRides() async {
        guard let circleId = appState.currentCircle?.id else { return }
        do {
            try await service.fetchRides(circleId: circleId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Ride Row

struct RideRow: View {
    let ride: ScheduledRide

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(.blue)
                Text(ride.purpose)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                ConfirmationBadge(status: ride.confirmationStatus)
            }

            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .foregroundStyle(.secondary)
                Text(ride.destinationName ?? ride.destinationAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("Pickup: \(ride.pickupTime, style: .time)")
                    .font(.subheadline)
            }

            HStack(spacing: 4) {
                Image(systemName: "car")
                    .foregroundStyle(.secondary)
                if let driverName = ride.driverName {
                    Text("Driver: \(driverName)")
                        .font(.subheadline)
                } else if ride.driverUserId != nil {
                    Text("Driver: Assigned")
                        .font(.subheadline)
                } else if ride.driverType == .externalService {
                    Text("Service: \(ride.externalServiceName ?? "External")")
                        .font(.subheadline)
                } else {
                    Text("Driver: Needed!")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            // Special needs badges
            if ride.hasSpecialNeeds {
                HStack(spacing: 6) {
                    if ride.wheelchairAccessible {
                        SpecialNeedsBadge(text: "Wheelchair", icon: "figure.roll")
                    }
                    if ride.oxygenRequired {
                        SpecialNeedsBadge(text: "Oxygen", icon: "lungs")
                    }
                    if ride.stretcherRequired {
                        SpecialNeedsBadge(text: "Stretcher", icon: "bed.double")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ride.purpose), pickup at \(ride.pickupTime.formatted(date: .omitted, time: .shortened)), \(ride.confirmationStatus.displayName)")
    }
}

// MARK: - Unconfirmed Ride Row

struct UnconfirmedRideRow: View {
    let ride: ScheduledRide

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.purpose)
                    .font(.headline)
                Text("\(ride.pickupTime, style: .date) at \(ride.pickupTime, style: .time)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Needs Driver")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ride.purpose), needs driver, \(ride.pickupTime.formatted(date: .abbreviated, time: .shortened))")
    }
}

// MARK: - Confirmation Badge

struct ConfirmationBadge: View {
    let status: ScheduledRide.ConfirmationStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
            Text(status.displayName)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(status.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.displayName)")
    }
}

// MARK: - Special Needs Badge

struct SpecialNeedsBadge: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.1))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Special need: \(text)")
    }
}

// MARK: - Preview

#Preview {
    let container = DependencyContainer()
    TransportationView()
        .environmentObject(AppState())
        .environmentObject(container)
}
