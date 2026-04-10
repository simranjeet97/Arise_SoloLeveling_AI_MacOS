import Foundation

// MARK: - EmotionalAnalysisResult

struct EmotionalAnalysisResult: Decodable {
    let acknowledgment: String
    let reframingQuestion: String
    let microAction: String
    let emotion: String
    let intensity: Int
}

// MARK: - EmotionalAnalysisService

@MainActor
final class EmotionalAnalysisService {

    static let shared = EmotionalAnalysisService()

    private let gemini = GeminiService.shared
    private let db = DatabaseService.shared

    private init() {}

    /// Submits a journal entry to Claude, extracts emotional intelligence,
    /// constructs the JournalEntry, and saves it to the database.
    func analyzeAndSaveJournal(transcript: String) async throws -> JournalEntry {
        let prompt = """
        You are ARISE in Shadow Dungeon mode — the emotional intelligence 
        layer of the player's personal system. The player has shared:
        
        '\(transcript)'
        
        Respond with:
        1. A 1-sentence empathetic acknowledgment (warm, not clinical)
        2. One reframing question to help them see it differently  
        3. One micro-action they can take in the next 10 minutes
        4. Detect emotion: {emotion: 'joy|stress|anxiety|sadness|neutral|anger', intensity: 1-10}
        
        Keep total response under 100 words. Speak like a trusted mentor, 
        not a therapist.
        
        Respond strictly in valid JSON matching this schema:
        {
          "acknowledgment": "...",
          "reframingQuestion": "...",
          "microAction": "...",
          "emotion": "stress",
          "intensity": 8
        }
        """

        let jsonString = try await gemini.sendMessage(prompt)
        
        // Clean markdown blocks if Claude wraps it
        let cleanedJSON = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleanedJSON.data(using: .utf8) else {
            throw EmotionalAnalysisError.invalidResponse
        }

        let result = try JSONDecoder().decode(EmotionalAnalysisResult.self, from: data)

        // Combine the 3 parts into the summary for the legacy UI/properties
        let combinedSummary = """
        \(result.acknowledgment)
        
        \(result.reframingQuestion)
        
        Action: \(result.microAction)
        """

        let entry = JournalEntry.new(
            rawTranscript: transcript,
            claudeSummary: combinedSummary,
            mood: mapEmotionToMoodRating(result.emotion, intensity: result.intensity),
            emotion: result.emotion,
            intensity: result.intensity
        )

        try db.saveJournalEntry(entry)

        return entry
    }

    /// Legacy mapping for UI compatibility
    private func mapEmotionToMoodRating(_ emotion: String, intensity: Int) -> JournalEntry.MoodRating {
        switch emotion.lowercased() {
        case "joy":     return intensity > 7 ? .blazing : .spark
        case "stress", "anxiety", "anger": return intensity > 7 ? .shadow : .dim
        case "sadness": return .shadow
        default:        return .neutral
        }
    }

    enum EmotionalAnalysisError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Failed to process the Shadow Dungeon response."
            }
        }
    }
}
