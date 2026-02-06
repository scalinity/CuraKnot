import SwiftUI

// MARK: - Add Agenda Item Sheet

struct AddAgendaItemSheet: View {
    // MARK: Properties

    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, String?) -> Void
    @State private var title = ""
    @State private var description = ""

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Topic Title", text: $title)
                        .accessibilityLabel("Agenda item title")
                        .accessibilityHint("Enter the main topic to discuss")

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Description")
                        .accessibilityHint("Add optional details about this agenda item")
                }
            }
            .navigationTitle("Add Agenda Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(title, description.isEmpty ? nil : description)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
