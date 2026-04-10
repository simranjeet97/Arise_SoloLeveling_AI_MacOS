import SwiftUI

// MARK: - JournalView

struct JournalView: View {

    let onDismiss: () -> Void

    @State private var transcript: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var result: JournalEntry? = nil
    
    @ObservedObject private var voice = VoiceOutputService.shared
    @ObservedObject private var whisper = WhisperService.shared

    var body: some View {
        ZStack {
            VisualEffectView.hudDark.ignoresSafeArea()
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("SHADOW DUNGEON")
                        .font(Theme.mono(16, weight: .black))
                        .foregroundColor(Theme.textDisabled)
                        .tracking(4)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textDisabled)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
                .padding(.top, 24)

                if isAnalyzing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("ARISE is interpreting your shadow...")
                            .font(Theme.mono(12))
                            .foregroundColor(Theme.accentPurple.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let result = result {
                    // Result State
                    resultView(result)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    // Input State
                    inputView
                        .transition(.opacity)
                }
            }
        }
        .onDisappear {
            whisper.stopRecording()
        }
    }

    // MARK: - Input State

    private var inputView: some View {
        VStack(spacing: 20) {
            
            Text("Enter your feelings to ground your mind in the System.")
                .font(Theme.label(14))
                .foregroundColor(Theme.textMuted)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderDim, lineWidth: 1))

                TextEditor(text: $transcript)
                    .font(Theme.label(16))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 150)
                
                if transcript.isEmpty {
                    Text("Tell ARISE how you feel today...")
                        .font(Theme.label(16))
                        .foregroundColor(Theme.textDisabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 30)
            
            HStack(spacing: 12) {
                // Whisper Mic Button
                Button(action: toggleMic) {
                    Image(systemName: whisper.audioLevel > 0.05 ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: 18))
                        .foregroundColor(whisper.audioLevel > 0.05 ? Theme.accentRed : Theme.textPrimary)
                        .padding(14)
                        .background(Circle().fill(Theme.bgCard).shadow(color: Theme.accentRed.opacity(whisper.audioLevel > 0.05 ? 0.5 : 0), radius: 10))
                }
                .buttonStyle(.plain)
                
                // Submit Button
                Button(action: analyze) {
                    Text("Enter the Shadow Dungeon")
                        .font(Theme.mono(14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AnyShapeStyle(Theme.gradientPurpleBlue))
                                .shadow(color: Theme.accentPurple.opacity(0.4), radius: 10, y: 3)
                        )
                }
                .buttonStyle(.plain)
                .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Result State

    private func resultView(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            
            HStack {
                Text(entry.emotion.capitalized)
                    .font(Theme.mono(18, weight: .black))
                    .foregroundColor(Theme.accentBlue)
                Spacer()
                Text("Intensity: \(entry.intensity)/10")
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundColor(Theme.accentAmber)
            }
            .padding(.bottom, 10)

            // Split the combined summary
            let parts = entry.claudeSummary.components(separatedBy: "\n\n")
            
            if parts.indices.contains(0) {
                resultBlock(title: "ACKNOWLEDGMENT", content: parts[0])
            }
            if parts.indices.contains(1) {
                resultBlock(title: "REFRAMING QUESTION", content: parts[1])
            }
            if parts.indices.contains(2) {
                resultBlock(title: "MICRO-ACTION", content: parts[2])
            }

            Spacer()
            
            Button("Done") {
                onDismiss()
            }
            .font(Theme.mono(14, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bgCard))
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 30)
        .onAppear {
            let msg = entry.claudeSummary.components(separatedBy: "\n\n").first ?? "Shadow recorded."
            voice.speak(msg)
        }
    }

    private func resultBlock(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.mono(10, weight: .black))
                .foregroundColor(Theme.textDisabled)
            Text(content)
                .font(Theme.label(15))
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func toggleMic() {
        if whisper.audioLevel > 0 { // proxy for recording state natively
            Task {
                if let text = try? await whisper.stopAndTranscribe() {
                    transcript += (transcript.isEmpty ? "" : " ") + text
                }
            }
        } else {
            whisper.startRecording()
        }
    }

    private func analyze() {
        whisper.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isAnalyzing = true
        Task {
            do {
                let entry = try await EmotionalAnalysisService.shared.analyzeAndSaveJournal(transcript: transcript)
                await MainActor.run {
                    self.result = entry
                    self.isAnalyzing = false
                }
            } catch {
                print("Shadow dungeon error: \(error)")
                await MainActor.run { isAnalyzing = false }
            }
        }
    }
}
