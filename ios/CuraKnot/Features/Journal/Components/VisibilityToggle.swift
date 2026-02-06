import SwiftUI

// MARK: - Visibility Toggle

/// A picker component for selecting journal entry visibility
struct VisibilityToggle: View {
    @Binding var visibility: EntryVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who can see this?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Visibility", selection: $visibility) {
                ForEach(EntryVisibility.allCases) { option in
                    Label(option.displayName, systemImage: option.icon)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(visibility.description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Visibility Badge

/// A small badge showing entry visibility
struct VisibilityBadge: View {
    let visibility: EntryVisibility

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: visibility.icon)
                .font(.caption2)

            Text(visibility == .private ? "Private" : "Shared")
                .font(.caption2)
        }
        .foregroundStyle(visibility == .private ? .orange : .secondary)
    }
}

#Preview {
    VStack(spacing: 20) {
        VisibilityToggle(visibility: .constant(.circle))

        HStack {
            VisibilityBadge(visibility: .private)
            VisibilityBadge(visibility: .circle)
        }
    }
    .padding()
}
