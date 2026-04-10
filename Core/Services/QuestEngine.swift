import Foundation

// MARK: - QuestEngine

/// Orchestrates quest generation (via Claude), completion, streaks, and stat rewards.
///
/// Key behaviours added:
///   • `generateDailyQuests()` — called at 8 AM via a daily Timer; prompts Claude
///     with the player's weak stats and last-7-days completions.
///   • Streak tracking — each domain completion increments its streak counter.
///     Milestone logic: 7d → +5 bonus XP, 30d → stat point, 100d → title upgrade.
///   • Penalty Quest — spawned automatically if a domain had no completion yesterday.
///   • Voice-detected completion — `completeQuestByVoiceIntent(transcript:)` lets
///     Claude detect intent from spoken text ("I finished my workout").
///   • Level-up — published via `pendingLevelUp` for the overlay to observe.
@MainActor
final class QuestEngine: ObservableObject {

    // MARK: Singleton
    static let shared = QuestEngine()

    // MARK: - Published State

    @Published var activeQuests:     [Quest]       = []
    @Published var completedQuests:  [Quest]       = []
    @Published var playerStats:      PlayerStats?
    @Published var streaks:          [QuestStreak] = []
    @Published var isGenerating:     Bool          = false
    @Published var lastSystemAlert:  String        = ""
    @Published var pendingLevelUp:   LevelUpEvent? = nil  // consumed by LevelUpOverlayView

    // MARK: - LevelUpEvent

    struct LevelUpEvent: Identifiable {
        let id    = UUID()
        let level: Int
        let title: String
    }

    // MARK: - Dependencies

    private let db      = DatabaseService.shared
    private let gemini  = GeminiService.shared
    private let voice   = VoiceOutputService.shared

    // MARK: - Daily Schedule Timer

    private var dailyQuestTimer: Timer?

    // MARK: - Init

    private init() {
        loadFromDatabase()
        scheduleDailyQuestGeneration()
        Task { await checkPenaltyQuests() }
    }

    // MARK: - Load / Refresh

    func loadFromDatabase() {
        do {
            playerStats     = try db.fetchStats()
            let allQuests   = try db.fetchAllQuests()
            activeQuests    = allQuests.filter { $0.status == .active }
            completedQuests = allQuests.filter { $0.status == .completed }
            streaks         = (try? db.fetchAllStreaks()) ?? []
        } catch {
            print("[QuestEngine] Load error: \(error)")
        }
    }

    // MARK: - Daily Quest Scheduling

