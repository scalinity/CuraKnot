import Foundation
import GRDB

// MARK: - Discharge Template Model

/// System-provided or custom templates for discharge checklists
struct DischargeTemplate: Codable, Identifiable, Equatable {
    let id: String
    var templateName: String
    var dischargeType: String
    var description: String?
    var itemsJson: String
    var isSystem: Bool
    var isActive: Bool
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var items: [ChecklistTemplateItem] {
        get {
            guard let data = itemsJson.data(using: .utf8) else {
                return []
            }
            return (try? JSONDecoder().decode([ChecklistTemplateItem].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                itemsJson = json
            }
        }
    }

    var itemsByCategory: [ChecklistCategory: [ChecklistTemplateItem]] {
        Dictionary(grouping: items, by: { $0.category })
    }

    var totalItems: Int {
        items.count
    }

    var requiredItems: [ChecklistTemplateItem] {
        items.filter { $0.isRequired }
    }

    var requiredItemCount: Int {
        requiredItems.count
    }

    func items(for category: ChecklistCategory) -> [ChecklistTemplateItem] {
        items.filter { $0.category == category }.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - GRDB Conformance

extension DischargeTemplate: FetchableRecord, PersistableRecord {
    static let databaseTableName = "discharge_templates"

    enum Columns: String, ColumnExpression {
        case id, templateName, dischargeType, description
        case itemsJson = "items"
        case isSystem, isActive, sortOrder
        case createdAt, updatedAt
    }
}

// MARK: - Checklist Category

enum ChecklistCategory: String, Codable, CaseIterable {
    case beforeLeaving = "BEFORE_LEAVING"
    case medications = "MEDICATIONS"
    case equipment = "EQUIPMENT"
    case homePrep = "HOME_PREP"
    case firstWeek = "FIRST_WEEK"

    var displayName: String {
        switch self {
        case .beforeLeaving: return "Before Leaving Hospital"
        case .medications: return "Medications"
        case .equipment: return "Equipment & Supplies"
        case .homePrep: return "Home Preparation"
        case .firstWeek: return "First Week at Home"
        }
    }

    var icon: String {
        switch self {
        case .beforeLeaving: return "building.2.fill"
        case .medications: return "pills.fill"
        case .equipment: return "cross.vial.fill"
        case .homePrep: return "house.fill"
        case .firstWeek: return "calendar.badge.clock"
        }
    }

    var color: String {
        switch self {
        case .beforeLeaving: return "blue"
        case .medications: return "green"
        case .equipment: return "purple"
        case .homePrep: return "orange"
        case .firstWeek: return "red"
        }
    }

    /// Maps to wizard step
    var wizardStep: DischargeRecord.WizardStep? {
        switch self {
        case .beforeLeaving: return .setup
        case .medications: return .medications
        case .equipment: return .equipment
        case .homePrep: return .homePrep
        case .firstWeek: return .review  // First week items shown in review
        }
    }
}

// MARK: - Checklist Template Item

struct ChecklistTemplateItem: Codable, Identifiable, Equatable {
    var id: String { "\(category.rawValue)_\(sortOrder)" }
    var category: ChecklistCategory
    var itemText: String
    var sortOrder: Int
    var isRequired: Bool
    var taskTemplate: TaskTemplate?
    var resourceLinks: [ResourceLink]?

    enum CodingKeys: String, CodingKey {
        case category
        case itemText = "item_text"
        case sortOrder = "sort_order"
        case isRequired = "is_required"
        case taskTemplate = "task_template"
        case resourceLinks = "resource_links"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let categoryString = try container.decode(String.self, forKey: .category)
        self.category = ChecklistCategory(rawValue: categoryString) ?? .beforeLeaving
        self.itemText = try container.decode(String.self, forKey: .itemText)
        self.sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        self.isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        self.taskTemplate = try container.decodeIfPresent(TaskTemplate.self, forKey: .taskTemplate)
        self.resourceLinks = try container.decodeIfPresent([ResourceLink].self, forKey: .resourceLinks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(itemText, forKey: .itemText)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isRequired, forKey: .isRequired)
        try container.encodeIfPresent(taskTemplate, forKey: .taskTemplate)
        try container.encodeIfPresent(resourceLinks, forKey: .resourceLinks)
    }
}

// MARK: - Task Template

struct TaskTemplate: Codable, Equatable {
    var titlePrefix: String?
    var priority: String?
    var dueDateOffset: Int?  // Days from discharge date

    enum CodingKeys: String, CodingKey {
        case titlePrefix = "title_prefix"
        case priority
        case dueDateOffset = "due_date_offset"
    }
}

// MARK: - Resource Link

struct ResourceLink: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var url: String
    var type: LinkType

    enum LinkType: String, Codable {
        case article = "ARTICLE"
        case video = "VIDEO"
        case product = "PRODUCT"
        case service = "SERVICE"
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        type: LinkType = .article
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.type = type
    }
}

// MARK: - Template Loading

extension DischargeTemplate {
    /// Get the appropriate template for a discharge type
    static func template(for dischargeType: DischargeRecord.DischargeType) -> String {
        switch dischargeType {
        case .general, .other: return "GENERAL"
        case .surgery: return "SURGERY"
        case .stroke: return "STROKE"
        case .cardiac: return "CARDIAC"
        case .fall: return "GENERAL"  // Use general for fall
        case .psychiatric: return "GENERAL"  // Use general for psychiatric
        }
    }
}
