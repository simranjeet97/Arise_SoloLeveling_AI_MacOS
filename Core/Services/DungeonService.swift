import Foundation

// MARK: - LearningDungeon

/// The full result of a Learning Dungeon research session.
/// Claude searches the web, synthesises a teaching summary, and generates quiz questions.
struct LearningDungeon {

    // MARK: - Quiz Question

    struct Question: Identifiable {
        let id:      String         // stable UUID for SwiftUI
        let prompt:  String
        let options: [String]       // exactly 4 choices
        let answer:  String         // one of the options verbatim
    }

    // MARK: - Source

    struct Source {
        let title:   String
        let url:     String
    }

    // MARK: - Properties

    let topic:    String
    let summary:  String
    let sources:  [Source]
    let questions: [Question]

    // MARK: - XP Calculation

    /// XP awarded per correct answer (INT-weighted: base 40 + 10 per question)
    static let xpPerCorrectAnswer = 50
    /// Bonus awarded for a perfect score
    static let perfectScoreBonus  = 75
}

// MARK: - DungeonService

/// Orchestrates a learning dungeon:
///   1. Calls Gemini with the `google_search` tool enabled
///   2. Parses the structured JSON response
///   3. Persists mastery progress to the database
///   4. Awards INT + SENSE XP for correct answers
@MainActor
final class DungeonService: ObservableObject {

    // MARK: Singleton

    static let shared = DungeonService()

    // MARK: - Published State

    @Published var isResearching:    Bool = false
    @Published var researchingQuery: String? = nil
    @Published var lastError:        String? = nil

    // MARK: - Dependencies

    private let gemini = GeminiService.shared
    private let db     = DatabaseService.shared

    // MARK: - Init

    private init() {}

    // MARK: - Enter Dungeon

    /// Research `topic` with web search, returning a fully parsed `LearningDungeon`.
    ///
    /// Claude is instructed to:
    ///  - Search for authoritative sources
    ///  - Synthesise a 200-word teaching summary
    ///  - Generate 3 quiz questions with 4 options each
    ///
    /// The raw JSON response is also printed to the console so the CLI test can capture it.
    func enterLearningDungeon(topic: String) async -> LearningDungeon? {
        isResearching = true
        lastError = nil
        defer { isResearching = false; researchingQuery = nil }

        let prompt = dungeonPrompt(for: topic)

        // Use the dedicated dungeon call: non-streaming, 8 192 tokens, JSON MIME type.
        // This avoids the token-truncation bug that caused malformed JSON when using
        // the streaming path with the 2 048-token general limit.
        let rawJSON: String
        do {
            rawJSON = try await gemini.sendDungeonMessage(prompt, useWebSearch: true)
        } catch {
            lastError = error.localizedDescription
            print("[DungeonService] ❌ Gemini error: \(error)")
            return nil
        }

        // Strip any leftover markdown fences the model may still emit.
        let cleaned = rawJSON
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[DungeonService] 📄 Raw JSON from Gemini:\n\(cleaned)")

        guard let dungeon = parseDungeonJSON(cleaned, topic: topic) else {
            lastError = "Failed to parse dungeon JSON. Raw response logged above."
            return nil
        }

        // Persist / update mastery record (start at 0% — quiz updates it later).
        try? persistMastery(for: topic, xpEarned: 0, correctAnswers: 0, total: 0)

        return dungeon
    }

    // MARK: - Record Quiz Result

    /// Call after the player finishes the quiz to award XP and update mastery.
    func recordQuizResult(
        topic:          String,
        correctAnswers: Int,
        outOf total:    Int
    ) {
        let xpEarned = correctAnswers * LearningDungeon.xpPerCorrectAnswer
            + (correctAnswers == total ? LearningDungeon.perfectScoreBonus : 0)

        // Award INT + SENSE stat XP via the database.
        let intGain  = max(1, correctAnswers * 2)
        let senseGain = correctAnswers > 0 ? 1 : 0

        do {
            if var stats = try db.fetchPlayerStats() {
                stats.intelligence += intGain
                stats.sense        += senseGain
                try db.updateStats(stats)
            }
            try db.addXP(amount: xpEarned)
        } catch {
            print("[DungeonService] ❌ XP award failed: \(error)")
        }

        try? persistMastery(for: topic,
                            xpEarned: xpEarned,
                            correctAnswers: correctAnswers,
                            total: total)

        print("[DungeonService] 🏆 Quiz complete — \(correctAnswers)/\(total) correct, +\(xpEarned) XP")
    }

    // MARK: - Mastery Persistence

    func fetchMastery(for topic: String) -> DungeonMastery? {
        try? db.fetchDungeonMastery(topic: topic)
    }

    @discardableResult
    private func persistMastery(
        for topic: String,
        xpEarned: Int,
        correctAnswers: Int,
        total: Int
    ) throws -> DungeonMastery {
        var mastery = (try? db.fetchDungeonMastery(topic: topic)) ?? DungeonMastery.fresh(topic: topic)
        if total > 0 {
            mastery.recordQuizResult(correctAnswers: correctAnswers, outOf: total, xpEarned: xpEarned)
        }
        try db.saveDungeonMastery(mastery)
        return mastery
    }

    // MARK: - Prompt

    private func dungeonPrompt(for topic: String) -> String {
        """
        LEARNING DUNGEON PROTOCOL — ARISE System Research Mode

        You are researching "\(topic)" for the Hunter's Learning Dungeon.

        Instructions:
        1. Use web_search to find 3 authoritative, up-to-date sources about "\(topic)".
        2. Synthesise a clear 200-word teaching summary at an intermediate software-engineer level.
           Write it in the ARISE System voice — direct, precise, knowledge-dense.
        3. Generate exactly 3 quiz questions that test comprehension of the summary.
           Each question must have exactly 4 answer options labeled A, B, C, D.
           Include the correct answer as the full text of the correct option.

        CRITICAL: Respond ONLY with valid JSON matching this exact schema.
        No markdown fences, no explanation, no preamble — pure JSON only:

        {
          "summary": "...",
          "sources": [
            { "title": "...", "url": "..." }
          ],
          "questions": [
            {
              "q": "Question text?",
              "options": ["A. ...", "B. ...", "C. ...", "D. ..."],
              "answer": "A. ..."
            }
          ]
        }
        """
    }

    // MARK: - JSON Parsing

    private func parseDungeonJSON(_ json: String, topic: String) -> LearningDungeon? {
        guard let data = json.data(using: .utf8) else { return nil }

        struct SourceDTO: Decodable {
            let title: String
            let url:   String
        }
        struct QuestionDTO: Decodable {
            let q:       String
            let options: [String]
            let answer:  String
        }
        struct DungeonDTO: Decodable {
            let summary:   String
            let sources:   [SourceDTO]
            let questions: [QuestionDTO]
        }

        guard let dto = try? JSONDecoder().decode(DungeonDTO.self, from: data) else {
            return nil
        }

        let sources = dto.sources.map {
            LearningDungeon.Source(title: $0.title, url: $0.url)
        }
        let questions = dto.questions.map { q in
            LearningDungeon.Question(
                id:      UUID().uuidString,
                prompt:  q.q,
                options: q.options,
                answer:  q.answer
            )
        }

        return LearningDungeon(
            topic:     topic,
            summary:   dto.summary,
            sources:   sources,
            questions: questions
        )
    }
}
