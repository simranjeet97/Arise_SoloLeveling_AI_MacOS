import Foundation
import AVFoundation

// MARK: - VoiceOutputService

/// AVSpeechSynthesizer wrapper with a sentence queue so Claude's streaming
/// tokens can be spoken as complete sentences arrive — minimising first-word
/// latency while avoiding choppy mid-sentence cuts.
final class VoiceOutputService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // MARK: Singleton

    static let shared = VoiceOutputService()

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()

    /// Published so the HUD can animate while ARISE is speaking.
    @Published var isSpeaking: Bool = false

    // Sentence accumulation buffer for streaming input.
    private var tokenBuffer        = ""
    private let sentenceTerminators: CharacterSet = {
        var cs = CharacterSet()
        cs.insert(charactersIn: ".!?")
        return cs
    }()

    /// Preferred voice — deeper male Siri/enhanced voice for authority.
    private var preferredVoice: AVSpeechSynthesisVoice? {
        let candidates = [
            "com.apple.voice.enhanced.en-US.Evan",
            "com.apple.ttsbundle.siri_Aaron_en-US_compact",
            "com.apple.speech.synthesis.voice.Alex",
        ]
        for id in candidates {
            if let voice = AVSpeechSynthesisVoice(identifier: id) { return voice }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Settings Support

    private var isVoiceEnabled: Bool {
        if UserDefaults.standard.object(forKey: "isVoiceEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "isVoiceEnabled")
    }

    // MARK: - Init

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Full-text API

    /// Speak a complete message immediately, stopping any current speech.
    /// - Parameters:
    ///   - rate: 0.52 — slightly deliberate, authoritative.
    ///   - pitch: 0.85 — slightly lower than default.
    func speak(_ text: String, rate: Float = 0.52, pitch: Float = 0.85) {
        guard isVoiceEnabled else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        enqueue(text, rate: rate, pitch: pitch)
    }

    /// Stop any active speech immediately.
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        tokenBuffer = ""
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    // MARK: - Streaming API

    /// Feed a raw token chunk from Claude's streaming response.
    /// Sentences are detected and spoken as soon as they complete.
    func feedStreamToken(_ token: String, rate: Float = 0.52, pitch: Float = 0.85) {
        guard isVoiceEnabled else { return }
        tokenBuffer += token

        // Extract and speak any complete sentences from the buffer.
        while let sentence = extractNextSentence() {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            enqueue(trimmed, rate: rate, pitch: pitch)
        }
    }

    /// Call after streaming ends to speak any remaining partial sentence.
    func flushStreamBuffer(rate: Float = 0.52, pitch: Float = 0.85) {
        guard isVoiceEnabled else {
            tokenBuffer = ""
            return
        }
        let remainder = tokenBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenBuffer = ""
        guard !remainder.isEmpty else { return }
        enqueue(remainder, rate: rate, pitch: pitch)
    }

    // MARK: - Private Helpers

    private func enqueue(_ text: String, rate: Float, pitch: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice              = preferredVoice
        utterance.rate               = rate
        utterance.pitchMultiplier    = pitch
        utterance.volume             = 0.95
        utterance.preUtteranceDelay  = 0.05
        utterance.postUtteranceDelay = 0.08

        DispatchQueue.main.async { self.isSpeaking = true }
        synthesizer.speak(utterance)
    }

    /// Scans `tokenBuffer` for the first sentence-terminating character
    /// and returns the sentence (including the terminator), trimming the buffer.
    private func extractNextSentence() -> String? {
        // Find the first occurrence of a sentence-terminator.
        guard let range = tokenBuffer.rangeOfCharacter(from: sentenceTerminators) else {
            return nil
        }
        // Include the terminator character in the sentence.
        let endIndex = tokenBuffer.index(after: range.lowerBound)
        let sentence = String(tokenBuffer[tokenBuffer.startIndex..<endIndex])
        tokenBuffer  = String(tokenBuffer[endIndex...]).trimmingCharacters(in: .init(charactersIn: " "))
        return sentence
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        // Only mark as not-speaking if the queue is empty.
        if !synthesizer.isSpeaking {
            DispatchQueue.main.async { self.isSpeaking = false }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
