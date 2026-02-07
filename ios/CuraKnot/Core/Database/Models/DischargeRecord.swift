import Foundation
import GRDB

// MARK: - Discharge Record Model

/// Represents a hospital discharge planning wizard instance
struct DischargeRecord: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String

    // Discharge info
    var facilityName: String
    var dischargeDate: Date
    var admissionDate: Date?
    var reasonForStay: String
    var dischargeType: DischargeType
    var templateId: String?

    // Status tracking
    var status: Status
    var currentStep: Int

    // Completion tracking
    var completedAt: Date?
    var completedBy: String?

    // Generated outputs
    var generatedTasks: [String]
    var generatedHandoffId: String?
    var generatedShifts: [String]
    var generatedBinderItems: [String]

    // Wizard state (JSON storage)
    var checklistStateJson: String?
    var shiftAssignmentsJson: String?
    var medicationChangesJson: String?

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Discharge Type

    enum DischargeType: String, Codable, CaseIterable {
        case general = "GENERAL"
        case surgery = "SURGERY"
        case stroke = "STROKE"
        case cardiac = "CARDIAC"
        case fall = "FALL"
        case psychiatric = "PSYCHIATRIC"
        case other = "OTHER"

        var displayName: String {
            switch self {
            case .general: return "General Discharge"
            case .surgery: return "Post-Surgery"
            case .stroke: return "Stroke Recovery"
            case .cardiac: return "Cardiac"
            case .fall: return "Fall/Injury"
            case .psychiatric: return "Psychiatric"
            case .other: return "Other"
            }
        }

        var icon: String {
            switch self {
            case .general: return "cross.case.fill"
            case .surgery: return "bandage.fill"
            case .stroke: return "brain.head.profile"
            case .cardiac: return "heart.fill"
            case .fall: return "figure.fall"
            case .psychiatric: return "brain"
            case .other: return "doc.text.fill"
            }
        }
    }

    // MARK: - Status

    enum Status: String, Codable {
        case inProgress = "IN_PROGRESS"
        case completed = "COMPLETED"
        case cancelled = "CANCELLED"

        var displayName: String {
            switch self {
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }

        var isActive: Bool {
            self == .inProgress
        }
    }

    // MARK: - Wizard Steps

    enum WizardStep: Int, CaseIterable {
        case setup = 1
        case medications = 2
        case equipment = 3
        case homePrep = 4
        case careSchedule = 5
        case followUps = 6
        case review = 7

        var title: String {
            switch self {
            case .setup: return "Setup"
            case .medications: return "Medications"
            case .equipment: return "Equipment"
            case .homePrep: return "Home Prep"
            case .careSchedule: return "Care Schedule"
            case .followUps: return "Follow-ups"
            case .review: return "Review"
            }
        }

        var icon: String {
            switch self {
            case .setup: return "doc.text"
            case .medications: return "pills.fill"
            case .equipment: return "cross.vial.fill"
            case .homePrep: return "house.fill"
            case .careSchedule: return "calendar"
            case .followUps: return "person.badge.clock"
            case .review: return "checkmark.circle.fill"
            }
        }

        static var totalSteps: Int {
            allCases.count
        }
    }

    // MARK: - Computed Properties

    var isComplete: Bool {
        status == .completed
    }

    var progress: Double {
        Double(currentStep) / Double(WizardStep.totalSteps)
    }

    var currentWizardStep: WizardStep? {
        WizardStep(rawValue: currentStep)
    }

    var checklistState: ChecklistState? {
        get {
            guard let json = checklistStateJson,
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(ChecklistState.self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                checklistStateJson = json
            } else {
                checklistStateJson = nil
            }
        }
    }

    var shiftAssignments: [Int: String]? {
        get {
            guard let json = shiftAssignmentsJson,
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode([Int: String].self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                shiftAssignmentsJson = json
            } else {
                shiftAssignmentsJson = nil
            }
        }
    }

    var medicationChanges: [DischargeMedicationChange]? {
        get {
            guard let json = medicationChangesJson,
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode([DischargeMedicationChange].self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                medicationChangesJson = json
            } else {
                medicationChangesJson = nil
            }
        }
    }

    var daysUntilDischarge: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: dischargeDate).day ?? 0
    }

    var formattedDischargeDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: dischargeDate)
    }
}

// MARK: - GRDB Conformance

extension DischargeRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "discharge_records"

    enum Columns: String, ColumnExpression {
        case id, circleId, patientId, createdBy
        case facilityName, dischargeDate, admissionDate, reasonForStay, dischargeType, templateId
        case status, currentStep, completedAt, completedBy
        case generatedTasks, generatedHandoffId, generatedShifts, generatedBinderItems
        case checklistStateJson, shiftAssignmentsJson, medicationChangesJson
        case createdAt, updatedAt
    }
}

// MARK: - Checklist State

struct ChecklistState: Codable, Equatable {
    var completedItems: Set<String>
    var itemNotes: [String: String]
    var itemAssignees: [String: String]
    var itemDueDates: [String: Date]

    init(
        completedItems: Set<String> = [],
        itemNotes: [String: String] = [:],
        itemAssignees: [String: String] = [:],
        itemDueDates: [String: Date] = [:]
    ) {
        self.completedItems = completedItems
        self.itemNotes = itemNotes
        self.itemAssignees = itemAssignees
        self.itemDueDates = itemDueDates
    }

    var completedCount: Int {
        completedItems.count
    }

    func isCompleted(_ itemId: String) -> Bool {
        completedItems.contains(itemId)
    }
}

// MARK: - Discharge Medication Change

struct DischargeMedicationChange: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var changeType: ChangeType
    var dosage: String?
    var frequency: String?
    var instructions: String?
    var source: Source

    enum ChangeType: String, Codable, CaseIterable {
        case new = "NEW"
        case stopped = "STOPPED"
        case doseChanged = "DOSE_CHANGED"
        case scheduleChanged = "SCHEDULE_CHANGED"

        var displayName: String {
            switch self {
            case .new: return "New"
            case .stopped: return "Stopped"
            case .doseChanged: return "Dose Changed"
            case .scheduleChanged: return "Schedule Changed"
            }
        }

        var icon: String {
            switch self {
            case .new: return "plus.circle.fill"
            case .stopped: return "minus.circle.fill"
            case .doseChanged: return "arrow.up.arrow.down.circle.fill"
            case .scheduleChanged: return "clock.arrow.circlepath"
            }
        }

        var color: String {
            switch self {
            case .new: return "green"
            case .stopped: return "red"
            case .doseChanged: return "orange"
            case .scheduleChanged: return "blue"
            }
        }
    }

    enum Source: String, Codable {
        case manual = "MANUAL"
        case scanned = "SCANNED"
        case imported = "IMPORTED"
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        changeType: ChangeType,
        dosage: String? = nil,
        frequency: String? = nil,
        instructions: String? = nil,
        source: Source = .manual
    ) {
        self.id = id
        self.name = name
        self.changeType = changeType
        self.dosage = dosage
        self.frequency = frequency
        self.instructions = instructions
        self.source = source
    }
}

// MARK: - Wizard Output Summary

struct DischargeOutputSummary: Codable, Equatable {
    var tasksToCreate: Int
    var medicationTasks: Int
    var equipmentTasks: Int
    var appointmentTasks: Int
    var careScheduleTasks: Int
    var binderUpdates: Int
    var newMedications: Int
    var newContacts: Int
    var shiftsScheduled: Int
    var handoffCreated: Bool

    var totalOutputs: Int {
        tasksToCreate + binderUpdates + shiftsScheduled + (handoffCreated ? 1 : 0)
    }
}
