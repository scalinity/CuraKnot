import SwiftUI

// MARK: - New Condition View

struct NewConditionView: View {
    @Environment(\.dismiss) private var dismiss

    let circleId: UUID
    let patientId: UUID
    let onSave: (ConditionType, String, String?, Date) async -> Void

    @State private var conditionType: ConditionType = .wound
    @State private var bodyLocation = ""
    @State private var description = ""
    @State private var startDate = Date()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you tracking?") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12) {
                        ForEach(ConditionType.allCases) { type in
                            conditionTypeButton(type)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section("Location on body") {
                    TextField("e.g., Left ankle, outer side", text: $bodyLocation)
                        .textContentType(.none)
                }

                Section("Description (optional)") {
                    TextField("e.g., Surgical incision from hip replacement", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Start date") {
                    DatePicker("When did this start?", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Track a Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Tracking") {
                        isSaving = true
                        Task {
                            await onSave(
                                conditionType,
                                bodyLocation,
                                description.isEmpty ? nil : description,
                                startDate
                            )
                            isSaving = false
                        }
                    }
                    .disabled(bodyLocation.isEmpty || isSaving)
                }
            }
        }
    }

    private func conditionTypeButton(_ type: ConditionType) -> some View {
        Button {
            conditionType = type
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.title2)
                Text(type.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(conditionType == type ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(conditionType == type ? .blue : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(conditionType == type ? Color.blue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
