import Foundation
import GRDB

// MARK: - Stat Keys

enum StatKey: String, CaseIterable, Codable {
    case strength     = "STR"
    case agility      = "AGI"
    case stamina      = "STA"
    case intelligence = "INT"
    case sense        = "SENSE"

    var displayName: String {
        switch self {
        case .strength:      return "Strength"
        case .agility:       return "Agility"
        case .stamina:       return "Stamina"
        case .intelligence:  return "Intelligence"
        case .sense:         return "Sense"
        }
    }

    var domain: QuestDomain {
        switch self {
        case .strength, .stamina:    return .physical
        case .agility:               return .physical
        case .intelligence, .sense:  return .career
        }
    }
}

// MARK: - PlayerStats (GRDB Record)

struct PlayerStats: Codable, FetchableRecord, PersistableRecord {

    // MARK: Table
    static let databaseTableName = "player_stats"

    enum Columns: String, ColumnExpression {
        case id, level, xp, xpToNextLevel
        case strength, agility, stamina, intelligence, sense
        case title, updatedAt
    }

    // MARK: Properties — match spec exactly
    var id: Int64?
    var level: Int          // 1-100, mirrors Solo Leveling's 100-level system
    var xp: Int             // current XP toward next level
    var xpToNextLevel: Int  // increases each level
    var strength: Int       // Career / Technical skill
    var agility: Int        // Adaptability / learning speed
    var stamina: Int        // Physical health consistency
    var intelligence: Int   // Deep learning / knowledge mastery
    var sense: Int          // Emotional IQ / peace of mind
    var title: String       // e.g. "Weakest Hunter" → "Shadow Monarch"
    var updatedAt: Date

    // MARK: Derived – keeps older UI code working
    var str:   Double { Double(strength) }
    var agi:   Double { Double(agility) }
    var sta:   Double { Double(stamina) }

    // MARK: - Convenience

    static func fresh() -> PlayerStats {
        let lvl = 1
        return PlayerStats(
            id:           nil,
            level:        lvl,
            xp:           0,
            xpToNextLevel: xpNeededForLevel(lvl),
            strength:     10,
            agility:      10,
            stamina:      10,
            intelligence: 10,
            sense:        10,
            title:        titleForLevel(lvl),
            updatedAt:    Date()
        )
    }

    // MARK: - Level / Title Logic

    /// XP required to level up *from* a given level.
    static func xpNeededForLevel(_ lvl: Int) -> Int {
        Int(Double(lvl) * 100 * pow(1.15, Double(lvl - 1)))
    }

    /// Title string based on level milestones (Solo Leveling style).
    static func titleForLevel(_ lvl: Int) -> String {
        switch lvl {
        case 1..<10:  return "Weakest Hunter"
        case 10..<20: return "E-Rank Hunter"
        case 20..<40: return "D-Rank Hunter"
        case 40..<60: return "C-Rank Hunter"
        case 60..<80: return "B-Rank Hunter"
        case 80..<90: return "A-Rank Hunter"
        case 90..<100: return "S-Rank Hunter"
        default:       return "Shadow Monarch"
        }
    }

    /// Fractional progress [0, 1] toward the next level (for progress bars).
    var levelProgress: Double {
        guard xpToNextLevel > 0 else { return 1 }
        return Double(xp) / Double(xpToNextLevel)
    }

    /// Award XP, auto-level-up if the bar fills, update title.
    /// Returns true if a level-up occurred.
    @discardableResult
    mutating func awardXP(_ amount: Int) -> Bool {
        var remaining = amount
        var didLevelUp = false
        while remaining > 0 && level < 100 {
            let space = xpToNextLevel - xp
            if remaining >= space {
                remaining -= space
                level += 1
                xp = 0
                xpToNextLevel = PlayerStats.xpNeededForLevel(level)
                title = PlayerStats.titleForLevel(level)
                didLevelUp = true
            } else {
                xp += remaining
                remaining = 0
            }
        }
        updatedAt = Date()
        return didLevelUp
    }

    // MARK: - Subscript (stat access by key – used in UI & QuestEngine)

    subscript(stat: StatKey) -> Double {
        get {
            switch stat {
            case .strength:      return Double(strength)
            case .agility:       return Double(agility)
            case .stamina:       return Double(stamina)
            case .intelligence:  return Double(intelligence)
            case .sense:         return Double(sense)
            }
        }
        set {
            let v = max(0, Int(newValue))
            switch stat {
            case .strength:      strength     = v
            case .agility:       agility      = v
            case .stamina:       stamina      = v
            case .intelligence:  intelligence = v
            case .sense:         sense        = v
            }
            updatedAt = Date()
        }
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, level, xp, xpToNextLevel
        case strength, agility, stamina, intelligence, sense
        case title, updatedAt
    }
}

// MARK: - Database Migration Helper

extension PlayerStats {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("level",         .integer).notNull().defaults(to: 1)
            t.column("xp",            .integer).notNull().defaults(to: 0)
            t.column("xpToNextLevel", .integer).notNull().defaults(to: 100)
            t.column("strength",      .integer).notNull().defaults(to: 10)
            t.column("agility",       .integer).notNull().defaults(to: 10)
            t.column("stamina",       .integer).notNull().defaults(to: 10)
            t.column("intelligence",  .integer).notNull().defaults(to: 10)
            t.column("sense",         .integer).notNull().defaults(to: 10)
            t.column("title",         .text).notNull().defaults(to: "Awaiting Awakening")
            t.column("updatedAt",     .datetime).notNull()
        }
    }
}
