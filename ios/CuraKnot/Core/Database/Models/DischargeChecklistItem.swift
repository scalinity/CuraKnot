import Foundation
import GRDB

// MARK: - Discharge Checklist Item Model

/// Individual checklist item progress tracking
struct DischargeChecklistItem: Codable, Identifiable, Equatable {
    let id: String
    let dischargeRecordId: String
    let templateItemId: String
    var category: ChecklistCategory
    var itemText: String
    var sortOrder: Int

    // Status
    var isCompleted: Bool
    var completedAt: Date?
    var completedBy: String?

    // Task linkage
    var createTask: Bool
    var taskId: String?
    var assignedTo: String?
    var dueDate: Date?

    // Notes
    var notes: String?

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var hasTask: Bool {
        taskId != nil
    }

    var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return Date() > dueDate
    }

    var formattedDueDate: String? {
        guard let dueDate = dueDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: dueDate, relativeTo: Date())
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        dischargeRecordId: String,
        templateItemId: String,
        category: ChecklistCategory,
        itemText: String,
        sortOrder: Int,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        completedBy: String? = nil,
        createTask: Bool = false,
        taskId: String? = nil,
        assignedTo: String? = nil,
        dueDate: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dischargeRecordId = dischargeRecordId
        self.templateItemId = templateItemId
        self.category = category
        self.itemText = itemText
        self.sortOrder = sortOrder
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.completedBy = completedBy
        self.createTask = createTask
        self.taskId = taskId
        self.assignedTo = assignedTo
        self.dueDate = dueDate
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Factory Method

    /// Create checklist items from a template
    static func createItems(
        from template: DischargeTemplate,
        dischargeRecordId: String
    ) -> [DischargeChecklistItem] {
        template.items.map { templateItem in
            DischargeChecklistItem(
                dischargeRecordId: dischargeRecordId,
                templateItemId: templateItem.id,
                category: templateItem.category,
                itemText: templateItem.itemText,
                sortOrder: templateItem.sortOrder
            )
        }
    }
}

// MARK: - GRDB Conformance

extension DischargeChecklistItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "discharge_checklist_items"

    enum Columns: String, ColumnExpression {
        case id, dischargeRecordId, templateItemId, category, itemText, sortOrder
        case isCompleted, completedAt, completedBy
        case createTask, taskId, assignedTo, dueDate
        case notes, createdAt, updatedAt
    }
}

// MARK: - Checklist Item Group

/// A grouped view of checklist items by category
struct ChecklistItemGroup: Identifiable {
    let id: ChecklistCategory
    let category: ChecklistCategory
    let items: [DischargeChecklistItem]

    var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    var totalCount: Int {
        items.count
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var isComplete: Bool {
        completedCount == totalCount
    }
}

// MARK: - Extensions

extension Array where Element == DischargeChecklistItem {
    /// Group items by category
    func grouped() -> [ChecklistItemGroup] {
        let grouped = Dictionary(grouping: self) { $0.category }
        return ChecklistCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return ChecklistItemGroup(
                id: category,
                category: category,
                items: items.sorted { $0.sortOrder < $1.sortOrder }
            )
        }
    }

    /// Get items for a specific category
    func items(for category: ChecklistCategory) -> [DischargeChecklistItem] {
        filter { $0.category == category }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Overall completion percentage
    var completionPercentage: Double {
        guard !isEmpty else { return 0 }
        let completed = filter(\.isCompleted).count
        return Double(completed) / Double(count)
    }

    /// Count of items with tasks to create
    var tasksToCreate: Int {
        filter { $0.createTask && $0.taskId == nil }.count
    }
}
