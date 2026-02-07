import Foundation
import GRDB

// MARK: - Binder Service (Full Implementation)

extension BinderService {
    // MARK: - CRUD Operations
    
    func createItem(
        circleId: String,
        patientId: String? = nil,
        type: BinderItem.ItemType,
        title: String,
        content: Encodable
    ) async throws -> BinderItem {
        guard let userId = await getCurrentUserId() else {
            throw BinderError.notAuthenticated
        }
        
        let contentJson = try String(data: JSONEncoder().encode(content), encoding: .utf8) ?? "{}"
        
        let item = BinderItem(
            id: UUID().uuidString,
            circleId: circleId,
            patientId: patientId,
            type: type,
            title: title,
            contentJson: contentJson,
            isActive: true,
            createdBy: userId,
            updatedBy: userId,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try databaseManager.write { db in
            try item.save(db)
        }
        
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "INSERT",
            entityType: "binder_items",
            entityId: item.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(item), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
        
        return item
    }
    
    func updateItem(
        _ item: BinderItem,
        title: String? = nil,
        content: Encodable? = nil
    ) async throws -> BinderItem {
        guard let userId = await getCurrentUserId() else {
            throw BinderError.notAuthenticated
        }
        
        var updated = item
        updated.updatedBy = userId
        updated.updatedAt = Date()
        
        if let title = title {
            updated.title = title
        }
        
        if let content = content {
            updated.contentJson = try String(data: JSONEncoder().encode(content), encoding: .utf8) ?? item.contentJson
        }
        
        try databaseManager.write { db in
            try updated.update(db)
        }
        
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "binder_items",
            entityId: item.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(updated), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
        
        return updated
    }
    
    func archiveItem(_ item: BinderItem) async throws {
        var updated = item
        updated.isActive = false
        updated.updatedAt = Date()
        
        try databaseManager.write { db in
            try updated.update(db)
        }
        
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "binder_items",
            entityId: item.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(updated), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }
    
    // MARK: - Query Methods
    
    func fetchItems(
        circleId: String,
        type: BinderItem.ItemType? = nil,
        patientId: String? = nil,
        includeArchived: Bool = false
    ) async throws -> [BinderItem] {
        try databaseManager.read { db in
            var query = BinderItem.filter(Column("circleId") == circleId)
            
            if let type = type {
                query = query.filter(Column("type") == type.rawValue)
            }
            
            if let patientId = patientId {
                query = query.filter(Column("patientId") == patientId)
            }
            
            if !includeArchived {
                query = query.filter(Column("isActive") == true)
            }
            
            return try query.order(Column("title")).fetchAll(db)
        }
    }
    
    func fetchMedications(circleId: String, patientId: String? = nil) async throws -> [MedicationContent] {
        let items = try await fetchItems(circleId: circleId, type: .med, patientId: patientId)
        return items.compactMap { item in
            guard let data = item.contentJson.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(MedicationContent.self, from: data)
        }
    }
    
    func fetchContacts(circleId: String, patientId: String? = nil) async throws -> [ContactContent] {
        let items = try await fetchItems(circleId: circleId, type: .contact, patientId: patientId)
        return items.compactMap { item in
            guard let data = item.contentJson.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ContactContent.self, from: data)
        }
    }
    
    // MARK: - Medication Helpers
    
    func createMedication(
        circleId: String,
        patientId: String,
        medication: MedicationContent
    ) async throws -> BinderItem {
        try await createItem(
            circleId: circleId,
            patientId: patientId,
            type: .med,
            title: medication.name,
            content: medication
        )
    }
    
    func createContact(
        circleId: String,
        patientId: String,
        contact: ContactContent
    ) async throws -> BinderItem {
        try await createItem(
            circleId: circleId,
            patientId: patientId,
            type: .contact,
            title: contact.name,
            content: contact
        )
    }
    
    func createFacility(
        circleId: String,
        patientId: String,
        facility: FacilityContent
    ) async throws -> BinderItem {
        try await createItem(
            circleId: circleId,
            patientId: patientId,
            type: .facility,
            title: facility.name,
            content: facility
        )
    }
    
    // MARK: - Revision History
    
    func fetchRevisions(itemId: String) async throws -> [BinderItemRevision] {
        // Fetch from local database first
        return try databaseManager.read { db in
            try BinderItemRevision
                .filter(Column("binderItemId") == itemId)
                .order(Column("revision").desc)
                .fetchAll(db)
        }
    }
    
    // MARK: - Helpers
    
    private func getCurrentUserId() async -> String? {
        // TODO: Get from auth manager
        return nil
    }
}

// MARK: - Binder Item Revision

struct BinderItemRevision: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "binderItemRevisions"
    
    let id: String
    let binderItemId: String
    let revision: Int
    let contentJson: String
    let editedBy: String
    let editedAt: Date
    let changeNote: String?
}

// MARK: - Binder Error

enum BinderError: Error, LocalizedError {
    case notAuthenticated
    case notFound
    case permissionDenied
    case invalidContent
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in"
        case .notFound:
            return "Item not found"
        case .permissionDenied:
            return "You don't have permission to modify this item"
        case .invalidContent:
            return "Invalid content format"
        }
    }
}
