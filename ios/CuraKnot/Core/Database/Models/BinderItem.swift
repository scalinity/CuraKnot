import Foundation
import GRDB

// MARK: - Binder Item Model

struct BinderItem: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    var patientId: String?
    let type: ItemType
    var title: String
    var contentJson: String
    var isActive: Bool
    let createdBy: String
    var updatedBy: String
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Item Type
    
    enum ItemType: String, Codable, CaseIterable {
        case med = "MED"
        case contact = "CONTACT"
        case facility = "FACILITY"
        case insurance = "INSURANCE"
        case doc = "DOC"
        case note = "NOTE"
        
        var displayName: String {
            switch self {
            case .med: return "Medication"
            case .contact: return "Contact"
            case .facility: return "Facility"
            case .insurance: return "Insurance"
            case .doc: return "Document"
            case .note: return "Note"
            }
        }
        
        var pluralName: String {
            switch self {
            case .med: return "Medications"
            case .contact: return "Contacts"
            case .facility: return "Facilities"
            case .insurance: return "Insurance"
            case .doc: return "Documents"
            case .note: return "Notes"
            }
        }
        
        var icon: String {
            switch self {
            case .med: return "pills.fill"
            case .contact: return "person.crop.circle.fill"
            case .facility: return "building.2.fill"
            case .insurance: return "creditcard.fill"
            case .doc: return "doc.fill"
            case .note: return "note.text"
            }
        }
    }
}

// MARK: - GRDB Conformance

extension BinderItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "binderItems"
}

// MARK: - Content Types

struct MedicationContent: Codable, Equatable {
    var name: String
    var dose: String?
    var schedule: String?
    var purpose: String?
    var prescriber: String?
    var startDate: Date?
    var stopDate: Date?
    var pharmacy: String?
    var notes: String?
}

struct ContactContent: Codable, Equatable {
    var name: String
    var role: ContactRole
    var phone: String?
    var email: String?
    var organization: String?
    var address: String?
    var notes: String?
    
    enum ContactRole: String, Codable, CaseIterable {
        case doctor
        case nurse
        case socialWorker = "social_worker"
        case family
        case other
        
        var displayName: String {
            switch self {
            case .doctor: return "Doctor"
            case .nurse: return "Nurse"
            case .socialWorker: return "Social Worker"
            case .family: return "Family"
            case .other: return "Other"
            }
        }
    }
}

struct FacilityContent: Codable, Equatable {
    var name: String
    var type: FacilityType
    var address: String
    var phone: String?
    var unitRoom: String?
    var visitingHours: String?
    var notes: String?
    
    enum FacilityType: String, Codable, CaseIterable {
        case hospital
        case nursingHome = "nursing_home"
        case rehab
        case other
        
        var displayName: String {
            switch self {
            case .hospital: return "Hospital"
            case .nursingHome: return "Nursing Home"
            case .rehab: return "Rehab Center"
            case .other: return "Other"
            }
        }
    }
}

struct InsuranceContent: Codable, Equatable {
    var provider: String
    var planName: String
    var memberId: String
    var groupNumber: String?
    var phone: String?
    var notes: String?
}

struct DocumentContent: Codable, Equatable {
    var description: String?
    var documentType: DocumentType
    var date: Date?
    var attachmentId: String
    
    enum DocumentType: String, Codable, CaseIterable {
        case medicalRecord = "medical_record"
        case insurance
        case legal
        case other
        
        var displayName: String {
            switch self {
            case .medicalRecord: return "Medical Record"
            case .insurance: return "Insurance"
            case .legal: return "Legal"
            case .other: return "Other"
            }
        }
    }
}

struct NoteContent: Codable, Equatable {
    var content: String
}
