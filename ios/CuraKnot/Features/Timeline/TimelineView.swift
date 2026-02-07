import SwiftUI

// MARK: - Timeline View

struct TimelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var handoffs: [Handoff] = []
    @State private var isLoading = false
    @State private var selectedFilter: HandoffFilter = .all
    @State private var searchText = ""
    @State private var showingNewHandoff = false
    
    enum HandoffFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case visit = "Visits"
        case call = "Calls"
    }
    
    var filteredHandoffs: [Handoff] {
        var result = handoffs
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        switch selectedFilter {
        case .all:
            break
        case .unread:
            // TODO: Filter by read status
            break
        case .visit:
            result = result.filter { $0.type == .visit }
        case .call:
            result = result.filter { $0.type == .call }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if handoffs.isEmpty && !isLoading {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No Handoffs Yet",
                        message: "Create your first handoff to start documenting care.",
                        actionTitle: "New Handoff"
                    ) {
                        showingNewHandoff = true
                    }
                } else {
                    List {
                        ForEach(filteredHandoffs) { handoff in
                            NavigationLink {
                                HandoffDetailView(handoff: handoff)
                            } label: {
                                HandoffCell(handoff: handoff)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await refresh()
                    }
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CircleSwitcherButton()
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    PatientFilterButton()
                }
            }
            .searchable(text: $searchText, prompt: "Search handoffs")
        }
        .sheet(isPresented: $showingNewHandoff) {
            NewHandoffView()
        }
        .task {
            await loadHandoffs()
        }
    }
    
    private func loadHandoffs() async {
        isLoading = true
        // TODO: Load from sync coordinator
        isLoading = false
    }
    
    private func refresh() async {
        await loadHandoffs()
    }
}

// MARK: - Handoff Cell

struct HandoffCell: View {
    let handoff: Handoff
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: handoff.type.icon)
                    .foregroundStyle(.secondary)
                
                Text(handoff.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if let publishedAt = handoff.publishedAt {
                    Text(publishedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let summary = handoff.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                // TODO: Show patient name
                Label("Patient", systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // TODO: Show task count, attachments
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Handoff Detail View

struct HandoffDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    let handoff: Handoff

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(handoff.type.displayName, systemImage: handoff.type.icon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let publishedAt = handoff.publishedAt {
                            Text(publishedAt, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Translated content (handles translation banner, toggle, and disclaimer)
                TranslatedHandoffView(
                    handoff: handoff,
                    circleId: appState.currentCircle?.id ?? "",
                    translationService: container.translationService,
                    subscriptionManager: container.subscriptionManager,
                    userId: appState.currentUser?.id ?? ""
                )

                // TODO: Show structured brief sections
                // - Status
                // - Changes
                // - Questions
                // - Next Steps

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Handoff")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Create Task", systemImage: "checklist") {}
                    Button("Edit", systemImage: "pencil") {}
                    Button("Share", systemImage: "square.and.arrow.up") {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct CircleSwitcherButton: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Menu {
            ForEach(appState.circles) { circle in
                Button {
                    appState.selectCircle(circle)
                } label: {
                    HStack {
                        Text(circle.displayIcon)
                        Text(circle.name)
                        if circle.id == appState.currentCircle?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Create New Circle", systemImage: "plus") {
                // TODO: Open circle creation
            }
        } label: {
            HStack(spacing: 4) {
                Text(appState.currentCircle?.displayIcon ?? "👨‍👩‍👧‍👦")
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
    }
}

struct PatientFilterButton: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Menu {
            Button("All Patients") {}
            Divider()
            ForEach(appState.patients) { patient in
                Button(patient.displayName) {}
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
    }
}

#Preview {
    TimelineView()
        .environmentObject(AppState())
}
