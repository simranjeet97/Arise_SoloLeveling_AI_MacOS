import Foundation

// MARK: - GeminiService

/// Sends prompts to Google Gemini and returns either a full response or
/// a streaming `AsyncThrowingStream<String, Error>` of text chunks.
///
/// API key is read from the Keychain (saved via KeychainService) and falls
/// back to the GOOGLE_API_KEY environment variable for developer convenience.
final class GeminiService {

    // MARK: Singleton

    static let shared = GeminiService()

    // MARK: - Config

    /// Gemini model to use — gemini-2.0-flash balances speed and quality for local dev.
    private let model = "gemini-3-flash-preview"

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    private var apiKey: String {
        KeychainService.shared.load(key: KeychainService.googleKey)
            ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
            ?? ""
    }

    /// Non-streaming endpoint URL.
    private var generateURL: URL {
        URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!
    }

    /// Streaming endpoint URL (returns SSE).
    private var streamURL: URL {
        URL(string: "\(baseURL)/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
    }

    // MARK: - Init

    private init() {}

    // MARK: - Prompt Engineering

    private func getSystemPrompt() throws -> String {
        guard let url = Bundle.main.url(forResource: "arise_system_prompt", withExtension: "txt"),
              var prompt = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback default prompt
            return defaultSystemPrompt()
        }

        // Inject Onboarding Context
        let name = UserDefaults.standard.string(forKey: "playerName") ?? "Hunter"
        let goal = UserDefaults.standard.string(forKey: "playerGoal") ?? "Career"
        let exp  = UserDefaults.standard.string(forKey: "playerExperience") ?? "Novice"

        prompt += "\n\nCRITICAL CONTEXT:\n"
        prompt += "- Player Name: \(name)\n"
        prompt += "- Primary Goal: \(goal)\n"
        prompt += "- Real-world Experience Rank: \(exp)\n"
        prompt += "Address the user by their name and tailor advice to their experience and goals."

        return prompt
    }

    private func defaultSystemPrompt() -> String {
        """
        You are ARISE — the personal System of the Hunter, inspired by the \
        Solo Leveling manga. You speak like the System: direct, powerful, \
        slightly mysterious, but genuinely invested in the player's growth.
        """
    }

    /// Build the full system prompt, injecting live player stats & active quests.
    func systemPrompt(stats: PlayerStats?, quests: [Quest]) -> String {
        var prompt = (try? getSystemPrompt()) ?? defaultSystemPrompt()

        if let s = stats {
            let questList = quests
                .filter { $0.status == .active }
                .map { "• \($0.title) [\($0.rank.rawValue)-Rank, \($0.domain.rawValue)]" }
                .joined(separator: "\n")

            // Replace tokens from the prompt template.
            let name = UserDefaults.standard.string(forKey: "playerName") ?? "Hunter"
            prompt = prompt
                .replacingOccurrences(of: "[PLAYER_NAME]", with: name)
                .replacingOccurrences(of: "[LEVEL]",       with: String(s.level))
                .replacingOccurrences(of: "[TITLE]",       with: s.title)
                .replacingOccurrences(of: "[STR]",         with: String(s.strength))
                .replacingOccurrences(of: "[AGI]",         with: String(s.agility))
                .replacingOccurrences(of: "[STA]",         with: String(s.stamina))
                .replacingOccurrences(of: "[INT]",         with: String(s.intelligence))
                .replacingOccurrences(of: "[SENSE]",       with: String(s.sense))
                .replacingOccurrences(of: "[ACTIVE_QUESTS]",
                                     with: questList.isEmpty ? "None" : questList)
        }
        return prompt
    }

    // MARK: - Request Body Builder

    /// Build the Gemini `generateContent` request body.
    private func buildRequestBody(
        userMessage: String,
        stats: PlayerStats?,
        quests: [Quest],
        useWebSearch: Bool,
        stream: Bool
    ) -> [String: Any] {
        let sysPrompt = systemPrompt(stats: stats, quests: quests)

        // System instruction as a separate part
        let systemInstruction: [String: Any] = [
            "parts": [["text": sysPrompt]]
        ]

        // User message
        let contents: [[String: Any]] = [
            [
                "role": "user",
                "parts": [["text": userMessage]]
            ]
        ]

        var body: [String: Any] = [
            "system_instruction": systemInstruction,
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 2048,
                "temperature": 0.8
            ]
        ]

