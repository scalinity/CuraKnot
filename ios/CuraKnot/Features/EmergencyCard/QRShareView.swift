import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QR Share View

struct QRShareView: View {
    @Environment(\.dismiss) private var dismiss
    
    let card: EmergencyCard
    var shareLink: EmergencyCardView.ShareLink?
    let onLinkCreated: (EmergencyCardView.ShareLink) -> Void
    
    @State private var isGenerating = false
    @State private var currentLink: EmergencyCardView.ShareLink?
    @State private var ttlHours = 24
    @State private var showingExplanation = false
    
    let ttlOptions = [
        (1, "1 hour"),
        (24, "24 hours"),
        (72, "3 days"),
        (168, "1 week")
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Warning Banner
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Share Carefully")
                                .font(.headline)
                            Text("This QR code provides access to medical information. Only share with trusted parties.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if let link = currentLink ?? shareLink {
                        // QR Code Display
                        VStack(spacing: 16) {
                            QRCodeImage(url: link.url)
                                .frame(width: 200, height: 200)
                            
                            // Link Info
                            VStack(spacing: 8) {
                                Text("Scan to view emergency info")
                                    .font(.headline)
                                
                                Text("Expires \(link.expiresAt, style: .relative)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Actions
                            HStack(spacing: 16) {
                                Button {
                                    UIPasteboard.general.string = link.url
                                } label: {
                                    Label("Copy Link", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                
                                ShareLink(item: URL(string: link.url)!) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // Revoke option
                        Button(role: .destructive) {
                            revokeLink()
                        } label: {
                            Label("Revoke This Link", systemImage: "xmark.circle")
                        }
                        .padding(.top)
                        
                    } else {
                        // Create New Link
                        VStack(spacing: 20) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            
                            Text("Generate a QR code to share this emergency card")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            
                            // TTL Picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Link expires after:")
                                    .font(.subheadline)
                                
                                Picker("Expiration", selection: $ttlHours) {
                                    ForEach(ttlOptions, id: \.0) { option in
                                        Text(option.1).tag(option.0)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            Button {
                                generateLink()
                            } label: {
                                HStack {
                                    if isGenerating {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(isGenerating ? "Generating..." : "Generate QR Code")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating)
                        }
                        .padding()
                    }
                    
                    // Explanation
                    DisclosureGroup("How does this work?", isExpanded: $showingExplanation) {
                        VStack(alignment: .leading, spacing: 12) {
                            ExplanationRow(
                                icon: "lock.fill",
                                title: "Secure Link",
                                text: "Each QR code contains a unique token that expires after the chosen time."
                            )
                            ExplanationRow(
                                icon: "eye.slash.fill",
                                title: "No Account Needed",
                                text: "Anyone with the link can view the card without signing up."
                            )
                            ExplanationRow(
                                icon: "xmark.shield.fill",
                                title: "Revocable",
                                text: "You can revoke access anytime, making the link stop working."
                            )
                            ExplanationRow(
                                icon: "list.bullet.clipboard",
                                title: "Access Logged",
                                text: "Each access is logged for your security."
                            )
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Share Emergency Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func generateLink() {
        isGenerating = true
        
        // TODO: Call generate-emergency-card edge function with create_share_link=true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isGenerating = false
            let newLink = EmergencyCardView.ShareLink(
                token: UUID().uuidString.prefix(12).lowercased(),
                url: "https://app.curaknot.com/emergency/\(UUID().uuidString.prefix(12).lowercased())",
                expiresAt: Date().addingTimeInterval(Double(ttlHours) * 3600)
            )
            currentLink = newLink
            onLinkCreated(newLink)
        }
    }
    
    private func revokeLink() {
        // TODO: Call revoke_share_link
        currentLink = nil
    }
}

// MARK: - Explanation Row

struct ExplanationRow: View {
    let icon: String
    let title: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - QR Code Image

struct QRCodeImage: View {
    let url: String
    
    var body: some View {
        if let image = generateQRCode(from: url) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale up for better quality
        let scale = UIScreen.main.scale * 3
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Emergency Card Config View

struct EmergencyCardConfigView: View {
    @Environment(\.dismiss) private var dismiss
    
    let card: EmergencyCard
    let onSave: (EmergencyCard) -> Void
    
    @State private var config: EmergencyCard.CardConfig
    @State private var isSaving = false
    
    init(card: EmergencyCard, onSave: @escaping (EmergencyCard) -> Void) {
        self.card = card
        self.onSave = onSave
        self._config = State(initialValue: card.configJson)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    Toggle("Name", isOn: $config.includeName)
                    Toggle("Date of Birth", isOn: $config.includeDob)
                    Toggle("Blood Type", isOn: $config.includeBloodType)
                }
                
                Section("Medical Information") {
                    Toggle("Allergies", isOn: $config.includeAllergies)
                    Toggle("Medical Conditions", isOn: $config.includeConditions)
                    Toggle("Medications", isOn: $config.includeMedications)
                }
                
                Section("Contacts") {
                    Toggle("Emergency Contacts", isOn: $config.includeEmergencyContacts)
                    Toggle("Primary Physician", isOn: $config.includePhysician)
                }
                
                Section("Other") {
                    Toggle("Insurance Info", isOn: $config.includeInsurance)
                    Toggle("Additional Notes", isOn: $config.includeNotes)
                }
                
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        
                        Text("Only enabled fields will be visible on the emergency card and in shared links.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Card Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConfig()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
    
    private func saveConfig() {
        isSaving = true
        
        // TODO: Update card via API
        var updatedCard = card
        updatedCard.configJson = config
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            onSave(updatedCard)
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    QRShareView(
        card: EmergencyCard(
            id: UUID(),
            circleId: UUID(),
            patientId: UUID(),
            createdBy: UUID(),
            configJson: .defaults,
            snapshotJson: EmergencyCard.CardSnapshot(),
            version: 1,
            createdAt: Date(),
            updatedAt: Date()
        ),
        shareLink: nil
    ) { _ in }
}
