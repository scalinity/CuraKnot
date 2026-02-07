import SwiftUI

// MARK: - Color Extensions (View Layer)

extension ScheduledRide.ConfirmationStatus {
    var color: Color {
        switch self {
        case .unconfirmed: return .orange
        case .confirmed: return .green
        case .declined: return .red
        }
    }
}

extension ScheduledRide.RideStatus {
    var color: Color {
        switch self {
        case .scheduled: return .blue
        case .completed: return .green
        case .cancelled: return .secondary
        case .missed: return .red
        }
    }
}
