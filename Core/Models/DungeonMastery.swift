import Foundation
import GRDB

// MARK: - DungeonMastery (GRDB Record)

/// Tracks a player's mastery progress for a given Learning Dungeon topic.
/// One row per unique `topic` string; updated whenever the player completes a quiz.
struct DungeonMastery: Codable, FetchableRecord, PersistableRecord, Identifiable {

    // MARK: Table
    static let databaseTableName = "dungeon_mastery"

    var id: String               // UUID string, stable across updates
    var topic: String            // e.g. "React Server Components"
    var masteryPercent: Double   // 0–100
    var totalXPEarned: Int
    var lastStudiedAt: Date

    // MARK: - Convenience

    static func fresh(topic: String) -> DungeonMastery {
        DungeonMastery(
            id:             UUID().uuidString,
            topic:          topic,
            masteryPercent: 0,
            totalXPEarned:  0,
            lastStudiedAt:  Date()
        )
    }

    /// Apply quiz results: each correct answer advances mastery by 33.3%.
    mutating func recordQuizResult(correctAnswers: Int, outOf total: Int, xpEarned: Int) {
        let gain = total > 0 ? (Double(correctAnswers) / Double(total)) * 100.0 : 0
        masteryPercent = min(100, masteryPercent + gain * 0.5)  // damped — you can't max out in one session
        totalXPEarned += xpEarned
        lastStudiedAt  = Date()
    }
}

// MARK: - Coding Keys

extension DungeonMastery {
    enum CodingKeys: String, CodingKey {
        case id, topic, masteryPercent, totalXPEarned, lastStudiedAt
    }
}

// MARK: - DB Migration Helper

extension DungeonMastery {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.column("id",             .text).primaryKey()
            t.column("topic",          .text).notNull().unique()
            t.column("masteryPercent", .double).notNull().defaults(to: 0)
            t.column("totalXPEarned",  .integer).notNull().defaults(to: 0)
            t.column("lastStudiedAt",  .datetime).notNull()
        }
    }
}
