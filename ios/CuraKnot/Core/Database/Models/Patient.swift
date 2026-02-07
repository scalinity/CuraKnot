import Foundation
import GRDB

// MARK: - Patient Model

struct Patient: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let circleId: String
    var displayName: String
    var initials: String?
    var dob: Date?
    var pronouns: String?
    var notes: String?
    var archivedAt: Date?
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Computed Properties
    
    var isArchived: Bool {
        archivedAt != nil
    }
    
    var displayInitials: String {
        if let initials = initials, !initials.isEmpty {
            return initials
        }
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
    
    var age: Int? {
        guard let dob = dob else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year], from: dob, to: now)
        return components.year
    }
    
    private static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var formattedDOB: String? {
        guard let dob = dob else { return nil }
        return Self.dobFormatter.string(from: dob)
    }
}

// MARK: - GRDB Conformance

extension Patient: FetchableRecord, PersistableRecord {
    static let databaseTableName = "patients"
}
