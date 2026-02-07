import Foundation
import GRDB

// MARK: - Local Care Cost Model (Read-Only)

/// Regional care cost data cached from the server.
/// Read-only -- data is fetched from the backend and cached locally.
struct LocalCareCost: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let state: String
    let zipCodePrefix: String?
    let regionName: String
    var homeCareHourlyMin: Decimal?
    var homeCareHourlyMax: Decimal?
    var homeCareHourlyMedian: Decimal?
    var assistedLivingMonthlyMin: Decimal?
    var assistedLivingMonthlyMax: Decimal?
    var assistedLivingMonthlyMedian: Decimal?
    var memoryCareMonthlyMin: Decimal?
    var memoryCareMonthlyMax: Decimal?
    var memoryCareMonthlyMedian: Decimal?
    var nursingHomePrivateDaily: Decimal?
    var nursingHomeSemiPrivateDaily: Decimal?
    var adultDayCareDaily: Decimal?
    var dataYear: Int
    var sourceAttribution: String?
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    /// Monthly estimate for full-time (40 hrs/week) home care at median rate
    var fullTimeHomeCareMonthly: Decimal? {
        guard let median = homeCareHourlyMedian else { return nil }
        return median * 40 * 4 // 40 hrs/week * ~4 weeks/month
    }

    /// Monthly estimate for 24/7 home care at median rate
    var twentyFourSevenHomeCareMonthly: Decimal? {
        guard let median = homeCareHourlyMedian else { return nil }
        return median * 168 * 4 // 168 hrs/week * ~4 weeks/month
    }

    /// Monthly nursing home cost (private room)
    var nursingHomePrivateMonthly: Decimal? {
        guard let daily = nursingHomePrivateDaily else { return nil }
        return daily * 30
    }

    /// Monthly nursing home cost (semi-private room)
    var nursingHomeSemiPrivateMonthly: Decimal? {
        guard let daily = nursingHomeSemiPrivateDaily else { return nil }
        return daily * 30
    }
}

// MARK: - GRDB Conformance (Read-Only)

extension LocalCareCost: FetchableRecord {
    static let databaseTableName = "localCareCosts"
}
