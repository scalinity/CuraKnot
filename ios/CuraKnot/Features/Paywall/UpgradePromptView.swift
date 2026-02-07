import SwiftUI

// MARK: - Upgrade Prompt View

/// A full-screen view shown when users attempt to access premium features
struct UpgradePromptView: View {
    let feature: PremiumFeature
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Feature icon
            ZStack {
                SwiftUI.Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.2), Color.blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: feature.iconName)
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Title
            Text(feature.upgradeTitle)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Description
            Text(feature.upgradeDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // What you get
            VStack(alignment: .leading, spacing: 12) {
                ForEach(feature.upgradePoints, id: \.self) { point in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text(point)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    onUpgrade()
                } label: {
                    Text("Upgrade to Premium")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.teal, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                }
                .accessibilityLabel("Upgrade to premium")
                .accessibilityHint("Opens subscription options")

                Button {
                    onDismiss()
                } label: {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

// MARK: - Inline Upgrade Banner

/// A compact banner for inline upgrade prompts
struct UpgradeBanner: View {
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Premium Feature")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                action()
            } label: {
                Text("Upgrade")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.teal)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
            .accessibilityLabel("Upgrade to premium")
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.teal.opacity(0.1), Color.blue.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.teal.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message), premium feature")
        .accessibilityHint("Tap Upgrade button to see subscription options")
    }
}

// MARK: - Coach Upgrade Prompt

