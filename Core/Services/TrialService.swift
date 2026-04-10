import Foundation

// MARK: - TrialReport

/// The Shadow Monarch's monthly assessment of the Hunter's journey.
struct TrialReport {
    let month:           String    // "March 2026"
    let achievement:     String    // Paragraph 1: what was achieved
    let weakestDungeon:  String    // Paragraph 2: weakest area
    let nextUnlock:      String    // Paragraph 3: one skill to unlock next month
    let generatedAt:     Date
    let statChanges:     [String: Int]   // stat → delta this month
    let questsCompleted: Int
    let xpEarned:        Int
}

// MARK: - TrialService

/// Runs the Shadow Monarch's Trial on the 1st of each month.
///
/// Flow:
///   1. Monthly Timer fires on the 1st at 09:00 AM
///   2. Fetches all quests completed this month, journal entries, and stat changes
///   3. Asks Claude to generate a 3-paragraph spoken Trial Report
///   4. ARISE speaks the report via VoiceOutputService
///   5. Report is persisted to UserDefaults for the TrialView to display
@MainActor
final class TrialService: ObservableObject {

    // MARK: Singleton

    static let shared = TrialService()

    // MARK: Published

    @Published var lastReport:     TrialReport? = nil
    @Published var isGenerating:   Bool         = false

    // MARK: - Keys

    private let reportKey = "ARISE_LastTrialReport"

    // MARK: - Dependencies

    private let db     = DatabaseService.shared
    private let claude = ClaudeService.shared
    private let voice  = VoiceOutputService.shared

    // MARK: - Timer

    private var trialTimer: Timer?

    // MARK: - Init

    private init() {
        loadCachedReport()
        scheduleMonthlyTrial()
    }

    // MARK: - Schedule

