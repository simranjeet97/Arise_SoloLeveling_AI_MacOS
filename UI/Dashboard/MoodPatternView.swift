import SwiftUI

// MARK: - MoodPatternView

struct MoodPatternView: View {

    @State private var entries: [JournalEntry] = []
    @State private var summary: String = ""
    @State private var isSummarizing: Bool = false

    private let db = DatabaseService.shared
    private let claude = ClaudeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header
            HStack {
                Text("SHADOW PATTERNS")
                    .font(Theme.mono(14, weight: .black))
                    .foregroundColor(Theme.textDisabled)
                    .tracking(2)
                Spacer()
                Button(action: fetchData) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            // Timeline
            if entries.isEmpty {
                Text("Your shadow is quiet. Enter the Shadow Dungeon to record your mind.")
                    .font(Theme.label(12))
                    .foregroundColor(Theme.textMuted)
                    .italic()
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entries) { entry in
                            VStack(spacing: 6) {
                                Capsule()
                                    .fill(colorForEmotion(entry.emotion))
                                    .frame(width: 12, height: CGFloat(40 + (entry.intensity * 4)))
                                    .animation(.spring(response: 0.4), value: entries.count)
                                
                                Text(dayString(for: entry.date))
                                    .font(Theme.mono(8))
                                    .foregroundColor(Theme.textMuted)
                            }
                            // Tooltip for macOS
                            .help("\(entry.emotion.capitalized): \(entry.intensity)/10\n\(entry.rawTranscript)")
                        }
                    }
                    .padding(.bottom, 8)
                }
            }

            // Summary Panel
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderDim, lineWidth: 1))

                if isSummarizing {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("ARISE is analyzing 30-day patterns...")
                            .font(Theme.mono(10))
                            .foregroundColor(Theme.accentPurple.opacity(0.8))
                    }
                    .padding(20)
                } else if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("30-DAY REFLECTION")
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                        Text(summary)
                            .font(Theme.label(12))
                            .foregroundColor(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                } else {
                    Text("Complete more shadow entries to generate a 30-day pattern analysis.")
                        .font(Theme.label(12))
                        .foregroundColor(Theme.textDisabled)
                        .italic()
                        .padding(20)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .onAppear {
            fetchData()
        }
    }

    // MARK: - Data Tasks

    private func fetchData() {
        do {
            let allEntries = try db.fetchJournalEntries(limit: 30) // last 30
            // Reverse so oldest is on left, newest on right
            entries = allEntries.reversed()
            
            if !entries.isEmpty && summary.isEmpty {
                generateSummary()
            }
        } catch {
            print("[MoodPatternView] Error fetching patterns: \(error)")
        }
    }

    private func generateSummary() {
        guard !isSummarizing else { return }
        isSummarizing = true

        let recentContext = entries.suffix(10).map { 
            "Date: \(dayString(for: $0.date)) | Emotion: \($0.emotion) (\($0.intensity)/10) | Notes: \($0.rawTranscript)"
        }.joined(separator: "\n")

        let prompt = """
        You are ARISE — the System. Analyze the last 30 days of the player's shadow patterns.
        Here is the recent context:
        \(recentContext)

        Write a 1-paragraph summary identifying their emotional trend (e.g. rising stress, consistent joy, volatile anxiety) and provide one piece of System-level advice to stabilize or enhance their mental state going into next month. Speak strictly as the System. Under 80 words.
        """

        Task {
            do {
                let response = try await claude.sendMessage(prompt)
                await MainActor.run {
                    self.summary = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.isSummarizing = false
                }
            } catch {
                await MainActor.run { isSummarizing = false }
            }
        }
    }

    // MARK: - Helpers

    private func colorForEmotion(_ emotion: String) -> Color {
        switch emotion.lowercased() {
        case "joy": return Theme.accentBlue // Teal equivalent in our Theme
        case "stress": return Theme.accentAmber
        case "anxiety": return Theme.accentPurple
        case "sadness": return Color(nsColor: .systemBlue)
        case "anger": return Theme.accentRed
        default: return Theme.textDisabled
        }
    }

    private func dayString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d/M"
        return fmt.string(from: date)
    }
}
