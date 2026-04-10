import Foundation
import GRDB

// MARK: - DatabaseService

/// Manages the SQLite database via GRDB.
/// All public API is thread-safe (dispatched on the GRDB writer/reader queue).
final class DatabaseService {

    // MARK: Singleton
    static let shared = DatabaseService()

    // MARK: - Properties

    private var dbQueue: DatabaseQueue?

    /// File URL for the SQLite database.
    private var dbURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appendingPathComponent("ARISE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("arise.db")
    }

    // MARK: - Init

    private init() {}

    // MARK: - Setup / Migrations

    /// Opens (or creates) the database, runs migrations, and seeds initial data.
    func setupDatabase() throws {
        let queue = try DatabaseQueue(path: dbURL.path)
        self.dbQueue = queue

        var migrator = DatabaseMigrator()

        // ── v1: baseline schema ───────────────────────────────────────────────
        migrator.registerMigration("v1_initial") { db in
            try PlayerStats.createTable(in: db)
            try Quest.createTable(in: db)
            try JournalEntry.createTable(in: db)
        }

        // ── v2: Learning Dungeons mastery table ───────────────────────────────
        migrator.registerMigration("v2_dungeon_mastery") { db in
            try DungeonMastery.createTable(in: db)
        }

        // ── v3: Quest streak tracking ────────────────────────────────────
        migrator.registerMigration("v3_quest_streaks") { db in
            try QuestStreak.createTable(in: db)
        }

        // ── v4: Journal emotions ─────────────────────────────────────────
        migrator.registerMigration("v4_journal_emotion") { db in
            let columns = try db.columns(in: JournalEntry.databaseTableName)
            if !columns.contains(where: { $0.name == "emotion" }) {
                try db.alter(table: JournalEntry.databaseTableName) { t in
                    t.add(column: "emotion", .text).notNull().defaults(to: "neutral")
                    t.add(column: "intensity", .integer).notNull().defaults(to: 5)
                }
            }
        }

        try migrator.migrate(queue)

        // ── Seed initial data (idempotent) ────────────────────────────────────
        try queue.write { db in
            if try PlayerStats.fetchCount(db) == 0 {
                let fresh = PlayerStats.fresh()
                try fresh.insert(db)
                print("[DatabaseService] Seeded initial PlayerStats — \(fresh.title)")
            }

            if try Quest.fetchCount(db) == 0 {
                let starterQuests = DatabaseService.starterQuests()
                for quest in starterQuests {
                    try quest.insert(db)
                }
                print("[DatabaseService] Seeded \(starterQuests.count) starter quests")
            }
        }

        print("[DatabaseService] Database ready at: \(dbURL.path)")
    }

    /// Wipes all tables and user profiles, then re-runs setup to create a fresh user state.
    func resetSystem() throws {
        _ = try dbQueue?.write { db in
            try PlayerStats.deleteAll(db)
            try Quest.deleteAll(db)
            try JournalEntry.deleteAll(db)
            try DungeonMastery.deleteAll(db)
            try QuestStreak.deleteAll(db)
        }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "playerName")
        defaults.removeObject(forKey: "playerGoal")
        defaults.removeObject(forKey: "playerExperience")
        defaults.removeObject(forKey: "hasCompletedOnboarding")

