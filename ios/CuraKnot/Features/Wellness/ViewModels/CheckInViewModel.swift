import Foundation
import SwiftUI

// MARK: - Check-In View Model

/// ViewModel for the weekly wellness check-in flow
/// Designed for < 30 second completion time
@MainActor
final class CheckInViewModel: ObservableObject {

    // MARK: - Types

    enum CheckInStep: Int, CaseIterable {
        case stress = 0
        case sleep = 1
        case capacity = 2
        case notes = 3
        case review = 4

        var title: String {
            switch self {
            case .stress: return "How stressed are you?"
            case .sleep: return "How's your sleep been?"
            case .capacity: return "What's your capacity?"
            case .notes: return "Anything to note?"
            case .review: return "Review"
            }
        }

        var subtitle: String {
            switch self {
            case .stress: return "Rate your stress level this week"
            case .sleep: return "Rate your sleep quality this week"
            case .capacity: return "How much can you take on?"
            case .notes: return "Optional - encrypted for privacy"
            case .review: return "Your weekly wellness check-in"
            }
        }

        var isOptional: Bool {
            self == .notes
        }
    }

    // MARK: - Properties

    private let wellnessService: WellnessService
    private let onComplete: (WellnessCheckIn) -> Void

    @Published var currentStep: CheckInStep = .stress
    @Published var stressLevel: Int = 3
    @Published var sleepQuality: Int = 3
    @Published var capacityLevel: Int = 2
    @Published var notes: String = ""
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    var progress: Double {
        Double(currentStep.rawValue) / Double(CheckInStep.allCases.count - 1)
    }

    var canGoBack: Bool {
        currentStep.rawValue > 0
    }

    var canGoNext: Bool {
        currentStep.rawValue < CheckInStep.allCases.count - 1
    }

    var isOnReviewStep: Bool {
        currentStep == .review
    }

    // MARK: - Stress Level Descriptions

    var stressDescription: String {
        switch stressLevel {
        case 1: return "Calm and relaxed"
        case 2: return "Slightly stressed"
        case 3: return "Moderately stressed"
        case 4: return "Very stressed"
        case 5: return "Extremely stressed"
        default: return ""
        }
    }

    var stressEmoji: String {
        switch stressLevel {
        case 1: return "😌"
        case 2: return "😐"
        case 3: return "😟"
        case 4: return "😰"
        case 5: return "😫"
        default: return "❓"
        }
    }

    // MARK: - Sleep Quality Descriptions

    var sleepDescription: String {
        switch sleepQuality {
        case 1: return "Very poor sleep"
        case 2: return "Poor sleep"
        case 3: return "Okay sleep"
        case 4: return "Good sleep"
        case 5: return "Excellent sleep"
        default: return ""
        }
    }

    var sleepEmoji: String {
        switch sleepQuality {
        case 1: return "💀"
        case 2: return "😵"
        case 3: return "😶"
        case 4: return "🥱"
        case 5: return "😴"
        default: return "❓"
        }
    }

    // MARK: - Capacity Level Descriptions

    var capacityDescription: String {
        switch capacityLevel {
        case 1: return "Running on empty"
        case 2: return "Limited capacity"
        case 3: return "Some room"
        case 4: return "Full capacity"
        default: return ""
        }
    }

    var capacityEmoji: String {
        switch capacityLevel {
        case 1: return "🫠"
        case 2: return "🤏"
        case 3: return "✋"
        case 4: return "💪"
        default: return "❓"
        }
    }

    // MARK: - Initialization

    init(wellnessService: WellnessService, onComplete: @escaping (WellnessCheckIn) -> Void) {
        self.wellnessService = wellnessService
        self.onComplete = onComplete
    }

    // MARK: - Navigation

    func goNext() {
        guard canGoNext else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = CheckInStep(rawValue: currentStep.rawValue + 1) ?? .review
        }
    }

    func goBack() {
        guard canGoBack else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = CheckInStep(rawValue: currentStep.rawValue - 1) ?? .stress
        }
    }

    func jumpToStep(_ step: CheckInStep) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = step
        }
    }

    // MARK: - Submission

    func submit() async {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        do {
            let checkIn = try await wellnessService.submitCheckIn(
                stressLevel: stressLevel,
                sleepQuality: sleepQuality,
                capacityLevel: capacityLevel,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete(checkIn)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func skip() async {
        isSubmitting = true
        errorMessage = nil

        do {
            try await wellnessService.skipCheckIn()
            // Create a placeholder check-in for completion callback
            let skippedCheckIn = WellnessCheckIn(
                userId: "",
                stressLevel: 3,
                sleepQuality: 3,
                capacityLevel: 2,
                skipped: true
            )
            onComplete(skippedCheckIn)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}