    /// Schedule `generateDailyQuests()` to fire every day at 8:00 AM.
    private func scheduleDailyQuestGeneration() {
        let calendar = Calendar.current
        let now      = Date()
        // Next 8:00 AM
        var comps    = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour   = 8
        comps.minute = 0
        comps.second = 0
        guard var nextFire = calendar.date(from: comps) else { return }
        if nextFire <= now {
            nextFire = calendar.date(byAdding: .day, value: 1, to: nextFire) ?? nextFire
        }
        let delay = nextFire.timeIntervalSinceNow
        dailyQuestTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.generateDailyQuests()
                // Re-schedule for the *next* day
                self?.scheduleDailyQuestGeneration()
            }
        }
        print("[QuestEngine] ⏰ Daily quests scheduled for \(nextFire)")
    }

    // MARK: - Daily Quest Generation

    /// Generates exactly 3 personalised daily quests via Claude:
    ///   1. E/D-rank Physical  (workout, sleep, nutrition)
    ///   2. C/B-rank Career    (coding, skill, research)
    ///   3. C-rank Emotional   (journal, reflection, social)
    ///
    /// Prompt weight: weak stats receive more impactful quests.
    func generateDailyQuests() async {
        guard let stats = playerStats else { return }
        guard !isGenerating else { return }

        isGenerating = true
        defer { isGenerating = false }

        // Build prompt context
        let statSummary  = statsSummary(stats)
        let weakStats    = weakestStats(stats)
        let recentTitles = (try? db.fetchCompletedQuests(inLastDays: 7))?.map { $0.title } ?? []
        let recentStr    = recentTitles.isEmpty ? "None" : recentTitles.prefix(10).joined(separator: "; ")

        let prompt = """
        ARISE DAILY QUEST GENERATION PROTOCOL

        Generate today's quest log for the Hunter.

        Player Stats: \(statSummary)
        Weakest stats (improve these): \(weakStats)
        Recent completions (last 7 days): \(recentStr)

        Generate exactly 3 quests — one per domain in this order:
        1. One E or D-rank PHYSICAL quest (workout, sleep, nutrition, movement)
        2. One C or B-rank CAREER quest (coding, project, research, skill-building)
        3. One C-rank EMOTIONAL quest (journaling, reflection, meditation, social connection)

        Rules:
        - Make each quest SPECIFIC and ACTIONABLE (not vague like "exercise more")
        - If SENSE is the lowest stat, make the emotional quest transformative
        - If STR/STA is lowest, make the physical quest more challenging
        - Do NOT repeat any quest from the recent completions list
        - estimatedMinutes must be realistic (5-120)

        Respond ONLY with a valid JSON array. No markdown, no explanation:
        [
          {
            "title": "...",
            "description": "Specific, actionable 2-sentence description.",
            "domain": "physical|career|emotional",
            "rank": "E|D|C|B",
            "xpReward": 60,
            "statRewards": { "stamina": 2 },
            "completionCriteria": "One-sentence measurable success condition.",
            "estimatedMinutes": 30
          }
        ]
        """

        do {
            let jsonStr  = try await gemini.sendDungeonMessage(prompt, useWebSearch: false)
            let newQuests = try parseQuestJSON(jsonStr)
            for quest in newQuests { try db.saveQuest(quest) }
            loadFromDatabase()
            announceNewQuests(newQuests)
            print("[QuestEngine] ✅ Generated \(newQuests.count) daily quests")
        } catch {
            print("[QuestEngine] Generation error: \(error)")
            lastSystemAlert = "Quest generation failed: \(error.localizedDescription)"
        }
    }

    /// Legacy method — calls `generateDailyQuests()`.
    func generateNewQuests(journalContext: String = "") async {
        await generateDailyQuests()
    }

    // MARK: - Quest Completion

    /// Mark a quest as completed, update streak, apply stat + XP rewards with milestone bonuses.
    func completeQuest(_ quest: Quest) {
        do {
            // 1. Core completion (stats + XP in one DB transaction)
            let result = try db.completeQuest(id: quest.id)
            playerStats = result.stats

            // 2. Streak update
            let streakResult = try db.updateStreakOnCompletion(domain: quest.domain)
            let streak        = streakResult.streak

            // 3. Bonus XP for streak milestones
            var totalBonusXP = streakResult.bonusXP
            if streakResult.bonusXP > 0 {
                try db.addXP(amount: streakResult.bonusXP)
                totalBonusXP = streakResult.bonusXP
            }

            // 4. Stat point for 30-day streak (award to the matching domain stat)
            if streakResult.grantsStatPoint, var stats = playerStats {
                let rewardStat = dominantStat(for: quest.domain)
                stats[rewardStat] += 1
                try db.updateStats(stats)
                playerStats = stats
                print("[QuestEngine] 🏆 30-Day streak! +1 \(rewardStat.displayName)")
            }

            // 5. Title upgrade for 100-day streak
            if streakResult.grantsTitleUpgrade, var stats = playerStats {
                stats.level = min(100, stats.level + 1)
                stats.title = PlayerStats.titleForLevel(stats.level)
                try db.updateStats(stats)
                playerStats = stats
            }

            loadFromDatabase()

            // 6. Level-up check
            if result.didLevelUp {
                let lvl = result.stats.level
                pendingLevelUp = LevelUpEvent(level: lvl, title: result.stats.title)
            }

            // 7. Announce
            let xpTotal   = quest.xpReward + totalBonusXP
            let statDetail = quest.statRewards
                .map { "\($0.key.capitalized) +\($0.value)" }
                .joined(separator: ", ")
            var msg = "Quest complete: \(quest.title). +\(xpTotal) XP awarded."
            if !statDetail.isEmpty { msg += " \(statDetail)." }
            if streak.currentStreak > 1 { msg += " \(streak.currentStreak)-day streak 🔥" }
            if result.didLevelUp  { msg += " LEVEL UP! Now Level \(result.stats.level)." }
            lastSystemAlert = msg
            voice.speak(msg)

        } catch {
            print("[QuestEngine] Complete quest error: \(error)")
        }
    }

    /// Abandon a quest (no rewards).
    func abandonQuest(_ quest: Quest) {
        var updated = quest
        updated.status = .abandoned
        try? db.saveQuest(updated)
        loadFromDatabase()
    }

    // MARK: - Voice Intent Completion

    /// Parse a spoken transcript like "I finished my workout" and auto-complete
    /// the matching active quest by asking Claude to detect intent.
    /// Returns true if a quest was successfully completed.
    func completeQuestByVoiceIntent(transcript: String) async -> Bool {
        guard !activeQuests.isEmpty else { return false }

        let questList = activeQuests.enumerated()
            .map { "\($0.offset + 1). \($0.element.title) [\($0.element.domain.rawValue)]" }
            .joined(separator: "\n")

        let prompt = """
        The Hunter said: "\(transcript)"

        Active quests:
        \(questList)

        If the Hunter's statement clearly indicates completion of one of these quests,
        respond with ONLY the quest number (1, 2, or 3). Otherwise respond with "none".
        No explanation, no punctuation — just the number or "none".
        """

        do {
            let response = try await gemini.sendMessage(prompt).trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = Int(response), idx >= 1, idx <= activeQuests.count {
                let quest = activeQuests[idx - 1]
                completeQuest(quest)
                return true
            } else {
                print("[QuestEngine] Voice intent: no matching quest for '\(transcript)'")
                return false
            }
        } catch {
            print("[QuestEngine] Voice intent error: \(error)")
            return false
        }
    }

    // MARK: - Penalty Quests

    /// For each domain that had no completion yesterday, spawn a fast "Penalty Quest".
    func checkPenaltyQuests() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let completedYesterday = (try? db.fetchCompletedQuests(inLastDays: 1)) ?? []
        let domainsCompleted = Set(completedYesterday.map { $0.domain })

        // Only apply penalty if the player has been using ARISE for at least 1 day
        guard let firstQuestDate = completedQuests.last?.createdAt,
              firstQuestDate < yesterday else { return }

        let penaltyDomains = QuestDomain.allCases.filter { domain in
            // Only check physical/career/emotional — skip social/learning
            [.physical, .career, .emotional].contains(domain) &&
            !domainsCompleted.contains(domain)
        }

        for domain in penaltyDomains {
            // Don't spawn a penalty if there's already an active quest in this domain
            let existingActive = activeQuests.first { $0.domain == domain }
            guard existingActive == nil else { continue }

            let penalty = penaltyQuest(for: domain)
            try? db.saveQuest(penalty)
            print("[QuestEngine] ⚠️ Penalty quest spawned for \(domain.displayName)")
        }

        if !penaltyDomains.isEmpty {
            loadFromDatabase()
            let domains = penaltyDomains.map { $0.displayName }.joined(separator: " and ")
            let msg = "Penalty quest activated. You missed \(domains) yesterday. Complete the penalty to maintain your path."
            lastSystemAlert = msg
            voice.speak(msg)
        }
    }

    private func penaltyQuest(for domain: QuestDomain) -> Quest {
        switch domain {
        case .physical:
            return Quest.new(
                title:       "Penalty: 10 Pushups",
                description: "You missed your physical training. Complete 10 pushups now to pay your dues and reset your discipline.",
                domain:      .physical,
                rank:        .E,
                xpReward:    10,
                statRewards: [:]
            )
        case .career:
            return Quest.new(
                title:       "Penalty: 15-Minute Focus",
                description: "You missed your career quest. Spend 15 focused minutes on any technical task — no distractions.",
                domain:      .career,
                rank:        .E,
                xpReward:    10,
                statRewards: [:]
            )
        case .emotional:
            return Quest.new(
                title:       "Penalty: Breathing Reset",
                description: "You missed your emotional quest. Complete 5 minutes of box breathing (4 counts in, hold, out, hold).",
                domain:      .emotional,
                rank:        .E,
                xpReward:    10,
                statRewards: [:]
            )
        default:
            return Quest.new(
                title:       "Penalty: System Alert",
                description: "Complete this 5-minute task to maintain progress.",
                domain:      domain,
                rank:        .E,
                xpReward:    10,
                statRewards: [:]
            )
        }
    }

    // MARK: - Streak Helpers

    /// Current streak count for a given domain (from published `streaks`).
    func currentStreak(for domain: QuestDomain) -> Int {
        streaks.first { $0.domain == domain.rawValue }?.currentStreak ?? 0
    }

    // MARK: - Parsing

    private func parseQuestJSON(_ json: String) throws -> [Quest] {
        let cleaned = json
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw ParsingError.invalidData
        }

        struct QuestDTO: Decodable {
            let title:                String
            let description:          String
            let domain:               String
            let rank:                 String
            let xpReward:             Int?
            let baseXP:               Double?
            let statRewards:          [String: Int]?
            let completionCriteria:   String?
            let estimatedMinutes:     Int?
        }

        let dtos = try JSONDecoder().decode([QuestDTO].self, from: data)
        return dtos.compactMap { dto -> Quest? in
            guard
                let domain = QuestDomain(rawValue: dto.domain.lowercased()),
                let rank   = QuestRank(rawValue: dto.rank.uppercased())
            else { return nil }

            let xp = dto.xpReward ?? Int(dto.baseXP ?? 50)
            var q = Quest.new(
                title:       dto.title,
                description: dto.description,
                domain:      domain,
                rank:        rank,
                xpReward:    xp,
                statRewards: dto.statRewards ?? [:]
            )
            // Store completionCriteria in description if present
            if let criteria = dto.completionCriteria, !criteria.isEmpty {
                q.description += "\n\nCompletion: \(criteria)"
            }
            return q
        }
    }

    // MARK: - Announcements

    private func announceNewQuests(_ quests: [Quest]) {
        guard !quests.isEmpty else { return }
        let titles = quests.map { $0.title }.joined(separator: ". ")
        let msg = "New quests have emerged from the shadows. \(titles)"
        lastSystemAlert = msg
        voice.speak(msg)
    }

    // MARK: - Stat Helpers

    private func statsSummary(_ stats: PlayerStats) -> String {
        "STR:\(stats.strength) AGI:\(stats.agility) STA:\(stats.stamina) INT:\(stats.intelligence) SENSE:\(stats.sense)"
    }

    private func weakestStats(_ stats: PlayerStats) -> String {
        let all: [(StatKey, Int)] = [
            (.strength,     stats.strength),
            (.agility,      stats.agility),
            (.stamina,      stats.stamina),
            (.intelligence, stats.intelligence),
            (.sense,        stats.sense)
        ]
        return all.sorted { $0.1 < $1.1 }
            .prefix(2)
            .map { "\($0.0.displayName) (\($0.1))" }
            .joined(separator: ", ")
    }

    private func dominantStat(for domain: QuestDomain) -> StatKey {
        switch domain {
        case .physical:  return .stamina
        case .career:    return .intelligence
        case .emotional: return .sense
        case .social:    return .sense
        case .learning:  return .intelligence
        }
    }

    // MARK: - Errors

    enum ParsingError: Error {
        case invalidData
    }
}