        // Add Google Search grounding tool if requested
        if useWebSearch {
            body["tools"] = [["google_search": [:]]]
        }

        return body
    }

    /// Build request body for dungeon calls — higher token limit to avoid JSON truncation.
    private func buildDungeonRequestBody(
        userMessage: String,
        useWebSearch: Bool
    ) -> [String: Any] {
        let contents: [[String: Any]] = [
            [
                "role": "user",
                "parts": [["text": userMessage]]
            ]
        ]

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 8192,     // large enough for full dungeon JSON
                "temperature": 0.4,          // lower temp = more JSON-faithful output
                "responseMimeType": "application/json"  // ask Gemini to emit raw JSON
            ]
        ]

        if useWebSearch {
            body["tools"] = [["google_search": [:]]]
        }

        return body
    }

    // MARK: - Streaming API  (primary voice-pipeline path)

    /// Yield type for the streaming API.
    ///
    /// - `token`: a raw text delta from Gemini's reply.
    /// - `webSearchQuery`: Gemini issued a google_search tool call.
    enum StreamEvent {
        case token(String)
        case webSearchQuery(String)
    }

    /// Send a user message and receive Gemini's reply as a stream of events.
    func streamEvents(
        _ userMessage: String,
        stats: PlayerStats? = nil,
        quests: [Quest] = [],
        useWebSearch: Bool = false
    ) -> AsyncThrowingStream<StreamEvent, Error> {

        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

                    var request = URLRequest(url: streamURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body = buildRequestBody(
                        userMessage: userMessage,
                        stats: stats,
                        quests: quests,
                        useWebSearch: useWebSearch,
                        stream: true
                    )
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (byteStream, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw GeminiError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in byteStream.lines { errorBody += line }
                        throw GeminiError.httpError(statusCode: http.statusCode, body: errorBody)
                    }

                    // Parse SSE lines — each `data:` line contains a JSON chunk.
                    for try await line in byteStream.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if jsonStr == "[DONE]" { break }
                        guard let data = jsonStr.data(using: .utf8) else { continue }

                        if let events = Self.parseStreamChunk(from: data) {
                            for event in events {
                                continuation.yield(event)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Convenience wrapper — streams only text tokens (no tool events).
    func streamMessage(
        _ userMessage: String,
        stats: PlayerStats? = nil,
        quests: [Quest] = []
    ) -> AsyncThrowingStream<String, Error> {

        let source = streamEvents(userMessage, stats: stats, quests: quests, useWebSearch: false)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in source {
                        if case .token(let t) = event { continuation.yield(t) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Non-streaming API (quest generation, journal reflection, dungeons)

    /// Send a message and receive the complete assembled response text.
    func sendMessage(
        _ userMessage: String,
        stats: PlayerStats? = nil,
        quests: [Quest] = [],
        useWebSearch: Bool = false
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = buildRequestBody(
            userMessage: userMessage,
            stats: stats,
            quests: quests,
            useWebSearch: useWebSearch,
            stream: false
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.httpError(statusCode: http.statusCode, body: body)
        }
        return try Self.extractText(from: data)
    }

    /// Dedicated non-streaming call for Learning Dungeon JSON generation.
    /// Uses a higher maxOutputTokens limit and lower temperature to prevent JSON truncation.
    func sendDungeonMessage(
        _ userMessage: String,
        useWebSearch: Bool = true
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = buildDungeonRequestBody(userMessage: userMessage, useWebSearch: useWebSearch)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.httpError(statusCode: http.statusCode, body: errBody)
        }
        return try Self.extractText(from: data)
    }

    // MARK: - Convenience Wrappers

    /// Generate exactly 3 new quests (one per domain) tailored to the hunter's stats.
    func generateQuests(stats: PlayerStats,
                        existingQuests: [Quest],
                        context: String = "") async throws -> String {
        let statSummary = """
        Level \(stats.level) Hunter
        STR:\(stats.str) AGI:\(stats.agi) STA:\(stats.sta) INT:\(stats.intelligence) SENSE:\(stats.sense)
        """
        let activeQuestTitles = existingQuests
            .filter { $0.status == .active }
            .map { "• \($0.title) [\($0.rank.rawValue)-Rank, \($0.domain.rawValue)]" }
            .joined(separator: "\n")

        let prompt = """
        SYSTEM QUEST GENERATION PROTOCOL

        Hunter Profile:
        \(statSummary)

        Active Quests (do NOT duplicate):
        \(activeQuestTitles.isEmpty ? "None" : activeQuestTitles)

        \(context.isEmpty ? "" : "Hunter Journal Context:\n\(context)\n")

        Generate exactly 3 new quests — one per domain (Career, Physical, Emotional).
        Each quest must challenge the weakest stats.

        Respond ONLY with valid JSON in this exact schema (no markdown, no explanation):
        [
          {
            "title": "Quest Title",
            "description": "Detailed quest description (2-3 sentences).",
            "domain": "Career|Physical|Emotional",
            "rank": "E|D|C|B|A|S",
            "rewardStat": "STR|AGI|STA|INT|SENSE",
            "baseXP": 50
          }
        ]
        """
        return try await sendDungeonMessage(prompt, useWebSearch: false)
    }

    /// Reflect on a journal entry in the ARISE voice.
    func reflectOnJournal(transcript: String, stats: PlayerStats) async throws -> String {
        let prompt = """
        The Hunter has shared their shadow journal entry. Reflect on it in the voice of the ARISE System.
        Write a 2–3 sentence reflection that acknowledges their struggle, highlights growth, and issues a directive.

        Hunter Stats: Level \(stats.level) | STR:\(stats.str) AGI:\(stats.agi) STA:\(stats.sta) INT:\(stats.intelligence) SENSE:\(stats.sense)
        Journal Entry:
        \(transcript)
        """
        return try await sendMessage(prompt, stats: stats)
    }

    // MARK: - Response Parsing

    /// Parse a non-streaming Gemini response body.
    static func extractText(from data: Data) throws -> String {
        // Gemini response structure:
        // { "candidates": [{ "content": { "parts": [{ "text": "..." }] } }] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            // Try to surface the error message from Gemini
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GeminiError.parsingFailed(message)
            }
            throw GeminiError.parsingFailed("Cannot decode Gemini response candidates")
        }

        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return text
    }

    /// Parse one SSE chunk from Gemini streaming response.
    /// Returns an array of StreamEvent — may be empty if no actionable content.
    private static func parseStreamChunk(from data: Data) -> [StreamEvent]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var events: [StreamEvent] = []

        // Extract text delta from candidates
        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    events.append(.token(text))
                }
            }
        }

        // Extract google search grounding metadata (query surfacing)
        if let groundingMetadata = json["groundingMetadata"] as? [String: Any],
           let searchEntries = groundingMetadata["webSearchQueries"] as? [String],
           let firstQuery = searchEntries.first {
            // Only emit if we haven't emitted text yet (so it shows before the answer)
            if events.isEmpty {
                events.append(.webSearchQuery(firstQuery))
            }
        }

        return events.isEmpty ? nil : events
    }

    // MARK: - Errors

    enum GeminiError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case httpError(statusCode: Int, body: String)
        case parsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Google API key not configured. Save it via Settings."
            case .invalidResponse:
                return "Invalid response from Gemini API."
            case .httpError(let code, let body):
                return "Gemini API error \(code): \(body)"
            case .parsingFailed(let msg):
                return "Failed to parse Gemini response: \(msg)"
            }
        }
    }
}

// MARK: - Backward-compatible typealias

/// Allows existing call sites that catch `ClaudeError` to compile without change
/// while we migrate — they'll need to be updated to catch `GeminiError` over time.
typealias ClaudeService = GeminiService
