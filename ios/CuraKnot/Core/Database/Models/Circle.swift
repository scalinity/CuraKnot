import Foundation
import GRDB

// MARK: - Circle Model

struct Circle: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var icon: String?
    let ownerUserId: String
    var plan: Plan
    var settingsJson: String?
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    
    // MARK: - Plan
    
    enum Plan: String, Codable, CaseIterable {
        case free = "FREE"
        case plus = "PLUS"
        case family = "FAMILY"
    }
    
    // MARK: - Computed Properties
    
    var isDeleted: Bool {
        deletedAt != nil
    }
    
    var displayIcon: String {
        icon ?? "👨‍👩‍👧‍👦"
    }
}

// MARK: - GRDB Conformance

extension Circle: FetchableRecord, PersistableRecord {
    static let databaseTableName = "circles"
}

// MARK: - Circle Member

struct CircleMember: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let userId: String
    var role: Role
    var status: Status
    var invitedBy: String?
    var invitedAt: Date?
    var joinedAt: Date?
    var lastActiveAt: Date?
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Role
    
    enum Role: String, Codable, CaseIterable {
        case owner = "OWNER"
        case admin = "ADMIN"
        case contributor = "CONTRIBUTOR"
        case viewer = "VIEWER"
        
        var displayName: String {
            switch self {
            case .owner: return "Owner"
            case .admin: return "Admin"
            case .contributor: return "Contributor"
            case .viewer: return "Viewer"
            }
        }
        
        var canCreateHandoffs: Bool {
            self != .viewer
        }
        
        var canCreateTasks: Bool {
            self != .viewer
        }
        
        var canInviteMembers: Bool {
            self == .owner || self == .admin
        }
        
        var canManageRoles: Bool {
            self == .owner || self == .admin
        }
        
        var canDeleteCircle: Bool {
            self == .owner
        }
    }
    
    // MARK: - Status
    
    enum Status: String, Codable {
        case invited = "INVITED"
        case active = "ACTIVE"
        case removed = "REMOVED"
    }
}

// MARK: - GRDB Conformance

extension CircleMember: FetchableRecord, PersistableRecord {
    static let databaseTableName = "circleMembers"
}
