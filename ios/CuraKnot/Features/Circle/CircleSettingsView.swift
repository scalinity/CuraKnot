import SwiftUI

// MARK: - Circle Settings View

struct CircleSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var showingInvite = false
    @State private var showingExport = false
    @State private var showingPatientManagement = false
    
    var body: some View {
        NavigationStack {
            List {
                // Circle Info
                if let circle = appState.currentCircle {
                    Section {
                        HStack {
                            Text(circle.displayIcon)
                                .font(.largeTitle)
                            
                            VStack(alignment: .leading) {
                                Text(circle.name)
                                    .font(.headline)
                                Text(circle.plan.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Members
                Section("Members") {
                    // TODO: Show actual members
                    NavigationLink {
                        MemberListView()
                    } label: {
                        Label("View Members", systemImage: "person.2")
                    }
                    
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Invite Member", systemImage: "person.badge.plus")
                    }
                }
                
                // Patients
                Section("Patients") {
                    NavigationLink {
                        PatientManagementView()
                    } label: {
                        Label("Manage Patients", systemImage: "person.crop.circle")
                    }
                }
                
                // Exports
                Section("Exports") {
                    Button {
                        showingExport = true
                    } label: {
                        Label("Generate Care Summary", systemImage: "doc.text")
                    }
                }
                
                // Calendar Sync
                Section("Calendar") {
                    NavigationLink {
                        CalendarSettingsView(
                            calendarSyncService: container.calendarSyncService,
                            appleProvider: container.appleCalendarProvider
                        )
                    } label: {
                        Label("Calendar Sync", systemImage: "calendar.badge.clock")
                    }
                }

                // Transportation (PLUS+ only)
                if container.subscriptionManager.hasFeature(.transportation) {
                    Section("Transportation") {
                        NavigationLink {
                            TransportationView()
                        } label: {
                            Label("Medical Transportation", systemImage: "car.side")
                        }
                    }
                }

                // Coordination
                if container.subscriptionManager.hasFeature(.familyMeetings) {
                    Section("Coordination") {
                        if let circle = appState.currentCircle,
                           let patient = appState.currentPatient,
                           let circleUUID = UUID(uuidString: circle.id) {
                            NavigationLink {
                                MeetingListView(
                                    circleId: circleUUID,
                                    service: container.familyMeetingService,
                                    subscriptionManager: container.subscriptionManager
                                )
                            } label: {
                                Label("Family Meetings", systemImage: "person.3")
                            }
                        }
                    }
                }

                // Language & Translation
                Section("Language") {
                    if let circle = appState.currentCircle {
                        NavigationLink {
                            CircleLanguageOverviewView(
                                circleId: circle.id,
                                translationService: container.translationService,
                                subscriptionManager: container.subscriptionManager,
                                userId: appState.currentUser?.id ?? ""
                            )
                        } label: {
                            Label("Circle Languages", systemImage: "globe")
                        }
                    }

                    NavigationLink {
                        LanguageSettingsView(
                            translationService: container.translationService,
                            subscriptionManager: container.subscriptionManager,
                            userId: appState.currentUser?.id ?? ""
                        )
                    } label: {
                        Label("Language Preferences", systemImage: "character.book.closed")
                    }
                }

                // Settings
                Section("Settings") {
                    NavigationLink {
                        CirclePrivacySettingsView()
                    } label: {
                        Label("Privacy & Data", systemImage: "lock.shield")
                    }

                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }
                }
                
                // Account
                Section {
                    Button(role: .destructive) {
                        Task {
                            await appState.signOut()
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Circle")
            .sheet(isPresented: $showingInvite) {
                InviteView()
            }
            .sheet(isPresented: $showingExport) {
                ExportView()
            }
        }
    }
}

// MARK: - Member List View

struct MemberListView: View {
    var body: some View {
        List {
            // TODO: Show actual members with roles
            Text("Member list will appear here")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Members")
    }
}

// MARK: - Patient Management View

struct PatientManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingNewPatient = false
    
    var body: some View {
        List {
            ForEach(appState.patients) { patient in
                NavigationLink {
                    PatientEditorView(patient: patient)
                } label: {
                    HStack {
                        Text(patient.displayInitials)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor, in: SwiftUI.Circle())
                        
                        VStack(alignment: .leading) {
                            Text(patient.displayName)
                                .font(.headline)
                            if let age = patient.age {
                                Text("\(age) years old")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Patients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewPatient = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewPatient) {
            PatientEditorView(patient: nil)
        }
    }
}

// MARK: - Patient Editor View

struct PatientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let patient: Patient?
    
    @State private var displayName = ""
    @State private var initials = ""
    @State private var dob = Date()
    @State private var hasDOB = false
    @State private var pronouns = ""
    @State private var notes = ""
    
    var isEditing: Bool {
        patient != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $displayName)
                    TextField("Initials (optional)", text: $initials)
                        .textInputAutocapitalization(.characters)
                }
                
                Section {
                    Toggle("Date of Birth", isOn: $hasDOB)
                    if hasDOB {
                        DatePicker("DOB", selection: $dob, displayedComponents: .date)
                    }
                    
                    TextField("Pronouns (optional)", text: $pronouns)
                }
                
                Section("Notes") {
                    TextField("Notes about this patient", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Patient" : "New Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // TODO: Save patient
                        dismiss()
                    }
                    .disabled(displayName.isEmpty)
                }
            }
            .onAppear {
                if let patient = patient {
                    displayName = patient.displayName
                    initials = patient.initials ?? ""
                    if let patientDOB = patient.dob {
                        dob = patientDOB
                        hasDOB = true
                    }
                    pronouns = patient.pronouns ?? ""
                    notes = patient.notes ?? ""
                }
            }
        }
    }
}

// MARK: - Invite View

struct InviteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inviteLink = ""
    @State private var selectedRole: CircleMember.Role = .contributor
    @State private var isGenerating = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Role Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Role")
                        .font(.headline)
                    
                    Picker("Role", selection: $selectedRole) {
                        Text("Admin").tag(CircleMember.Role.admin)
                        Text("Contributor").tag(CircleMember.Role.contributor)
                        Text("Viewer").tag(CircleMember.Role.viewer)
                    }
                    .pickerStyle(.segmented)
                    
                    Text(roleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                Divider()
                
                // Generate Button
                if inviteLink.isEmpty {
                    Button {
                        generateInvite()
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Text("Generate Invite Link")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                } else {
                    // Show link
                    VStack(spacing: 16) {
                        Text("Share this link:")
                            .font(.headline)
                        
                        Text(inviteLink)
                            .font(.caption)
                            .padding()
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        
                        HStack(spacing: 16) {
                            Button {
                                UIPasteboard.general.string = inviteLink
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            
                            ShareLink(item: inviteLink) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var roleDescription: String {
        switch selectedRole {
        case .admin:
            return "Can manage members, create handoffs and tasks, edit binder."
        case .contributor:
            return "Can create handoffs and tasks, edit binder."
        case .viewer:
            return "Can view timeline and binder. Can complete assigned tasks."
        case .owner:
            return "Full control over the circle."
        }
    }
    
    private func generateInvite() {
        isGenerating = true
        // TODO: Generate invite via API
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            inviteLink = "https://curaknot.app/join/abc123"
            isGenerating = false
        }
    }
}

// MARK: - Export View

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate = Date()
    @State private var selectedPatients: Set<String> = []
    @State private var includeHandoffs = true
    @State private var includeMedChanges = true
    @State private var includeQuestions = true
    @State private var includeTasks = true
    @State private var includeContacts = true
    @State private var isGenerating = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                
                Section("Patients") {
                    ForEach(appState.patients) { patient in
                        Toggle(patient.displayName, isOn: Binding(
                            get: { selectedPatients.contains(patient.id) },
                            set: { isOn in
                                if isOn {
                                    selectedPatients.insert(patient.id)
                                } else {
                                    selectedPatients.remove(patient.id)
                                }
                            }
                        ))
                    }
                }
                
                Section("Include") {
                    Toggle("Handoff Summaries", isOn: $includeHandoffs)
                    Toggle("Medication Changes", isOn: $includeMedChanges)
                    Toggle("Questions for Clinician", isOn: $includeQuestions)
                    Toggle("Outstanding Tasks", isOn: $includeTasks)
                    Toggle("Key Contacts", isOn: $includeContacts)
                }
                
                Section {
                    Button {
                        generateExport()
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                            } else {
                                Text("Generate PDF")
                            }
                            Spacer()
                        }
                    }
                    .disabled(selectedPatients.isEmpty || isGenerating)
                }
            }
            .navigationTitle("Care Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Select all patients by default
                selectedPatients = Set(appState.patients.map { $0.id })
            }
        }
    }
    
    private func generateExport() {
        isGenerating = true
        // TODO: Generate export via API
    }
}

// MARK: - Settings Views

struct CirclePrivacySettingsView: View {
    @State private var transcriptRetention = 30
    @State private var audioRetention = 30
    @State private var commentsEnabled = false
    
    var body: some View {
        Form {
            Section("Data Retention") {
                Picker("Transcript Retention", selection: $transcriptRetention) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                
                Picker("Audio Retention", selection: $audioRetention) {
                    Text("Delete after publish").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
            }
            
            Section("Features") {
                Toggle("Enable Comments", isOn: $commentsEnabled)
            }
        }
        .navigationTitle("Privacy & Data")
    }
}

struct NotificationSettingsView: View {
    @State private var handoffNotifications = true
    @State private var taskNotifications = true
    @State private var quietHoursEnabled = false
    @State private var quietStart = Date()
    @State private var quietEnd = Date()
    
    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("New Handoffs", isOn: $handoffNotifications)
                Toggle("Task Reminders", isOn: $taskNotifications)
            }
            
            Section("Quiet Hours") {
                Toggle("Enable Quiet Hours", isOn: $quietHoursEnabled)
                
                if quietHoursEnabled {
                    DatePicker("Start", selection: $quietStart, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $quietEnd, displayedComponents: .hourAndMinute)
                }
            }
        }
        .navigationTitle("Notifications")
    }
}

#Preview {
    CircleSettingsView()
        .environmentObject(AppState())
}
