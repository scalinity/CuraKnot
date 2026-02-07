import SwiftUI

// MARK: - Question Row

struct QuestionRow: View {
    let question: AppointmentQuestion
    var onToggle: ((AppointmentQuestion) -> Void)?

    @State private var isChecked = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox (optional)
            if let onToggle = onToggle {
                Button {
                    isChecked.toggle()
                    onToggle(question)
                } label: {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChecked ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Priority badge (if high)
                if question.isHighPriority {
                    PriorityBadge(priority: question.priority)
                }

                // Question text
                Text(question.questionText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // Reasoning (for AI questions)
                if let reasoning = question.reasoning, !reasoning.isEmpty {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Source and category badges
                HStack(spacing: 12) {
                    SourceBadge(source: question.source)
                    CategoryBadge(category: question.category)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Compact Question Row

struct CompactQuestionRow: View {
    let question: AppointmentQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if question.isHighPriority {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Text(question.questionText)
                    .font(.subheadline)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                SourceBadge(source: question.source)
                Spacer()
                StatusBadge(status: question.status)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Post-Appointment Question Row

struct PostAppointmentQuestionRow: View {
    let question: AppointmentQuestion
    let onStatusChange: (AppointmentQuestion, QuestionStatus, String?) -> Void

    @State private var selectedStatus: QuestionStatus
    @State private var responseNotes: String = ""
    @State private var isExpanded = false

    init(
        question: AppointmentQuestion,
        onStatusChange: @escaping (AppointmentQuestion, QuestionStatus, String?) -> Void
    ) {
        self.question = question
        self.onStatusChange = onStatusChange
        _selectedStatus = State(initialValue: question.status)
        _responseNotes = State(initialValue: question.responseNotes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question text
            Text(question.questionText)
                .font(.body)

            // Status picker
            Picker("Status", selection: $selectedStatus) {
                ForEach([QuestionStatus.discussed, .notDiscussed, .deferred], id: \.self) { status in
                    Label(status.displayName, systemImage: status.icon)
                        .tag(status)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedStatus) { _, newValue in
                onStatusChange(question, newValue, responseNotes.isEmpty ? nil : responseNotes)
            }

            // Response notes (expandable)
            DisclosureGroup("Add Notes", isExpanded: $isExpanded) {
                TextField("Response notes...", text: $responseNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .onChange(of: responseNotes) { _, newValue in
                        if selectedStatus != .pending {
                            onStatusChange(question, selectedStatus, newValue.isEmpty ? nil : newValue)
                        }
                    }
            }
            .font(.subheadline)

            // Priority and category
            HStack {
                PriorityBadge(priority: question.priority)
                Spacer()
                CategoryBadge(category: question.category)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Previews

#Preview("Question Row") {
    List {
        QuestionRow(
            question: AppointmentQuestion(
                id: "1",
                circleId: "c1",
                patientId: "p1",
                appointmentPackId: nil,
                questionText: "You mentioned dizziness 4 times in the last 30 days. Could this be related to medications or a new condition?",
                reasoning: "Dizziness was mentioned 4 times in recent handoffs",
                category: .symptom,
                source: .aiGenerated,
                sourceHandoffIds: [],
                sourceMedicationIds: [],
                createdBy: "u1",
                priority: .high,
                priorityScore: 8,
                status: .pending,
                sortOrder: 0,
                responseNotes: nil,
                discussedAt: nil,
                discussedBy: nil,
                followUpTaskId: nil,
                createdAt: Date(),
                updatedAt: Date()
            ),
            onToggle: { _ in }
        )

        QuestionRow(
            question: AppointmentQuestion(
                id: "2",
                circleId: "c1",
                patientId: "p1",
                appointmentPackId: nil,
                questionText: "Are all current medications still necessary?",
                reasoning: nil,
                category: .general,
                source: .template,
                sourceHandoffIds: [],
                sourceMedicationIds: [],
                createdBy: "u1",
                priority: .low,
                priorityScore: 2,
                status: .pending,
                sortOrder: 1,
                responseNotes: nil,
                discussedAt: nil,
                discussedBy: nil,
                followUpTaskId: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}