        print("[DatabaseService] System wiped. Re-seeding database.")
        try setupDatabase()
    }

    // MARK: - Starter Quests Seed

    private static func starterQuests() -> [Quest] {
        [
            Quest.new(
                title:       "Ship One Feature",
                description: "Build and merge a meaningful feature or fix at work. Document your work.",
                domain:      .career,
                rank:        .E,
                xpReward:    75,
                statRewards: ["strength": 2, "intelligence": 1]
            ),
            Quest.new(
                title:       "30-Minute Movement",
                description: "Complete 30 minutes of intentional physical activity — gym, run, or yoga.",
                domain:      .physical,
                rank:        .E,
                xpReward:    60,
                statRewards: ["stamina": 2, "agility": 1]
            ),
            Quest.new(
                title:       "Reflect & Release",
                description: "Spend 10 minutes journaling your current feelings and one thing you are grateful for.",
                domain:      .emotional,
                rank:        .E,
                xpReward:    50,
                statRewards: ["sense": 2]
            )
        ]
    }

    // MARK: - Player Stats

    /// Fetch the single PlayerStats record (spec: `fetchStats()`).
    func fetchStats() throws -> PlayerStats? {
        try dbQueue?.read { db in
            try PlayerStats.fetchOne(db)
        }
    }

    // MARK: Alias kept for QuestEngine compatibility
    func fetchPlayerStats() throws -> PlayerStats? { try fetchStats() }

    /// Persist an updated PlayerStats record (spec: `updateStats()`).
    func updateStats(_ stats: PlayerStats) throws {
        try dbQueue?.write { db in
            try stats.save(db)
        }
    }

    // MARK: Alias kept for QuestEngine compatibility
    func savePlayerStats(_ stats: PlayerStats) throws { try updateStats(stats) }

    // MARK: - XP

    /// Add XP to the player, auto-level-up & update title.
    /// Returns `true` if a level-up occurred (spec: `addXP(amount:)`).
    @discardableResult
    func addXP(amount: Int) throws -> Bool {
        var didLevelUp = false
        try dbQueue?.write { db in
            guard var stats = try PlayerStats.fetchOne(db) else { return }
            didLevelUp = stats.awardXP(amount)
            try stats.update(db)
        }
        return didLevelUp
    }

    // MARK: - Quests

    /// Fetch all quests whose status is `.active` (spec: `fetchActiveQuests()`).
    func fetchActiveQuests() throws -> [Quest] {
        try dbQueue?.read { db in
            try Quest
                .filter(Column("status") == QuestStatus.active.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        } ?? []
    }

    func fetchAllQuests() throws -> [Quest] {
        try dbQueue?.read { db in
            try Quest.order(Column("createdAt").desc).fetchAll(db)
        } ?? []
    }

    /// Mark a quest as completed (spec: `completeQuest(id:)`).
    /// Also applies stat rewards and XP to the player in one transaction.
    /// Returns the updated PlayerStats so the caller can reflect changes in UI.
    @discardableResult
    func completeQuest(id: String) throws -> (quest: Quest, stats: PlayerStats, didLevelUp: Bool) {
        var resultQuest: Quest!
        var resultStats: PlayerStats!
        var leveledUp = false

        try dbQueue?.write { db in
            guard var quest = try Quest
                .filter(Column("id") == id)
                .fetchOne(db) else {
                throw DatabaseError.questNotFound
            }
            quest.status      = .completed
            quest.completedAt = Date()
            try quest.update(db)
            resultQuest = quest

            guard var stats = try PlayerStats.fetchOne(db) else { return }
            // Apply stat rewards
            quest.applyStatRewards(to: &stats)
            // Apply XP
            leveledUp = stats.awardXP(quest.xpReward)
            try stats.update(db)
            resultStats = stats
        }

        return (resultQuest, resultStats, leveledUp)
    }

    /// Fetch quests completed within the last N calendar days (for daily-quest context).
    func fetchCompletedQuests(inLastDays days: Int) throws -> [Quest] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return try dbQueue?.read { db in
            try Quest
                .filter(Column("status") == QuestStatus.completed.rawValue)
                .filter(Column("completedAt") >= cutoff)
                .order(Column("completedAt").desc)
                .fetchAll(db)
        } ?? []
    }

    func saveQuest(_ quest: Quest) throws {
        try dbQueue?.write { db in
            try quest.save(db)
        }
    }

    func deleteQuest(id: String) throws {
        _ = try dbQueue?.write { db in
            try Quest
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }

    // MARK: - Quest Streaks

    /// Fetch the streak record for a domain (nil if first completion).
    func fetchStreak(domain: QuestDomain) throws -> QuestStreak? {
        try dbQueue?.read { db in
            try QuestStreak.fetchOne(db, key: domain.rawValue)
        }
    }

    /// Fetch all streak records ordered by current streak descending.
    func fetchAllStreaks() throws -> [QuestStreak] {
        try dbQueue?.read { db in
            try QuestStreak
                .order(Column("currentStreak").desc)
                .fetchAll(db)
        } ?? []
    }

    /// Update the streak for a domain when a quest is completed.
    /// - Returns: the updated QuestStreak and a MilestoneResult if applicable.
    @discardableResult
    func updateStreakOnCompletion(domain: QuestDomain) throws -> (streak: QuestStreak, bonusXP: Int, grantsStatPoint: Bool, grantsTitleUpgrade: Bool) {
        var result: QuestStreak!
        var bonusXP = 0
        var statPoint = false
        var titleUpgrade = false

        try dbQueue?.write { db in
            let today = Calendar.current.startOfDay(for: Date())
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

            if var existing = try QuestStreak.fetchOne(db, key: domain.rawValue) {
                let lastDay = Calendar.current.startOfDay(for: existing.lastCompletedDate)
                if Calendar.current.isDateInToday(existing.lastCompletedDate) {
                    // Already completed today — streak stays, just update count
                    existing.totalCompletions += 1
                } else if lastDay == yesterday {
                    // Consecutive day — increment streak
                    existing.currentStreak += 1
                    existing.longestStreak = max(existing.longestStreak, existing.currentStreak)
                    existing.totalCompletions += 1
                    existing.lastCompletedDate = Date()
                    bonusXP = QuestStreak.milestoneBonus(for: existing.currentStreak)
                    statPoint = existing.grantsStatPoint
                    titleUpgrade = existing.grantsTitleUpgrade
                } else {
                    // Missed day — reset streak
                    existing.currentStreak = 1
                    existing.totalCompletions += 1
                    existing.lastCompletedDate = Date()
                }
                try existing.update(db)
                result = existing
            } else {
                // First time completing a quest in this domain
                let fresh = QuestStreak(
                    domain:            domain.rawValue,
                    currentStreak:     1,
                    longestStreak:     1,
                    lastCompletedDate: Date(),
                    totalCompletions:  1
                )
                try fresh.insert(db)
                result = fresh
            }
        }
        return (result, bonusXP, statPoint, titleUpgrade)
    }

    // MARK: - Journal Entries

    func fetchJournalEntries(limit: Int = 30) throws -> [JournalEntry] {
        try dbQueue?.read { db in
            try JournalEntry
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        } ?? []
    }

    func saveJournalEntry(_ entry: JournalEntry) throws {
        try dbQueue?.write { db in
            try entry.save(db)
        }
    }

    // MARK: - Dungeon Mastery

    /// Fetch the mastery record for a topic, or nil if never studied.
    func fetchDungeonMastery(topic: String) throws -> DungeonMastery? {
        try dbQueue?.read { db in
            try DungeonMastery
                .filter(Column("topic") == topic)
                .fetchOne(db)
        }
    }

    /// Fetch all mastery records ordered by most recently studied.
    func fetchAllMasteries() throws -> [DungeonMastery] {
        try dbQueue?.read { db in
            try DungeonMastery
                .order(Column("lastStudiedAt").desc)
                .fetchAll(db)
        } ?? []
    }

    /// Insert or update a DungeonMastery record.
    func saveDungeonMastery(_ mastery: DungeonMastery) throws {
        try dbQueue?.write { db in
            // upsert: if id exists update, otherwise insert
            if try DungeonMastery.filter(Column("id") == mastery.id).fetchOne(db) != nil {
                try mastery.update(db)
            } else {
                try mastery.insert(db)
            }
        }
    }

    // MARK: - Errors

    enum DatabaseError: Error {
        case questNotFound
        case statsNotFound
    }
}
