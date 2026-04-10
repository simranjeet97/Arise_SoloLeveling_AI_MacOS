import SwiftUI
import AppKit
import AVFoundation

// MARK: - VoiceHUDView

/// Floating pill-shaped overlay that drives the full ARISE voice pipeline:
///   ⌥Space → record → Whisper STT → Claude stream → TTS sentence-by-sentence
///
/// Target: < 1.5 s from end of speech to first word.
struct VoiceHUDView: View {

    /// When `true`, recording starts automatically on `.onAppear`.
    /// Set by the AppDelegate when opening via the menu bar item
    /// so the user doesn't need an extra tap.
    let autoStart: Bool
    let onDismiss: () -> Void

    init(autoStart: Bool = false, onDismiss: @escaping () -> Void) {
        self.autoStart = autoStart
        self.onDismiss = onDismiss
    }

    @ObservedObject private var whisper = WhisperService.shared
    @ObservedObject private var voice   = VoiceOutputService.shared

    // MARK: - Pipeline State

    enum PipelineStage {
        case idle
        case listening           // Recording + silence detection
        case transcribing        // Whisper in flight
        case thinking            // Claude in flight (before first token)
        case speaking            // TTS active
    }

    @State private var stage:           PipelineStage = .idle
    @State private var transcribedText: String        = ""
    @State private var ariseResponse:   String        = ""
    @State private var pipelineError:   String?       = nil
    @State private var responseTask:    Task<Void, Never>?
    /// Set when Claude triggers a web_search tool call — shown in the HUD.
    @State private var researchingQuery: String?      = nil

    // Silence detection
    @State private var silenceTimer:    Timer? = nil
    private let silenceThreshold: Float = 0.02   // RMS below this = silence
    private let silenceDuration: Double = 1.2    // seconds before auto-stop

    // Animation
    @State private var phase:           CGFloat = 0
    @State private var appear                   = false
    @State private var waveTimer:       Timer?  = nil

    // Global hotkey monitor
    @State private var hotkeyMonitor:   Any?    = nil

    // Auto-dismiss after speaking ends
    @State private var dismissTimer:    Timer?  = nil

    // MARK: - Computed State

    private var hudState: HUDState {
        switch stage {
        case .idle:         return .idle
        case .listening:    return .userSpeaking
        case .transcribing: return .processing
        case .thinking:     return .processing
        case .speaking:     return .systemSpeaking
        }
    }

    enum HUDState {
        case idle, userSpeaking, processing, systemSpeaking

        var barColor: Color {
            switch self {
            case .idle:          return Theme.textDisabled
            case .userSpeaking:  return Theme.accentBlue
            case .processing:    return Theme.accentBlue.opacity(0.6)
            case .systemSpeaking: return Theme.accentPurple
            }
        }

        var glowColor: Color {
            switch self {
            case .idle:          return .clear
            case .userSpeaking:  return Theme.accentBlue.opacity(0.4)
            case .processing:    return Theme.accentBlue.opacity(0.25)
            case .systemSpeaking: return Theme.accentPurple.opacity(0.5)
            }
        }

