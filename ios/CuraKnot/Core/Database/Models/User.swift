import Foundation
import GRDB

// MARK: - User Model

struct User: Codable, Identifiable, Equatable {
    let id: String
    var email: String?
    var appleSub: String?
    var displayName: String
    var avatarUrl: String?
    var settingsJson: String?
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Computed Properties
    
    var settings: UserSettings {
        get {
            guard let json = settingsJson,
                  let data = json.data(using: .utf8) else {
                return UserSettings()
            }
            return (try? JSONDecoder().decode(UserSettings.self, from: data)) ?? UserSettings()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                settingsJson = json
            }
        }
    }
    
    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

// MARK: - GRDB Conformance

extension User: FetchableRecord, PersistableRecord {
    static let databaseTableName = "users"
}

// MARK: - User Settings

struct UserSettings: Codable, Equatable {
    var quietHoursEnabled: Bool = false
    var quietHoursStart: String = "22:00"
    var quietHoursEnd: String = "08:00"
    var pushNotificationsEnabled: Bool = true
    var analyticsOptIn: Bool = false
    var preferredLanguage: String = "en"
    var translationMode: String = "AUTO"
    var showOriginalWithTranslation: Bool = false
}
