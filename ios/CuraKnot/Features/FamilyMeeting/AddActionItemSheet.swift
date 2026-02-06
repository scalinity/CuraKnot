import SwiftUI

// MARK: - Add Action Item Sheet

struct AddActionItemSheet: View {
    // MARK: Properties

    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, UUID?, Date?) -> Void
    @State private var description = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Action Item Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Action item description")
                        .accessibilityHint("Describe what needs to be done")
                }

                Section {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                        .accessibilityHint("When enabled, allows setting a deadline for this action")

                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, in: Date()..., displayedComponents: .date)
                            .accessibilityLabel("Due date")
                            .accessibilityHint("Select a deadline for this action item")
                    }
                }
            }
            .navigationTitle("Add Action Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(
                            description,
                            nil,
                            hasDueDate ? dueDate : nil
                        )
                        dismiss()
                    }
                    .disabled(description.isEmpty)
                }
            }
        }
    }
}