        var statusLabel: String {
            switch self {
            case .idle:          return "⌥SPACE TO SPEAK"
            case .userSpeaking:  return "LISTENING…"
            case .processing:    return "ARISE PROCESSING…"
            case .systemSpeaking: return "ARISE SPEAKING"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            pillContent
        }
        .frame(width: 400)
        .background(hudBackground)
        .shadow(color: hudState.glowColor, radius: 28, x: 0, y: 0)
        .scaleEffect(appear ? 1 : 0.88)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { appear = true }
            startWaveTimer()
            registerGlobalHotkey()
            // If opened by the menu bar, begin listening immediately.
            if autoStart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startListening()
                }
            }
        }
        .onDisappear {
            waveTimer?.invalidate()
            teardown()
        }
        .onChange(of: whisper.audioLevel) { level in
            guard stage == .listening else { return }
            handleAudioLevel(level)
        }
        .onChange(of: voice.isSpeaking) { speaking in
            if !speaking && stage == .speaking {
                scheduleDismiss()
            }
        }
    }

    // MARK: - Pill Content

    private var pillContent: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 14)

            waveformRow
                .padding(.horizontal, 20)
                .padding(.top, 12)

            textArea
                .padding(.horizontal, 20)
                .padding(.top, 8)

            controlRow
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Pulsing status dot
            ZStack {
                Circle()
                    .fill(hudState == .idle ? Theme.textDisabled : hudState.barColor)
                    .frame(width: 7, height: 7)

                if hudState != .idle {
                    Circle()
                        .stroke(hudState.barColor.opacity(0.4), lineWidth: 4)
                        .frame(width: 7, height: 7)
                        .scaleEffect(1.8)
                        .opacity(0)
                        .animation(
                            .easeOut(duration: 0.9).repeatForever(autoreverses: false),
                            value: hudState.statusLabel
                        )
                }
            }

            Text(hudState.statusLabel)
                .font(Theme.mono(9, weight: .black))
                .foregroundColor(hudState == .idle ? Theme.textDisabled : hudState.barColor)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textMuted)
                    .padding(6)
                    .background(Circle().fill(Theme.bgCard))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Waveform

    private var waveformRow: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                WaveBar(
                    index: i,
                    phase: phase,
                    level: barLevel,
                    color: hudState.barColor,
                    maxH:  44
                )
            }
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
    }

    private var barLevel: CGFloat {
        switch stage {
        case .idle:         return 0.08
        case .listening:    return CGFloat(whisper.audioLevel)
        case .transcribing: return 0.3
        case .thinking:     return 0.4
        case .speaking:     return 0.6
        }
    }

    // MARK: - Text Area

    private var textArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.borderDim, lineWidth: 0.5)
                )

            Group {
                if let err = pipelineError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(Theme.label(10))
                        .foregroundColor(Theme.accentRed.opacity(0.85))
                } else if !ariseResponse.isEmpty {
                    ScrollView {
                        Text(ariseResponse)
                            .font(Theme.label(11))
                            .foregroundColor(Theme.accentPurple.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 72)
                } else if let query = researchingQuery, !query.isEmpty {
                    // Show web search query in muted italic while Claude researches
                    VStack(spacing: 4) {
                        if !transcribedText.isEmpty {
                            Text(transcribedText)
                                .font(Theme.label(10))
                                .foregroundColor(Theme.textMuted)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.accentBlue.opacity(0.7))
                            Text("Researching: \(query)\u{2026}")
                                .font(Theme.label(10))
                                .foregroundColor(Theme.textMuted)
                                .italic()
                                .lineLimit(2)
                        }
                    }
                } else if !transcribedText.isEmpty {
                    Text(transcribedText)
                        .font(Theme.label(11))
                        .foregroundColor(Theme.textPrimary)
                } else {
                    Text(idleHint)
                        .font(Theme.label(10))
                        .foregroundColor(Theme.textMuted)
                        .italic()
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(minHeight: 54)
    }

    private var idleHint: String {
        switch stage {
        case .idle:         return "Press ⌥Space or tap Record to speak."
        case .transcribing: return "Transcribing…"
        case .thinking:     return "ARISE is thinking…"
        default:            return "Shadow journal is ready."
        }
    }

    // MARK: - Control Row

    private var controlRow: some View {
        HStack(spacing: 10) {
            // Mic toggle
            Button {
                handleMicButton()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: micIcon)
                        .font(.system(size: 13, weight: .bold))
                    Text(micLabel)
                        .font(Theme.label(12, weight: .bold))
                }
                .foregroundColor(stage == .listening ? .white : .black)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(stage == .listening
                              ? AnyShapeStyle(Theme.accentRed)
                              : AnyShapeStyle(Theme.gradientPurpleBlue))
                )
                .shadow(
                    color: (stage == .listening ? Theme.accentRed : Theme.accentPurple).opacity(0.5),
                    radius: 10, y: 3
                )
            }
            .buttonStyle(.plain)
            .disabled(stage == .transcribing || stage == .thinking)

            // Silence ARISE
            if voice.isSpeaking {
                Button {
                    voice.stopSpeaking()
                    stage = .idle
                    dismissTimer?.invalidate()
                } label: {
                    Label("Silence", systemImage: "speaker.slash")
                        .font(Theme.label(12, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Theme.borderGlow)
                                )
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.3), value: voice.isSpeaking)
    }

    private var micIcon: String {
        stage == .listening ? "stop.fill" : "waveform"
    }
    private var micLabel: String {
        stage == .listening ? "Stop" : "Record"
    }

    // MARK: - Pipeline Logic

    private func handleMicButton() {
        switch stage {
        case .listening:
            stopListeningAndProcess()
        default:
            startListening()
        }
    }

    private func startListening() {
        guard stage == .idle else { return }
        pipelineError   = nil
        transcribedText = ""
        ariseResponse   = ""
        stage           = .listening
        silenceTimer?.invalidate()
        whisper.startRecording()
        print("[ARISE] 🎙 Recording started")
    }

    private func stopListeningAndProcess() {
        guard stage == .listening else { return }
        silenceTimer?.invalidate()
        stage = .transcribing
        print("[ARISE] ⏹ Recording stopped — transcribing…")

        responseTask?.cancel()
        responseTask = Task {
            await runPipeline()
        }
    }

    /// Full pipeline: STT → Claude stream (with optional web search) → TTS.
    private func runPipeline() async {
        // 1. Transcribe
        let transcript: String
        do {
            transcript = try await whisper.stopAndTranscribe()
        } catch {
            await setError("STT Error: \(error.localizedDescription)")
            return
        }

        await MainActor.run {
            transcribedText  = transcript
            researchingQuery = nil
            stage            = .thinking
        }
        print("[ARISE] 📝 Transcript: \(transcript)")

        // 2. Fetch player context from DB (best-effort)
        let stats  = await DatabaseService.shared.fetchPlayerStatsAsync()
        let quests = await DatabaseService.shared.fetchActiveQuestsAsync()

        // 3. Check for quest completion intent FIRST
        let completed = await QuestEngine.shared.completeQuestByVoiceIntent(transcript: transcript)
        if completed {
            await MainActor.run {
                stage = .speaking // It's speaking now
            }
            return
        }

        // 4. Stream Claude response — with web_search enabled
        await MainActor.run { ariseResponse = "" }

        // Use the full event stream so web_search queries surface in the HUD.
        let stream = GeminiService.shared.streamEvents(
            transcript,
            stats:        stats,
            quests:       quests,
            useWebSearch: true
        )

        var firstToken = true
        do {
            for try await event in stream {
                if Task.isCancelled { break }

                switch event {
                case .webSearchQuery(let query):
                    // Surface the search query in the HUD text area
                    await MainActor.run {
                        researchingQuery = query
                    }
                    print("[ARISE] 🔍 Web search: \(query)")

                case .token(let token):
                    if firstToken {
                        firstToken = false
                        await MainActor.run {
                            stage            = .speaking
                            researchingQuery = nil   // clear search label once text starts
                        }
                        print("[ARISE] 🟣 First token received — speaking")
                    }
                    await MainActor.run {
                        ariseResponse += token
                    }
                    // Feed to TTS on main actor
                    await MainActor.run {
                        VoiceOutputService.shared.feedStreamToken(token)
                    }
                }
            }
            // Flush remaining partial sentence
            await MainActor.run {
                VoiceOutputService.shared.flushStreamBuffer()
            }
            print("[ARISE] ✅ Stream complete. Response:\n\(ariseResponse)")
        } catch {
            await setError("Claude Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Silence Detection

    private func handleAudioLevel(_ level: Float) {
        if level > silenceThreshold {
            // Sound detected — reset timer
            silenceTimer?.invalidate()
            silenceTimer = nil
        } else if silenceTimer == nil {
            // Start silence countdown
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration,
                                                repeats: false) { _ in
                DispatchQueue.main.async {
                    guard self.stage == .listening else { return }
                    print("[ARISE] 🔇 Silence detected — auto-stopping")
                    self.stopListeningAndProcess()
                }
            }
        }
    }

    // MARK: - Auto-Dismiss

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async {
                guard self.stage == .speaking && !VoiceOutputService.shared.isSpeaking else { return }
                print("[ARISE] 🏁 Pipeline complete — hiding HUD")
                self.stage = .idle
                // Uncomment to auto-dismiss the HUD window:
                // self.onDismiss()
            }
        }
    }

    // MARK: - Global Hotkey (⌥Space)

    private func registerGlobalHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // keyCode 49 = Space; modifierFlags check for Option only
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            else { return }

            DispatchQueue.main.async {
                switch self.stage {
                case .idle:      self.startListening()
                case .listening: self.stopListeningAndProcess()
                default:         break
                }
            }
        }
    }

    // MARK: - Teardown

    private func teardown() {
        waveTimer?.invalidate()
        silenceTimer?.invalidate()
        dismissTimer?.invalidate()
        responseTask?.cancel()
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hotkeyMonitor = nil
        whisper.stopRecording()
    }

    // MARK: - Helpers

    @MainActor
    private func setError(_ msg: String) {
        pipelineError = msg
        stage         = .idle
        print("[ARISE] ❌ \(msg)")
    }

    // MARK: - Background

    private var hudBackground: some View {
        ZStack {
            VisualEffectView.hudDark
                .clipShape(RoundedRectangle(cornerRadius: 20))
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.bgPrimary)
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Theme.accentPurple.opacity(0.55), Theme.accentBlue.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
    }

    // MARK: - Wave Timer

    private func startWaveTimer() {
        waveTimer?.invalidate()
        waveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            // @State mutations MUST happen on the main thread.
            DispatchQueue.main.async { phase += 0.07 }
        }
    }
}

// MARK: - WaveBar

private struct WaveBar: View {
    let index: Int
    let phase: CGFloat
    let level: CGFloat
    let color: Color
    let maxH:  CGFloat

    private var height: CGFloat {
        let wave = sin(phase + CGFloat(index) * 0.9) * 0.5 + 0.5
        let base: CGFloat = 4
        return base + (maxH - base) * wave * level
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.55), color],
                    startPoint: .bottom, endPoint: .top
                )
            )
            .frame(width: 7, height: max(4, height))
            .shadow(color: color.opacity(level > 0.1 ? 0.5 : 0), radius: 4)
            .animation(.easeInOut(duration: 0.05), value: height)
    }
}

// MARK: - DatabaseService async helpers (pipeline convenience)

extension DatabaseService {
    /// Fetch the current player stats off the main thread (async wrapper).
    func fetchPlayerStatsAsync() async -> PlayerStats? {
        await Task.detached(priority: .userInitiated) {
            try? self.fetchPlayerStats()
        }.value ?? nil
    }

    /// Fetch active quests off the main thread (async wrapper).
    func fetchActiveQuestsAsync() async -> [Quest] {
        await Task.detached(priority: .userInitiated) {
            (try? self.fetchActiveQuests()) ?? []
        }.value
    }
}
