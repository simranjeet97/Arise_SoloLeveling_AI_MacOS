import Foundation
import GRDB

// MARK: - Quest Domain

enum QuestDomain: String, CaseIterable, Codable {
    case career    = "career"
    case physical  = "physical"
    case emotional = "emotional"
    case social    = "social"
    case learning  = "learning"

    var emoji: String {
        switch self {
        case .career:    return "⚔️"
        case .physical:  return "🏋️"
        case .emotional: return "🌒"
        case .social:    return "🤝"
        case .learning:  return "📚"
        }
    }

    var displayName: String {
        switch self {
        case .career:    return "Career"
        case .physical:  return "Physical"
        case .emotional: return "Emotional"
        case .social:    return "Social"
        case .learning:  return "Learning"
        }
    }
}

// MARK: - Quest Rank

enum QuestRank: String, CaseIterable, Codable, Comparable {
    case E = "E"
    case D = "D"
    case C = "C"
    case B = "B"
    case A = "A"
    case S = "S"

    /// Base XP multiplier.
    var xpMultiplier: Double {
        switch self {
        case .E: return 1.0
        case .D: return 1.5
        case .C: return 2.5
        case .B: return 4.0
        case .A: return 7.0
        case .S: return 12.0
        }
    }

    static func < (lhs: QuestRank, rhs: QuestRank) -> Bool {
        let order: [QuestRank] = [.E, .D, .C, .B, .A, .S]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Quest Status

enum QuestStatus: String, Codable {
    case active    = "active"
    case completed = "completed"
    case failed    = "failed"
    case pending   = "pending"
    case abandoned = "abandoned"   // kept for compat
}

// MARK: - Quest (GRDB Record)

/// The GRDB primary key is `rowID` (autoincrement); `id` is a UUID string used for
/// SwiftUI Identifiable so ForEach works even before a record is persisted.
struct Quest: Codable, FetchableRecord, PersistableRecord, Identifiable {

    // MARK: Table
    static let databaseTableName = "quests"

    // Identifiable.ID — stable UUID string (never nil, set at creation)
    var id: String          // UUID string, also stored in DB as unique TEXT

    // MARK: Spec-required properties
    var rowID: Int64?       // SQLite autoincrement PK (mirrors spec's `id: Int64?`)
    var title: String
    var description: String
    var rank: QuestRank
    var domain: QuestDomain
    var status: QuestStatus
    var xpReward: Int
    /// Stored as JSON text: {"strength": 2, "stamina": 1}
    var statRewards: [String: Int]
    var streakDay: Int
    var createdAt: Date
    var completedAt: Date?

    // MARK: - Derived

    var totalXPReward: Double { Double(xpReward) }

    // MARK: - Convenience Init

    static func new(
        title:       String,
        description: String,
        domain:      QuestDomain,
        rank:        QuestRank       = .E,
        xpReward:    Int             = 50,
        statRewards: [String: Int]   = [:]
    ) -> Quest {
        Quest(
            id:          UUID().uuidString,
            rowID:       nil,
            title:       title,
            description: description,
            rank:        rank,
            domain:      domain,
            status:      .active,
            xpReward:    xpReward,
            statRewards: statRewards,
            streakDay:   0,
            createdAt:   Date(),
            completedAt: nil
        )
    }

    // MARK: - Stat rewards

    func applyStatRewards(to stats: inout PlayerStats) {
        for (key, points) in statRewards {
            switch key.lowercased() {
            case "strength":     stats.strength     += points
            case "agility":      stats.agility      += points
            case "stamina":      stats.stamina       += points
            case "intelligence": stats.intelligence  += points
            case "sense":        stats.sense         += points
            default: break
            }
        }
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, rowID, title, description, rank, domain, status
        case xpReward, statRewards, streakDay, createdAt, completedAt
    }
}

// MARK: - Custom Codable (statRewards JSON string in SQLite)

extension Quest {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self,              forKey: .id)
        rowID       = try c.decodeIfPresent(Int64.self,      forKey: .rowID)
        title       = try c.decode(String.self,              forKey: .title)
        description = try c.decode(String.self,              forKey: .description)
        rank        = try c.decode(QuestRank.self,           forKey: .rank)
        domain      = try c.decode(QuestDomain.self,         forKey: .domain)
        status      = try c.decode(QuestStatus.self,         forKey: .status)
        xpReward    = try c.decode(Int.self,                 forKey: .xpReward)
        streakDay   = try c.decode(Int.self,                 forKey: .streakDay)
        createdAt   = try c.decode(Date.self,                forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self,       forKey: .completedAt)
        // statRewards: stored as JSON string in SQLite TEXT column
        if let jsonStr = try? c.decode(String.self, forKey: .statRewards),
           let data = jsonStr.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            statRewards = dict
        } else {
            statRewards = (try? c.decode([String: Int].self, forKey: .statRewards)) ?? [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                   forKey: .id)
        try c.encodeIfPresent(rowID,       forKey: .rowID)
        try c.encode(title,                forKey: .title)
        try c.encode(description,          forKey: .description)
        try c.encode(rank,                 forKey: .rank)
        try c.encode(domain,               forKey: .domain)
        try c.encode(status,               forKey: .status)
        try c.encode(xpReward,             forKey: .xpReward)
        try c.encode(streakDay,            forKey: .streakDay)
        try c.encode(createdAt,            forKey: .createdAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        // statRewards → JSON string
        if let data = try? JSONEncoder().encode(statRewards),
           let jsonStr = String(data: data, encoding: .utf8) {
            try c.encode(jsonStr, forKey: .statRewards)
        } else {
            try c.encode("{}", forKey: .statRewards)
        }
    }
}

// MARK: - Database Migration Helper

extension Quest {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("rowID")
            t.column("id",          .text).notNull().unique()   // UUID string
            t.column("title",       .text).notNull()
            t.column("description", .text).notNull().defaults(to: "")
            t.column("rank",        .text).notNull().defaults(to: "E")
            t.column("domain",      .text).notNull()
            t.column("status",      .text).notNull().defaults(to: "active")
            t.column("xpReward",    .integer).notNull().defaults(to: 50)
            t.column("statRewards", .text).notNull().defaults(to: "{}")
            t.column("streakDay",   .integer).notNull().defaults(to: 0)
            t.column("createdAt",   .datetime).notNull()
            t.column("completedAt", .datetime)
        }
    }
}
