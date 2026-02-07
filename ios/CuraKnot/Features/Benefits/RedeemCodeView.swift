import SwiftUI

// MARK: - Benefit Redemption Model

struct BenefitRedemption: Identifiable, Codable {
    let id: UUID
    let benefitCodeId: UUID
    let circleId: UUID?
    let userId: UUID
    let redeemedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case benefitCodeId = "benefit_code_id"
        case circleId = "circle_id"
        case userId = "user_id"
        case redeemedAt = "redeemed_at"
    }
}

// MARK: - Redeem Code View

struct RedeemCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var code = ""
    @State private var isRedeeming = false
    @State private var result: RedemptionResult?
    @State private var errorMessage: String?
    
    struct RedemptionResult {
        let plan: String
        let orgName: String
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let result = result {
                    // Success State
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        
                        Text("Code Redeemed!")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(spacing: 8) {
                            Text("Your circle has been upgraded to")
                                .foregroundStyle(.secondary)
                            
                            Text(result.plan)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                            
                            if !result.orgName.isEmpty {
                                Text("Sponsored by \(result.orgName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                    .padding()
                } else {
                    // Input State
                    VStack(spacing: 20) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        
                        Text("Redeem Benefit Code")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Enter a code from your employer or insurer to unlock premium features.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        
                        // Code Input
                        TextField("Enter code", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.title3.monospaced())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        
                        Button {
                            redeemCode()
                        } label: {
                            HStack {
                                if isRedeeming {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isRedeeming ? "Redeeming..." : "Redeem Code")
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(code.isEmpty || isRedeeming)
                        .padding(.horizontal)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Info Section
                if result == nil {
                    VStack(spacing: 12) {
                        Text("Where do I get a code?")
                            .font(.headline)
                        
                        Text("Benefit codes are provided by employers and insurance companies that offer CuraKnot as a caregiver benefit. Contact your HR department or benefits administrator.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
            }
            .navigationTitle("Redeem Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func redeemCode() {
        errorMessage = nil
        isRedeeming = true
        
        // TODO: Call redeem-benefit-code edge function
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isRedeeming = false
            
            // Simulate success for demo
            if code.uppercased().hasPrefix("DEMO") {
                result = RedemptionResult(plan: "FAMILY", orgName: "Demo Company")
            } else {
                errorMessage = "Invalid or expired code. Please check and try again."
            }
        }
    }
}

// MARK: - Plan Status View

struct PlanStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingRedeemCode = false
    
    var currentPlan: String {
        (appState.currentCircle?.plan ?? .free).rawValue
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Current Plan
            VStack(spacing: 8) {
                Text("Current Plan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(currentPlan)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(planColor)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(planColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Features
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Plan Includes")
                    .font(.headline)
                
                FeatureRow(icon: "checkmark.circle.fill", text: "Unlimited handoffs", included: true)
                FeatureRow(icon: "checkmark.circle.fill", text: "Care circle with \(memberLimit) members", included: true)
                FeatureRow(icon: currentPlan != "FREE" ? "checkmark.circle.fill" : "xmark.circle", text: "Advanced exports", included: currentPlan != "FREE")
                FeatureRow(icon: currentPlan == "FAMILY" ? "checkmark.circle.fill" : "xmark.circle", text: "Multiple patients", included: currentPlan == "FAMILY")
                FeatureRow(icon: currentPlan == "FAMILY" ? "checkmark.circle.fill" : "xmark.circle", text: "Shift scheduling", included: currentPlan == "FAMILY")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Redeem Code Button
            Button {
                showingRedeemCode = true
            } label: {
                Label("Redeem Benefit Code", systemImage: "gift")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Plan & Billing")
        .sheet(isPresented: $showingRedeemCode) {
            RedeemCodeView()
        }
    }
    
    var planColor: Color {
        switch currentPlan {
        case "FAMILY": return .purple
        case "PLUS": return .blue
        default: return .secondary
        }
    }
    
    var memberLimit: String {
        switch currentPlan {
        case "FAMILY": return "unlimited"
        case "PLUS": return "10"
        default: return "5"
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let included: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(included ? .green : .secondary)
            
            Text(text)
                .foregroundStyle(included ? .primary : .secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    RedeemCodeView()
        .environmentObject(AppState())
}
