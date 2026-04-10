import Foundation
import GRDB

// MARK: - QuestStreak (GRDB Record)

/// Tracks the current streak (consecutive daily completions) per quest domain.
/// One row per domain; updated atomically when a quest is completed.
struct QuestStreak: Codable, FetchableRecord, PersistableRecord {

    // MARK: Table
    static let databaseTableName = "quest_streaks"

    var domain:        String   // QuestDomain.rawValue ("career", "physical", "emotional")
    var currentStreak: Int      // Current consecutive-day count
    var longestStreak: Int      // Historical peak
    var lastCompletedDate: Date // Most recent day a quest in this domain was completed
    var totalCompletions: Int   // All-time completed count for this domain

    // MARK: - Milestone Bonus XP

    /// Extra XP awarded at streak milestone thresholds.
    static func milestoneBonus(for streak: Int) -> Int {
        switch streak {
        case 7:   return 5
        case 30:  return 25  // stat point awarded separately
        case 100: return 100 // title upgrade event fired separately
        default:  return 0
        }
    }

    /// True when the streak milestone grants a stat point (30-day mark).
    var grantsStatPoint: Bool { currentStreak == 30 || (currentStreak > 30 && currentStreak % 30 == 0) }

    /// True when the streak milestone upgrades the player's title (100-day mark).
    var grantsTitleUpgrade: Bool { currentStreak == 100 || (currentStreak > 100 && currentStreak % 100 == 0) }
}

// MARK: - Migration Helper

extension QuestStreak {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.column("domain",            .text).primaryKey()
            t.column("currentStreak",     .integer).notNull().defaults(to: 0)
            t.column("longestStreak",     .integer).notNull().defaults(to: 0)
            t.column("lastCompletedDate", .datetime).notNull()
            t.column("totalCompletions",  .integer).notNull().defaults(to: 0)
        }
    }
}
