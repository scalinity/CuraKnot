import SwiftUI

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: QuestionPriority

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: priority.icon)
                .font(.caption2)
            Text(priority.displayName.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundStyle(priority.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(priority.color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: QuestionCategory

    var body: some View {
        Label(category.displayName, systemImage: category.icon)
            .font(.caption2)
            .foregroundStyle(category.color)
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
    let source: QuestionSource

    var body: some View {
        Label(source.displayName, systemImage: source.icon)
            .font(.caption2)
            .foregroundStyle(source.color)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: QuestionStatus

    var body: some View {
        Label(status.displayName, systemImage: status.icon)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Previews

#Preview("Priority Badges") {
    VStack(spacing: 12) {
        PriorityBadge(priority: .high)
        PriorityBadge(priority: .medium)
        PriorityBadge(priority: .low)
    }
    .padding()
}

#Preview("Category Badges") {
    VStack(alignment: .leading, spacing: 8) {
        CategoryBadge(category: .symptom)
        CategoryBadge(category: .medication)
        CategoryBadge(category: .sideEffect)
        CategoryBadge(category: .general)
    }
    .padding()
}

#Preview("Source Badges") {
    VStack(alignment: .leading, spacing: 8) {
        SourceBadge(source: .aiGenerated)
        SourceBadge(source: .userAdded)
        SourceBadge(source: .template)
    }
    .padding()
}

#Preview("Status Badges") {
    VStack(spacing: 8) {
        StatusBadge(status: .pending)
        StatusBadge(status: .discussed)
        StatusBadge(status: .notDiscussed)
        StatusBadge(status: .deferred)
    }
    .padding()
}
