import SwiftUI

// MARK: - Binder View

struct BinderView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @State private var items: [BinderItem] = []
    @State private var searchText = ""
    
    var sections: [(type: BinderItem.ItemType, items: [BinderItem])] {
        BinderItem.ItemType.allCases.compactMap { type in
            let typeItems = items.filter { $0.type == type }
            return typeItems.isEmpty ? nil : (type, typeItems)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Condition Photo Tracking (Plus+ only)
                // TODO: Re-enable after ConditionPhotoService is fixed
                /*
                if dependencyContainer.subscriptionManager.hasFeature(.conditionPhotoTracking),
                   let circleIdStr = appState.currentCircle?.id,
                   let circleId = UUID(uuidString: circleIdStr),
                   let patientIdStr = appState.patients.first?.id,
                   let patientId = UUID(uuidString: patientIdStr) {
                    Section {
                        NavigationLink {
                            ConditionListView(circleId: circleId, patientId: patientId)
                        } label: {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 30)
                                Text("Condition Tracking")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                */

                // Legal Document Vault (Plus+ only)
                if dependencyContainer.subscriptionManager.hasFeature(.legalVault) {
                    Section {
                        NavigationLink {
                            LegalVaultView(service: dependencyContainer.legalVaultService)
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 30)
                                Text("Legal Documents")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                ForEach(Array(BinderItem.ItemType.allCases), id: \.self) { type in
                    let typeItems = items.filter { $0.type == type }
                    
                    NavigationLink {
                        BinderSectionView(type: type, items: typeItems)
                    } label: {
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 30)
                            
                            Text(type.pluralName)
                            
                            Spacer()
                            
                            Text("\(typeItems.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Binder")
            .searchable(text: $searchText, prompt: "Search binder")
        }
    }
}

// MARK: - Binder Section View

struct BinderSectionView: View {
    let type: BinderItem.ItemType
    let items: [BinderItem]
    
    @State private var showingEditor = false
    
    var body: some View {
        List {
            if items.isEmpty {
                EmptyStateView(
                    icon: type.icon,
                    title: "No \(type.pluralName)",
                    message: "Add \(type.displayName.lowercased())s to keep track of important information.",
                    actionTitle: "Add \(type.displayName)"
                ) {
                    showingEditor = true
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        BinderItemDetailView(item: item)
                    } label: {
                        BinderItemCell(item: item)
                    }
                }
            }
        }
        .navigationTitle(type.pluralName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            // TODO: Item editor based on type
            Text("Editor for \(type.displayName)")
        }
    }
}

// MARK: - Binder Item Cell

struct BinderItemCell: View {
    let item: BinderItem
    
    var body: some View {
        HStack {
            Image(systemName: item.type.icon)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                
                // TODO: Type-specific subtitle
                Text("Last updated \(item.updatedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Binder Item Detail View

struct BinderItemDetailView: View {
    let item: BinderItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: item.type.icon)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                    
                    Text(item.title)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Divider()
                
                // TODO: Type-specific content display
                Text("Content will be displayed here based on item type")
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle(item.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", systemImage: "pencil") {
                    // TODO: Open editor
                }
            }
        }
    }
}

// MARK: - Medication Editor View

struct MedicationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var dose = ""
    @State private var schedule = ""
    @State private var purpose = ""
    @State private var prescriber = ""
    @State private var pharmacy = ""
    @State private var startDate = Date()
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $name)
                    TextField("Dose (e.g., 10mg)", text: $dose)
                    TextField("Schedule (e.g., twice daily)", text: $schedule)
                }
                
                Section("Details") {
                    TextField("Purpose", text: $purpose)
                    TextField("Prescriber", text: $prescriber)
                    TextField("Pharmacy", text: $pharmacy)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                }
                
                Section("Notes") {
                    TextField("Additional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // TODO: Save medication
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    BinderView()
        .environmentObject(AppState())
}