/// Specialized upgrade prompt for the Care Coach feature
struct CoachUpgradePrompt: View {
    let plan: String
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                SwiftUI.Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.15), Color.blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Title
            VStack(spacing: 8) {
                Text("AI Care Coach")
                    .font(.title)
                    .fontWeight(.bold)

                if plan == "FREE" {
                    Text("Available on Plus and Family plans")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You've reached your monthly limit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Description
            Text("Get personalized caregiving guidance, appointment prep help, and emotional support from your AI Care Coach.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Features
            VStack(alignment: .leading, spacing: 12) {
                CoachUpgradeFeature(
                    icon: "heart.text.square",
                    text: "Stress management tips"
                )
                CoachUpgradeFeature(
                    icon: "stethoscope",
                    text: "Appointment preparation"
                )
                CoachUpgradeFeature(
                    icon: "pills",
                    text: "Medication guidance"
                )
                CoachUpgradeFeature(
                    icon: "clock.badge.checkmark",
                    text: "24/7 availability"
                )
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()

            // Upgrade button
            Button {
                onUpgrade()
            } label: {
                HStack {
                    Text(plan == "FREE" ? "Upgrade to Plus" : "Upgrade for Unlimited")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.teal, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .accessibilityLabel("Upgrade subscription")
            .accessibilityHint("Opens subscription options")
        }
    }
}

private struct CoachUpgradeFeature: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Premium Feature Extension

extension PremiumFeature {
    var iconName: String {
        switch self {
        case .appointmentQuestions: return "list.bullet.clipboard"
        case .aiQuestionGeneration: return "sparkles"
        case .coachChat: return "bubble.left.and.bubble.right.fill"
        case .documentScanner: return "doc.text.viewfinder"
        case .medReconciliation: return "pills"
        case .shiftMode: return "clock.badge.checkmark"
        case .operationalInsights: return "chart.line.uptrend.xyaxis"
        case .dischargeWizard: return "cross.case.fill"
        case .facilityCommunicationLog: return "phone.badge.checkmark"
        case .facilityLogAISuggestions: return "sparkles"
        case .conditionPhotoTracking: return "camera.viewfinder"
        case .conditionPhotoCompare: return "photo.stack"
        case .conditionPhotoShare: return "square.and.arrow.up"
        case .familyMeetings: return "person.3.fill"
        case .transportation: return "car.fill"
        case .transportationAnalytics: return "chart.bar.fill"
        case .familyVideoBoard: return "video.fill"
        case .handoffTranslation: return "character.book.closed"
        case .customGlossary: return "text.book.closed"
        case .legalVault: return "lock.doc"
        case .legalVaultUnlimited: return "lock.doc.fill"
        case .careCostTracking: return "dollarsign.circle"
        case .careCostProjections: return "chart.line.uptrend.xyaxis.circle"
        case .careCostExport: return "square.and.arrow.up.on.square"
        case .respiteFinder: return "magnifyingglass"
        case .respiteRequests: return "hand.raised"
        case .respiteReviews: return "star"
        case .respiteTracking: return "clock.badge.checkmark"
        case .respiteReminders: return "bell"
        }
    }

    var upgradeTitle: String {
        switch self {
        case .appointmentQuestions: return "Appointment Questions"
        case .aiQuestionGeneration: return "AI-Generated Questions"
        case .coachChat: return "AI Care Coach"
        case .documentScanner: return "Document Scanner"
        case .medReconciliation: return "Medication Reconciliation"
        case .shiftMode: return "Shift Handoff Mode"
        case .operationalInsights: return "Operational Insights"
        case .dischargeWizard: return "Discharge Planning Wizard"
        case .facilityCommunicationLog: return "Facility Communication Log"
        case .facilityLogAISuggestions: return "AI Task Suggestions"
        case .conditionPhotoTracking: return "Condition Photo Tracking"
        case .conditionPhotoCompare: return "Photo Comparison"
        case .conditionPhotoShare: return "Photo Sharing"
        case .familyMeetings: return "Family Meetings"
        case .transportation: return "Transportation Coordination"
        case .transportationAnalytics: return "Transportation Analytics"
        case .familyVideoBoard: return "Family Video Board"
        case .handoffTranslation: return "Handoff Translation"
        case .customGlossary: return "Custom Glossary"
        case .legalVault: return "Legal Document Vault"
        case .legalVaultUnlimited: return "Unlimited Legal Vault"
        case .careCostTracking: return "Care Cost Tracking"
        case .careCostProjections: return "Cost Projections"
        case .careCostExport: return "Expense Export"
        case .respiteFinder: return "Respite Care Finder"
        case .respiteRequests: return "Respite Requests"
        case .respiteReviews: return "Respite Reviews"
        case .respiteTracking: return "Respite Tracking"
        case .respiteReminders: return "Respite Reminders"
        }
    }

    var upgradeDescription: String {
        switch self {
        case .appointmentQuestions:
            return "Prepare better for medical appointments with smart question suggestions."
        case .aiQuestionGeneration:
            return "Let AI generate personalized questions based on your care situation."
        case .coachChat:
            return "Get guidance and support from an AI assistant that understands caregiving."
        case .documentScanner:
            return "Quickly digitize and organize medical documents, prescriptions, and more."
        case .medReconciliation:
            return "Keep medications accurate by comparing lists and tracking changes."
        case .shiftMode:
            return "Perfect for professional caregivers with structured shift handoffs."
        case .operationalInsights:
            return "Track patterns and trends to optimize care coordination."
        case .dischargeWizard:
            return "Guided support for hospital-to-home transitions with smart checklists."
        case .facilityCommunicationLog:
            return "Track facility calls, manage follow-ups, and never forget who said what."
        case .facilityLogAISuggestions:
            return "Get AI-suggested tasks from your communication logs."
        case .conditionPhotoTracking:
            return "Track wounds, rashes, and other conditions with secure photos over time."
        case .conditionPhotoCompare:
            return "Compare photos side-by-side to track healing progress."
        case .conditionPhotoShare:
            return "Securely share condition photos with care team members."
        case .familyMeetings:
            return "Coordinate and track family meetings with agenda and action items."
        case .transportation:
            return "Organize transportation for medical appointments and care needs."
        case .transportationAnalytics:
            return "Analyze transportation patterns and optimize scheduling."
        case .familyVideoBoard:
            return "Send heartfelt video messages to your loved one in care."
        case .handoffTranslation:
            return "Translate handoffs into multiple languages for multilingual families."
        case .customGlossary:
            return "Create custom medical term glossaries for your care circle."
        case .legalVault, .legalVaultUnlimited:
            return "Securely store POA, advance directives, and legal documents."
        case .careCostTracking:
            return "Track all care-related expenses, insurance coverage, and out-of-pocket costs."
        case .careCostProjections:
            return "Project future care costs across different scenarios like home care vs. facility."
        case .careCostExport:
            return "Export expense reports for tax preparation, insurance, or financial planning."
        case .respiteFinder:
            return "Find respite care providers in your area."
        case .respiteRequests:
            return "Request respite care coverage from your care circle."
        case .respiteReviews:
            return "Read and write reviews for respite care providers."
        case .respiteTracking:
            return "Track respite care usage and provider history."
        case .respiteReminders:
            return "Get reminders for upcoming respite care sessions."
        }
    }

    var upgradePoints: [String] {
        switch self {
        case .appointmentQuestions, .aiQuestionGeneration:
            return [
                "AI-suggested questions",
                "Based on recent handoffs",
                "Export for appointments"
            ]
        case .coachChat:
            return [
                "Personalized guidance",
                "Appointment prep help",
                "Stress management tips",
                "Available 24/7"
            ]
        case .documentScanner:
            return [
                "Medication label scanning",
                "Insurance card capture",
                "OCR text extraction"
            ]
        case .medReconciliation:
            return [
                "Compare medication lists",
                "Track additions & removals",
                "Reconciliation history"
            ]
        case .shiftMode:
            return [
                "Structured shift handoffs",
                "Checklist templates",
                "Delta change tracking"
            ]
        case .operationalInsights:
            return [
                "Care pattern analysis",
                "Member contribution stats",
                "Trend visualization"
            ]
        case .dischargeWizard:
            return [
                "Pre-built discharge checklists",
                "Auto-create tasks from items",
                "Generate discharge handoff"
            ]
        case .facilityCommunicationLog:
            return [
                "One-tap call logging",
                "Follow-up reminders",
                "Searchable history",
                "Quick actions (call, email)"
            ]
        case .facilityLogAISuggestions:
            return [
                "AI analyzes call summaries",
                "Suggests follow-up tasks",
                "One-tap task creation"
            ]
        case .conditionPhotoTracking:
            return [
                "Secure photo storage",
                "Timeline view of progress",
                "Biometric protection"
            ]
        case .conditionPhotoCompare:
            return [
                "Side-by-side comparison",
                "Swipe between photos",
                "Track healing progress"
            ]
        case .conditionPhotoShare:
            return [
                "Secure sharing links",
                "Time-limited access",
                "Share with care team"
            ]
        case .familyMeetings:
            return [
                "Schedule family meetings",
                "Set agenda items",
                "Track action items",
                "Meeting summaries"
            ]
        case .transportation:
            return [
                "Coordinate rides",
                "Track appointments",
                "Driver management"
            ]
        case .transportationAnalytics:
            return [
                "Ride statistics",
                "Driver contributions",
                "Coverage analysis"
            ]
        case .familyVideoBoard:
            return [
                "Send video messages",
                "Patient-friendly playback",
                "Auto-looping videos",
                "Simple reaction system"
            ]
        case .handoffTranslation:
            return [
                "Translate to 20+ languages",
                "Multilingual family support",
                "Medical term accuracy"
            ]
        case .customGlossary:
            return [
                "Custom medical terms",
                "Family-specific vocabulary",
                "Shared across circle"
            ]
        case .legalVault, .legalVaultUnlimited:
            return [
                "Secure document storage",
                "Power of Attorney",
                "Advance directives",
                "Insurance policies"
            ]
        case .careCostTracking:
            return [
                "Track all care expenses",
                "Insurance coverage breakdown",
                "Monthly cost summaries",
                "Receipt attachment"
            ]
        case .careCostProjections:
            return [
                "Compare care scenarios",
                "Regional cost data",
                "Home care vs. facility",
                "Annual cost estimates"
            ]
        case .careCostExport:
            return [
                "PDF and CSV reports",
                "Tax-ready summaries",
                "Custom date ranges"
            ]
        case .respiteFinder:
            return [
                "Search local providers",
                "View ratings and reviews",
                "Contact information"
            ]
        case .respiteRequests:
            return [
                "Request coverage",
                "Schedule respite care",
                "Coordinate with circle"
            ]
        case .respiteReviews:
            return [
                "Write provider reviews",
                "Rate experiences",
                "Help other families"
            ]
        case .respiteTracking:
            return [
                "Usage history",
                "Provider tracking",
                "Cost analysis"
            ]
        case .respiteReminders:
            return [
                "Session reminders",
                "Booking confirmations",
                "Schedule alerts"
            ]
        }
    }
}

// MARK: - Previews

#Preview("Upgrade Prompt") {
    UpgradePromptView(
        feature: .coachChat,
        onUpgrade: {},
        onDismiss: {}
    )
}

#Preview("Upgrade Banner") {
    UpgradeBanner(
        message: "Unlimited AI messages with Family plan",
        action: {}
    )
    .padding()
}

#Preview("Coach Upgrade - Free") {
    CoachUpgradePrompt(plan: "FREE", onUpgrade: {})
}

#Preview("Coach Upgrade - Plus") {
    CoachUpgradePrompt(plan: "PLUS", onUpgrade: {})
}
