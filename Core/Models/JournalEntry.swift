import Foundation
import GRDB

// MARK: - JournalEntry (GRDB Record)

struct JournalEntry: Codable, FetchableRecord, PersistableRecord, Identifiable {

    // MARK: Table
    static let databaseTableName = "journal_entries"

    // MARK: Properties
    var id: String          // UUID string
    var date: Date
    var rawTranscript: String        // Whisper output
    var claudeSummary: String        // Claude reflection
    var mood: MoodRating             // Legacy UI scale
    var emotion: String              // 'joy', 'stress', 'anxiety', 'sadness', 'neutral', 'anger'
    var intensity: Int               // 1-10 scale
    var linkedQuestIDs: [String]     // Quest UUIDs referenced in entry
    var createdAt: Date

    // MARK: - Mood Rating

    enum MoodRating: Int, Codable, CaseIterable {
        case shadow   = 1   // ████░░░░░░ Dark / struggling
        case dim      = 2
        case neutral  = 3
        case spark    = 4
        case blazing  = 5   // Full energy, unstoppable

        var label: String {
            switch self {
            case .shadow:  return "Shadow"
            case .dim:     return "Dim"
            case .neutral: return "Neutral"
            case .spark:   return "Spark"
            case .blazing: return "Blazing"
            }
        }

        var emoji: String {
            switch self {
            case .shadow:  return "🌑"
            case .dim:     return "🌘"
            case .neutral: return "🌗"
            case .spark:   return "🌔"
            case .blazing: return "🌕"
            }
        }
    }

    // MARK: - Convenience Init

    static func new(
        rawTranscript:  String,
        claudeSummary:  String  = "",
        mood:           MoodRating = .neutral,
        emotion:        String  = "neutral",
        intensity:      Int     = 5,
        linkedQuestIDs: [String] = []
    ) -> JournalEntry {
        let now = Date()
        return JournalEntry(
            id:             UUID().uuidString,
            date:           Calendar.current.startOfDay(for: now),
            rawTranscript:  rawTranscript,
            claudeSummary:  claudeSummary,
            mood:           mood,
            emotion:        emotion,
            intensity:      intensity,
            linkedQuestIDs: linkedQuestIDs,
            createdAt:      now
        )
    }

    // MARK: - GRDB Column Mapping

    // linkedQuestIDs is serialised as a comma-separated string in SQLite.
    enum CodingKeys: String, CodingKey {
        case id, date, rawTranscript, claudeSummary, mood, emotion, intensity, linkedQuestIDs, createdAt
    }

    // GRDB encodes/decodes arrays via JSON automatically when using Codable.
}

// MARK: - Database Migration Helper

extension JournalEntry {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.column("id",             .text).primaryKey()
            t.column("date",           .datetime).notNull()
            t.column("rawTranscript",  .text).notNull().defaults(to: "")
            t.column("claudeSummary",  .text).notNull().defaults(to: "")
            t.column("mood",           .integer).notNull().defaults(to: 3)
            t.column("emotion",        .text).notNull().defaults(to: "neutral")
            t.column("intensity",      .integer).notNull().defaults(to: 5)
            t.column("linkedQuestIDs", .text).notNull().defaults(to: "[]")
            t.column("createdAt",      .datetime).notNull()
        }
    }
}
