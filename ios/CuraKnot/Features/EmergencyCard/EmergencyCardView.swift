import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Emergency Card Model

struct EmergencyCard: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let createdBy: UUID
    var configJson: CardConfig
    var snapshotJson: CardSnapshot
    var version: Int
    var lastSyncedAt: Date?
    let createdAt: Date
    var updatedAt: Date
    
    struct CardConfig: Codable {
        var includeName: Bool
        var includeDob: Bool
        var includeBloodType: Bool
        var includeAllergies: Bool
        var includeConditions: Bool
        var includeMedications: Bool
        var includeEmergencyContacts: Bool
        var includePhysician: Bool
        var includeInsurance: Bool
        var includeNotes: Bool
        
        enum CodingKeys: String, CodingKey {
            case includeName = "include_name"
            case includeDob = "include_dob"
            case includeBloodType = "include_blood_type"
            case includeAllergies = "include_allergies"
            case includeConditions = "include_conditions"
            case includeMedications = "include_medications"
            case includeEmergencyContacts = "include_emergency_contacts"
            case includePhysician = "include_physician"
            case includeInsurance = "include_insurance"
            case includeNotes = "include_notes"
        }
        
        static var defaults: CardConfig {
            CardConfig(
                includeName: true,
                includeDob: false,
                includeBloodType: false,
                includeAllergies: true,
                includeConditions: true,
                includeMedications: true,
                includeEmergencyContacts: true,
                includePhysician: true,
                includeInsurance: false,
                includeNotes: false
            )
        }
    }
    
    struct CardSnapshot: Codable {
        var generatedAt: Date?
        var version: Int?
        var name: String?
        var initials: String?
        var dob: String?
        var allergies: [Allergy]?
        var conditions: [String]?
        var medications: [Medication]?
        var emergencyContacts: [Contact]?
        var physician: Contact?
        var customFields: [CustomField]?
        
        struct Allergy: Codable {
            let name: String?
            let severity: String?
        }
        
        struct Medication: Codable {
            let name: String?
            let dose: String?
            let schedule: String?
        }
        
        struct Contact: Codable {
            let name: String?
            let role: String?
            let phone: String?
        }
        
        struct CustomField: Codable {
            let label: String?
            let value: String?
        }
        
        enum CodingKeys: String, CodingKey {
            case generatedAt = "generated_at"
            case version, name, initials, dob, allergies, conditions, medications
            case emergencyContacts = "emergency_contacts"
            case physician
            case customFields = "custom_fields"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case configJson = "config_json"
        case snapshotJson = "snapshot_json"
        case version
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Emergency Card View

struct EmergencyCardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPatient: Patient?
    @State private var card: EmergencyCard?
    @State private var isLoading = false
    @State private var showingConfig = false
    @State private var showingQRShare = false
    @State private var shareLink: ShareLink?
    
    struct ShareLink {
        let token: String
        let url: String
        let expiresAt: Date
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Patient Selector
                if appState.patients.count > 1 {
                    Picker("Patient", selection: $selectedPatient) {
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }
                
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if let card = card {
                    ScrollView {
                        CardDisplayView(snapshot: card.snapshotJson)
                            .padding()
                    }
                } else {
                    EmptyStateView(
                        icon: "staroflife",
                        title: "No Emergency Card",
                        message: "Create an emergency card with critical info for responders.",
                        actionTitle: "Create Card"
                    ) {
                        createCard()
                    }
                }
            }
            .navigationTitle("Emergency Card")
            .toolbar {
                if card != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingConfig = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingQRShare = true
                        } label: {
                            Image(systemName: "qrcode")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingConfig) {
                if let card = card {
                    EmergencyCardConfigView(card: card) { updatedCard in
                        self.card = updatedCard
                    }
                }
            }
            .sheet(isPresented: $showingQRShare) {
                if let card = card {
                    QRShareView(card: card, shareLink: shareLink) { newLink in
                        self.shareLink = newLink
                    }
                }
            }
            .onAppear {
                selectedPatient = appState.patients.first
            }
            .onChange(of: selectedPatient) { _, patient in
                loadCard(for: patient)
            }
        }
    }
    
    private func loadCard(for patient: Patient?) {
        guard patient != nil else { return }
        isLoading = true
        // TODO: Load from local cache or Supabase
        isLoading = false
    }
    
    private func createCard() {
        guard selectedPatient != nil else { return }
        isLoading = true
        // TODO: Create card via edge function
        isLoading = false
    }
}

// MARK: - Card Display View

struct CardDisplayView: View {
    let snapshot: EmergencyCard.CardSnapshot
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "staroflife.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                
                if let name = snapshot.name {
                    Text(name)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                if let dob = snapshot.dob {
                    Text("DOB: \(dob)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Allergies
            if let allergies = snapshot.allergies, !allergies.isEmpty {
                CardSection(title: "Allergies", icon: "exclamationmark.triangle.fill", color: .orange) {
                    ForEach(allergies.indices, id: \.self) { index in
                        if let name = allergies[index].name {
                            HStack {
                                Text(name)
                                Spacer()
                                if let severity = allergies[index].severity {
                                    Text(severity)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            
            // Conditions
            if let conditions = snapshot.conditions, !conditions.isEmpty {
                CardSection(title: "Medical Conditions", icon: "heart.text.square.fill", color: .purple) {
                    ForEach(conditions, id: \.self) { condition in
                        Text(condition)
                    }
                }
            }
            
            // Medications
            if let medications = snapshot.medications, !medications.isEmpty {
                CardSection(title: "Medications", icon: "pills.fill", color: .blue) {
                    ForEach(medications.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medications[index].name ?? "")
                                .fontWeight(.medium)
                            if let dose = medications[index].dose, let schedule = medications[index].schedule {
                                Text("\(dose) • \(schedule)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Emergency Contacts
            if let contacts = snapshot.emergencyContacts, !contacts.isEmpty {
                CardSection(title: "Emergency Contacts", icon: "phone.fill", color: .green) {
                    ForEach(contacts.indices, id: \.self) { index in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(contacts[index].name ?? "")
                                    .fontWeight(.medium)
                                if let role = contacts[index].role {
                                    Text(role)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let phone = contacts[index].phone {
                                Link(destination: URL(string: "tel:\(phone)")!) {
                                    Image(systemName: "phone.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            
            // Physician
            if let physician = snapshot.physician {
                CardSection(title: "Primary Physician", icon: "stethoscope", color: .teal) {
                    HStack {
                        Text(physician.name ?? "")
                        Spacer()
                        if let phone = physician.phone {
                            Link(destination: URL(string: "tel:\(phone)")!) {
                                Image(systemName: "phone.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                }
            }
            
            // Last updated
            if let generatedAt = snapshot.generatedAt {
                Text("Last updated: \(generatedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Card Section

struct CardSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    EmergencyCardView()
        .environmentObject(AppState())
}
