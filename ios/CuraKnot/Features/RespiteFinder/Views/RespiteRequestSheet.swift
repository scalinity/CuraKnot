import SwiftUI

// MARK: - Respite Request Sheet

struct RespiteRequestSheet: View {
    @StateObject private var viewModel: RespiteRequestViewModel
    @Environment(\.dismiss) private var dismiss

    let circleId: String
    let patientId: String

    init(service: RespiteFinderService, provider: RespiteProvider, circleId: String, patientId: String) {
        _viewModel = StateObject(wrappedValue: RespiteRequestViewModel(service: service, provider: provider))
        self.circleId = circleId
        self.patientId = patientId
    }

    var body: some View {
        NavigationStack {
            if viewModel.showSuccess {
                successView
            } else {
                formView
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: viewModel.provider.providerType.icon)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(viewModel.provider.name)
                            .font(.headline)
                        Text(viewModel.provider.providerType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(String(localized: "Dates")) {
                DatePicker(String(localized: "Start Date"), selection: $viewModel.startDate, in: Date()..., displayedComponents: .date)
                DatePicker(String(localized: "End Date"), selection: $viewModel.endDate, in: viewModel.startDate..., displayedComponents: .date)
            }

            Section(String(localized: "Information to Share")) {
                Toggle(String(localized: "Medications"), isOn: $viewModel.shareMedications)
                Toggle(String(localized: "Emergency Contacts"), isOn: $viewModel.shareContacts)
                Toggle(String(localized: "Dietary Needs"), isOn: $viewModel.shareDietary)
                Toggle(String(localized: "Full Care Summary"), isOn: $viewModel.shareFullSummary)
            }

            Section {
                Text(String(localized: "Describe scheduling or logistical needs only. Do not include diagnoses or medication names here — use the toggles above to control medical data sharing."))
                    .font(.caption)
                    .foregroundStyle(.orange)
                TextEditor(text: $viewModel.specialConsiderations)
                    .frame(minHeight: 80)
            } header: {
                Text(String(localized: "Special Considerations"))
            }

            Section(String(localized: "How Should They Contact You?")) {
                Picker(String(localized: "Method"), selection: $viewModel.contactMethod) {
                    Text(String(localized: "Phone")).tag(RespiteRequest.ContactMethod.phone)
                    Text(String(localized: "Email")).tag(RespiteRequest.ContactMethod.email)
                }
                .pickerStyle(.segmented)

                TextField(
                    viewModel.contactMethod == .phone ? String(localized: "Phone number") : String(localized: "Email address"),
                    text: $viewModel.contactValue
                )
                .keyboardType(viewModel.contactMethod == .phone ? .namePhonePad : .emailAddress)
                .textContentType(viewModel.contactMethod == .phone ? .telephoneNumber : .emailAddress)
                .autocapitalization(.none)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(String(localized: "Check Availability"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Submit")) {
                    viewModel.submit(circleId: circleId, patientId: patientId)
                }
                .bold()
                .disabled(!viewModel.isValid || viewModel.isSubmitting)
            }
        }
        .disabled(viewModel.isSubmitting)
        .overlay {
            if viewModel.isSubmitting {
                Color.black.opacity(0.1)
                    .ignoresSafeArea()
                ProgressView(String(localized: "Submitting..."))
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text(String(localized: "Request Submitted"))
                .font(.title2)
                .bold()

            Text(String(localized: "Your availability request has been sent to \(viewModel.provider.name). They will contact you via \(viewModel.contactMethod.displayName.lowercased())."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(String(localized: "Done")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .navigationTitle(String(localized: "Success"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Done")) { dismiss() }
            }
        }
    }
}
