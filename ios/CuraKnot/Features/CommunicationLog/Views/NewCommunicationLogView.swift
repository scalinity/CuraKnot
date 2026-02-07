import SwiftUI

// MARK: - New Communication Log View

struct NewCommunicationLogView: View {
    @StateObject private var viewModel: NewCommunicationLogViewModel
    @Environment(\.dismiss) private var dismiss

    let onSave: (CommunicationLog) -> Void

    init(
        service: CommunicationLogService,
        binderService: BinderService,
        circleId: String,
        patientId: String,
        onSave: @escaping (CommunicationLog) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: NewCommunicationLogViewModel(
            service: service,
            binderService: binderService,
            circleId: circleId,
            patientId: patientId
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Communication Type") {
                    Picker("Type", selection: $viewModel.communicationType) {
                        ForEach(CommunicationLog.CommunicationType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Facility") {
                    if !viewModel.availableFacilities.isEmpty {
                        Picker("Select Facility", selection: Binding(
                            get: { viewModel.selectedFacility?.id },
                            set: { id in
                                if let id = id {
                                    let facility = viewModel.availableFacilities.first { $0.id == id }
                                    viewModel.selectFacility(facility)
                                } else {
                                    viewModel.selectFacility(nil)
                                }
                            }
                        )) {
                            Text("Other / New").tag(nil as String?)
                            ForEach(viewModel.availableFacilities) { facility in
                                Text(facility.title).tag(facility.id as String?)
                            }
                        }
                    }

                    if viewModel.selectedFacility == nil {
                        TextField("Facility Name", text: $viewModel.facilityName)
                            .autocorrectionDisabled()
                    }
                }

                Section("Contact") {
                    TextField("Name", text: $viewModel.contactName)
                        .autocorrectionDisabled()

                    NavigationLink {
                        RoleSelectionView(selectedRoles: $viewModel.contactRoles)
                    } label: {
                        HStack {
                            Text("Role")
                            Spacer()
                            if viewModel.contactRoles.isEmpty {
                                Text("Select")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(viewModel.contactRoles.map { $0.displayName }.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    TextField("Phone (optional)", text: $viewModel.contactPhone)
                        .keyboardType(.phonePad)

                    TextField("Email (optional)", text: $viewModel.contactEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("Call Type", selection: $viewModel.callType) {
                        ForEach(CommunicationLog.CallType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .onChange(of: viewModel.callType) { _, _ in
                        viewModel.updateFollowUpFromCallType()
                    }

                    DatePicker("When", selection: $viewModel.callDate)

                    Stepper(
                        value: Binding(
                            get: { viewModel.durationMinutes ?? 0 },
                            set: { viewModel.durationMinutes = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...180,
                        step: 5
                    ) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            if let minutes = viewModel.durationMinutes {
                                Text("~\(minutes) min")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not set")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Call Details")
                } footer: {
                    Text(viewModel.promptText)
                        .foregroundStyle(.secondary)
                }

                Section("Summary") {
                    TextEditor(text: $viewModel.summary)
                        .frame(minHeight: 100)
                }

                Section("Follow-up") {
                    Toggle("Needs follow-up", isOn: $viewModel.needsFollowUp)

                    if viewModel.needsFollowUp {
                        DatePicker(
                            "Date",
                            selection: $viewModel.followUpDate,
                            in: Date()...,
                            displayedComponents: .date
                        )

                        TextField("Reason (optional)", text: $viewModel.followUpReason)
                    }
                }
            }
            .navigationTitle("Log Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let log = await viewModel.save() {
                                onSave(log)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .disabled(viewModel.isSaving)
            .overlay {
                if viewModel.isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadFacilities()
            }
        }
    }
}

// MARK: - Role Selection View

struct RoleSelectionView: View {
    @Binding var selectedRoles: Set<CommunicationLog.ContactRole>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(CommunicationLog.ContactRole.allCases, id: \.self) { role in
                Button {
                    if selectedRoles.contains(role) {
                        selectedRoles.remove(role)
                    } else {
                        selectedRoles.insert(role)
                    }
                } label: {
                    HStack {
                        Label(role.displayName, systemImage: role.icon)
                        Spacer()
                        if selectedRoles.contains(role) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.teal)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Contact Role")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Quick Log Sheet (One-Tap Post-Call)

struct QuickCallLogSheet: View {
    @StateObject private var viewModel: NewCommunicationLogViewModel
    @Environment(\.dismiss) private var dismiss

    let facilityName: String
    let facilityId: String?
    let onSave: (CommunicationLog) -> Void

    init(
        service: CommunicationLogService,
        binderService: BinderService,
        circleId: String,
        patientId: String,
        facilityName: String,
        facilityId: String?,
        onSave: @escaping (CommunicationLog) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: NewCommunicationLogViewModel(
            service: service,
            binderService: binderService,
            circleId: circleId,
            patientId: patientId
        ))
        self.facilityName = facilityName
        self.facilityId = facilityId
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "phone.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)
                    Text(facilityName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.top)

                Form {
                    Section("Who did you speak with?") {
                        TextField("Name", text: $viewModel.contactName)
                            .autocorrectionDisabled()

                        Picker("Role", selection: Binding(
                            get: { viewModel.contactRoles.first ?? .other },
                            set: { viewModel.contactRoles = [$0] }
                        )) {
                            ForEach(CommunicationLog.ContactRole.allCases, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                    }

                    Section("What type of call?") {
                        Picker("Type", selection: $viewModel.callType) {
                            ForEach(CommunicationLog.CallType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Quick summary") {
                        TextEditor(text: $viewModel.summary)
                            .frame(minHeight: 80)
                    }

                    Section {
                        Toggle("Need to follow up?", isOn: $viewModel.needsFollowUp)

                        if viewModel.needsFollowUp {
                            DatePicker(
                                "When",
                                selection: $viewModel.followUpDate,
                                in: Date()...,
                                displayedComponents: .date
                            )
                        }
                    }
                }
            }
            .navigationTitle("Log Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.facilityName = facilityName
                        if let id = facilityId {
                            viewModel.selectedFacility = NewCommunicationLogViewModel.FacilitySelection(
                                id: id,
                                name: facilityName,
                                phone: nil
                            )
                        }
                        Task {
                            if let log = await viewModel.save() {
                                onSave(log)
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.contactName.isEmpty || viewModel.summary.isEmpty || viewModel.isSaving)
                }
            }
        }
        .presentationDetents([.large])
    }
}