    /// Schedule the trial to fire on the 1st of next month at 09:00 AM.
    private func scheduleMonthlyTrial() {
        guard let nextFirst = nextFirstOfMonth() else { return }
        let delay = nextFirst.timeIntervalSinceNow
        trialTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = await self?.runMonthlyTrial()
                self?.scheduleMonthlyTrial()  // re-arm
            }
        }
        print("[TrialService] ⚖️ Monthly trial scheduled for \(nextFirst)")
    }

    private func nextFirstOfMonth() -> Date? {
        let cal    = Calendar.current
        let now    = Date()
        var comps  = cal.dateComponents([.year, .month], from: now)
        comps.day  = 1
        comps.hour = 9
        comps.minute = 0
        comps.second = 0
        guard let thisFirst = cal.date(from: comps) else { return nil }
        if thisFirst > now { return thisFirst }
        // Already past the 1st — schedule for next month
        guard let next = cal.date(byAdding: .month, value: 1, to: thisFirst) else { return nil }
        return next
    }

    // MARK: - Run Trial

    /// Generate the monthly Trial Report for the given month.
    /// Pass `month: nil` to use the _previous_ calendar month (the default behaviour).
    @discardableResult
    func runMonthlyTrial(month referenceDate: Date? = nil) async -> TrialReport? {
        guard !isGenerating else { return nil }
        isGenerating = true
        defer { isGenerating = false }

        let calendar = Calendar.current
        let ref      = referenceDate ?? Date()

        // ── Fetch data for the previous calendar month ───────────────────────────
        let prevMonthDate  = calendar.date(byAdding: .month, value: -1, to: ref) ?? ref
        let monthName      = monthYearString(prevMonthDate)
        let daysInMonth    = calendar.range(of: .day, in: .month, for: prevMonthDate)?.count ?? 30

        let completedThisMonth  = (try? db.fetchCompletedQuests(inLastDays: daysInMonth)) ?? []
        let journals            = (try? db.fetchJournalEntries(limit: 20)) ?? []
        let stats               = (try? db.fetchStats()) ?? nil
        let streaks             = (try? db.fetchAllStreaks()) ?? []

        // Summarise completions by domain
        let byDomain = Dictionary(grouping: completedThisMonth, by: { $0.domain })
        let domainSummary = QuestDomain.allCases.map { domain -> String in
            let count = byDomain[domain]?.count ?? 0
            let streak = streaks.first { $0.domain == domain.rawValue }?.currentStreak ?? 0
            return "\(domain.displayName): \(count) quests | streak \(streak)d"
        }.joined(separator: "\n")

        let journalSample = journals.prefix(5).map { $0.rawTranscript }.joined(separator: "\n---\n")
        let statStr = stats.map {
            "STR:\($0.strength) AGI:\($0.agility) STA:\($0.stamina) INT:\($0.intelligence) SENSE:\($0.sense) | Level \($0.level)"
        } ?? "Stats unavailable"

        // Weakest domain
        let weakest = QuestDomain.allCases.min { a, b in
            (byDomain[a]?.count ?? 0) < (byDomain[b]?.count ?? 0)
        } ?? .emotional

        let prompt = """
        SHADOW MONARCH'S TRIAL — \(monthName) Assessment

        You are ARISE — the System. Deliver a spoken Trial Report for the Hunter.
        Write exactly 3 short paragraphs, total 150-200 words, in the ARISE System voice.
        Direct, powerful, slightly mysterious. No bullet points.

        Hunter Data for \(monthName):
        Current Stats: \(statStr)
        Quest Completions by Domain:
        \(domainSummary)
        Total Quests Completed: \(completedThisMonth.count)
        Journal Excerpts:
        \(journalSample.isEmpty ? "No entries." : journalSample)

        Paragraph 1 — ACHIEVEMENT: What did the Hunter accomplish? Be specific about the strongest domain.
        Paragraph 2 — WEAKEST DUNGEON: Call out \(weakest.displayName) as their dungeon of weakness. Be direct.
        Paragraph 3 — NEXT MONTH'S UNLOCK: One specific skill, habit, or challenge to pursue next month.

        Respond with ONLY the 3 paragraphs, no labels, no formatting.
        """

        do {
            let reportText = try await claude.sendMessage(prompt, stats: stats)
            let paragraphs = reportText
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let achievement    = paragraphs.indices.contains(0) ? paragraphs[0] : reportText
            let weakestDungeon = paragraphs.indices.contains(1) ? paragraphs[1] : ""
            let nextUnlock     = paragraphs.indices.contains(2) ? paragraphs[2] : ""

            let xpEarned = completedThisMonth.reduce(0) { $0 + $1.xpReward }

            let report = TrialReport(
                month:           monthName,
                achievement:     achievement,
                weakestDungeon:  weakestDungeon,
                nextUnlock:      nextUnlock,
                generatedAt:     Date(),
                statChanges:     [:],
                questsCompleted: completedThisMonth.count,
                xpEarned:        xpEarned
            )
            lastReport = report
            cacheReport(report)

            // Speak the full report
            let spoken = "Shadow Monarch's Trial — \(monthName) Assessment. "
                       + achievement + " "
                       + weakestDungeon + " "
                       + nextUnlock
            voice.speak(spoken)

            print("[TrialService] ✅ Trial report generated for \(monthName)")
            return report

        } catch {
            print("[TrialService] ❌ Trial generation error: \(error)")
            return nil
        }
    }

    // MARK: - Persistence (UserDefaults)

    private func cacheReport(_ report: TrialReport) {
        let dict: [String: Any] = [
            "month":           report.month,
            "achievement":     report.achievement,
            "weakestDungeon":  report.weakestDungeon,
            "nextUnlock":      report.nextUnlock,
            "generatedAt":     report.generatedAt.timeIntervalSince1970,
            "questsCompleted": report.questsCompleted,
            "xpEarned":        report.xpEarned
        ]
        UserDefaults.standard.set(dict, forKey: reportKey)
    }

    private func loadCachedReport() {
        guard let dict = UserDefaults.standard.dictionary(forKey: reportKey),
              let month          = dict["month"]          as? String,
              let achievement    = dict["achievement"]    as? String,
              let weakestDungeon = dict["weakestDungeon"] as? String,
              let nextUnlock     = dict["nextUnlock"]     as? String,
              let ts             = dict["generatedAt"]    as? Double
        else { return }

        lastReport = TrialReport(
            month:           month,
            achievement:     achievement,
            weakestDungeon:  weakestDungeon,
            nextUnlock:      nextUnlock,
            generatedAt:     Date(timeIntervalSince1970: ts),
            statChanges:     [:],
            questsCompleted: dict["questsCompleted"] as? Int ?? 0,
            xpEarned:        dict["xpEarned"]        as? Int ?? 0
        )
    }

    // MARK: - Helpers

    private func monthYearString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }
}
