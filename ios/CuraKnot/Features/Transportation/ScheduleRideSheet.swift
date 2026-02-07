import SwiftUI

// MARK: - Schedule Ride Sheet

struct ScheduleRideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject var service: TransportationService

    // Form state
    @State private var selectedPatient: Patient?
    @State private var purpose = ""
    @State private var pickupAddress = ""
    @State private var pickupTime = Date().addingTimeInterval(3600)
    @State private var destinationAddress = ""
    @State private var destinationName = ""
    @State private var needsReturn = false
    @State private var returnTime = Date().addingTimeInterval(7200)

    // Special needs
    @State private var wheelchairAccessible = false
    @State private var stretcherRequired = false
    @State private var oxygenRequired = false
    @State private var otherNeeds = ""

    // Driver
    @State private var driverType: ScheduledRide.DriverType = .family
    @State private var externalServiceName = ""

    // State
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // Patient
                Section {
                    Picker("Patient", selection: $selectedPatient) {
                        Text("Select Patient").tag(nil as Patient?)
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                }

                // Appointment Details
                Section("Ride Details") {
                    TextField("Purpose (e.g., Dr. Smith - Cardiology)", text: $purpose)

                    TextField("Pickup Address", text: $pickupAddress, axis: .vertical)
                        .lineLimit(2)

                    DatePicker("Pickup Time", selection: $pickupTime, in: Date()...)

                    TextField("Destination Address", text: $destinationAddress, axis: .vertical)
                        .lineLimit(2)

                    TextField("Destination Name (optional)", text: $destinationName)
                }

                // Return Ride
                Section("Return Ride") {
                    Toggle("Return Ride Needed", isOn: $needsReturn)

                    if needsReturn {
                        DatePicker("Estimated Return Time", selection: $returnTime, in: pickupTime.addingTimeInterval(60)...)
                            .datePickerStyle(.compact)
                    }
                }

                // Special Needs
                Section("Special Needs") {
                    Toggle("Wheelchair Accessible", isOn: $wheelchairAccessible)
                    Toggle("Stretcher Transport", isOn: $stretcherRequired)
                    Toggle("Oxygen Equipment", isOn: $oxygenRequired)
                    TextField("Other needs (optional)", text: $otherNeeds, axis: .vertical)
                        .lineLimit(3)
                }

                // Driver Selection
                Section("Driver") {
                    Picker("Driver Type", selection: $driverType) {
                        Text("Family Member").tag(ScheduledRide.DriverType.family)
                        Text("External Service").tag(ScheduledRide.DriverType.externalService)
                    }

                    if driverType == .externalService {
                        TextField("Service Name", text: $externalServiceName)
                    }
                }

                // Save
                Section {
                    Button {
                        saveRide()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isSaving ? "Saving..." : "Save & Find Driver")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving || !isFormValid)
                }
            }
            .navigationTitle("Schedule Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                selectedPatient = appState.patients.first
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        selectedPatient != nil &&
        !purpose.trimmingCharacters(in: .whitespaces).isEmpty &&
        !pickupAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destinationAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        pickupTime > Date() &&
        (!needsReturn || returnTime > pickupTime)
    }

    // MARK: - Save

    private func saveRide() {
        guard let patient = selectedPatient,
              let circleId = appState.currentCircle?.id else { return }

        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                let request = CreateRideRequest(
                    circleId: circleId,
                    patientId: patient.id,
                    purpose: purpose.trimmedAndLimited(to: 500),
                    pickupAddress: pickupAddress.trimmedAndLimited(to: 1000),
                    pickupTime: pickupTime,
                    destinationAddress: destinationAddress.trimmedAndLimited(to: 1000),
                    destinationName: destinationName.trimmedLimitedOrNil(to: 500),
                    needsReturn: needsReturn,
                    returnTime: needsReturn ? returnTime : nil,
                    wheelchairAccessible: wheelchairAccessible,
                    stretcherRequired: stretcherRequired,
                    oxygenRequired: oxygenRequired,
                    otherNeeds: otherNeeds.trimmedLimitedOrNil(to: 2000),
                    driverType: driverType,
                    externalServiceName: driverType == .externalService ? externalServiceName.trimmedLimitedOrNil(to: 500) : nil
                )
                try await service.createRide(request)
                guard !Task.isCancelled else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let container = DependencyContainer()
    ScheduleRideSheet(service: container.transportationService)
        .environmentObject(AppState())
        .environmentObject(container)
}
