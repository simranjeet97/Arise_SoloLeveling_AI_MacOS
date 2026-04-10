import SwiftUI
import AppKit

// MARK: - LearningDungeonView

/// Full-panel Learning Dungeon UI.
///
/// Shows:
///   1. Research summary with web sources (from Claude + web_search)
///   2. Three quiz questions with A–D choices
///   3. Mastery progress bar for this topic
///   4. XP award on completion
struct LearningDungeonView: View {

    let topic: String
    let onDismiss: () -> Void

    // MARK: - State

    @StateObject private var service = DungeonService.shared

    @State private var dungeon:        LearningDungeon?  = nil
    @State private var isLoading:      Bool              = true
    @State private var loadError:      String?           = nil

    // Quiz state
    @State private var selectedAnswers: [String: String] = [:]  // questionID → chosen option
    @State private var submitted:       Bool             = false
    @State private var correctCount:    Int              = 0
    @State private var xpAwarded:       Int              = 0

    // Mastery
    @State private var mastery: DungeonMastery? = nil

    // Animation
    @State private var appear = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Holographic background
            Theme.gradientBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Group {
                    if isLoading {
                        loadingView
                    } else if let err = loadError {
                        errorView(message: err)
                    } else if let dungeon {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 20) {
                                summaryCard(dungeon: dungeon)
                                sourcesCard(sources: dungeon.sources)
                                quizSection(questions: dungeon.questions)
                                masteryCard
                                if submitted {
                                    resultsBanner
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .scaleEffect(appear ? 1 : 0.95)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) { appear = true }
            Task { await loadDungeon() }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Dungeon icon
            ZStack {
                Circle()
                    .fill(Theme.accentPurple.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.accentPurple)
            }
            .purpleGlow(radius: 8, opacity: 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text("LEARNING DUNGEON")
                    .font(Theme.mono(9, weight: .black))
                    .foregroundColor(Theme.accentPurple.opacity(0.8))
                    .tracking(2)
                Text(topic)
                    .font(Theme.label(16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Mastery badge
            if let m = mastery {
                masteryBadge(percent: m.masteryPercent)
            }

            // Dismiss
            Button(action: onDismiss) {
                ZStack {
                    Circle()
                        .fill(Theme.bgCard)
                        .frame(width: 30, height: 30)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.borderGlow, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.3)
                .tint(Theme.accentPurple)

            if let q = service.researchingQuery {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.accentBlue)
                    Text("Researching: \(q)…")
                        .font(Theme.label(12))
                        .foregroundColor(Theme.textMuted)
                        .italic()
                }
                .transition(.opacity)
                .animation(.easeInOut, value: q)
            } else {
                Text("ARISE is searching the web…")
                    .font(Theme.label(13))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(Theme.accentRed)
            Text("Dungeon Breach")
                .font(Theme.label(15, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(message)
                .font(Theme.label(11))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 40)
            Button("Retry") {
                loadError = nil
                isLoading = true
                Task { await loadDungeon() }
            }
            .gradientButtonStyle()
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .font(Theme.label(13, weight: .bold))
            Spacer()
        }
    }

    // MARK: - Summary Card

    private func summaryCard(dungeon: LearningDungeon) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "scroll.fill", title: "ARISE SYNTHESIS", color: Theme.accentPurple)

            Text(dungeon.summary)
                .font(Theme.label(13))
                .foregroundColor(Theme.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ariseCard()
    }

    // MARK: - Sources Card

    private func sourcesCard(sources: [LearningDungeon.Source]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "link.circle.fill", title: "WEB SOURCES", color: Theme.accentBlue)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sources.indices, id: \.self) { i in
                    let s = sources[i]
                    Button {
                        if let url = URL(string: s.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(i + 1)")
                                .font(Theme.mono(9, weight: .black))
                                .foregroundColor(Theme.accentBlue)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Theme.accentBlue.opacity(0.15)))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title)
                                    .font(Theme.label(11, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(s.url)
                                    .font(Theme.label(9))
                                    .foregroundColor(Theme.accentBlue.opacity(0.75))
                                    .lineLimit(1)
                            }

                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textDisabled)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .ariseCard()
    }

    // MARK: - Quiz Section

    private func quizSection(questions: [LearningDungeon.Question]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "questionmark.circle.fill", title: "DUNGEON TRIAL", color: Theme.accentAmber)

            ForEach(Array(questions.enumerated()), id: \.element.id) { idx, q in
                questionCard(question: q, number: idx + 1)
            }

            if !submitted {
                let allAnswered = questions.allSatisfy { selectedAnswers[$0.id] != nil }
                Button {
                    submitQuiz(questions: questions)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("SUBMIT TRIAL")
                            .font(Theme.label(13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(allAnswered
                                  ? AnyShapeStyle(Theme.gradientPurpleBlue)
                                  : AnyShapeStyle(Theme.bgCard))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(allAnswered ? Color.clear : Theme.borderDim, lineWidth: 0.5)
                    )
                    .shadow(color: allAnswered ? Theme.accentPurple.opacity(0.4) : .clear, radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(!allAnswered)
                .animation(.spring(response: 0.3), value: allAnswered)
            }
        }
        .ariseCard()
    }

    private func questionCard(question: LearningDungeon.Question, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("Q\(number)")
                    .font(Theme.mono(9, weight: .black))
                    .foregroundColor(Theme.accentAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Theme.accentAmber.opacity(0.15))
                    )
                Text(question.prompt)
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 5) {
                ForEach(question.options, id: \.self) { option in
                    optionButton(option: option, question: question)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.bgPrimary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.borderDim, lineWidth: 0.5)
                )
        )
    }

    private func optionButton(option: String, question: LearningDungeon.Question) -> some View {
        let selected  = selectedAnswers[question.id] == option
        let isCorrect = option == question.answer
        let reveal    = submitted

        let bgColor: AnyShapeStyle = {
            if !reveal {
                return selected ? AnyShapeStyle(Theme.accentPurple.opacity(0.25)) : AnyShapeStyle(Color.clear)
            }
            if isCorrect { return AnyShapeStyle(Theme.accentGreen.opacity(0.2)) }
            if selected  { return AnyShapeStyle(Theme.accentRed.opacity(0.18)) }
            return AnyShapeStyle(Color.clear)
        }()

        let borderColor: Color = {
            if !reveal {
                return selected ? Theme.accentPurple.opacity(0.6) : Theme.borderDim
            }
            if isCorrect { return Theme.accentGreen.opacity(0.7) }
            if selected  { return Theme.accentRed.opacity(0.5) }
            return Theme.borderDim
        }()

        let textColor: Color = {
            if !reveal { return selected ? Theme.textPrimary : Theme.textMuted }
            if isCorrect { return Theme.accentGreen }
            if selected  { return Theme.accentRed }
            return Theme.textDisabled
        }()

        return Button {
            guard !submitted else { return }
            selectedAnswers[question.id] = option
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(borderColor, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    if selected || (reveal && isCorrect) {
                        Circle()
                            .fill(reveal ? (isCorrect ? Theme.accentGreen : Theme.accentRed) : Theme.accentPurple)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(option)
                    .font(Theme.label(11))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                // Answer indicator after submit
                if reveal && isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accentGreen)
                        .font(.system(size: 11))
                } else if reveal && selected && !isCorrect {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.accentRed)
                        .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(borderColor, lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
        .animation(.easeInOut(duration: 0.18), value: submitted)
    }

    // MARK: - Mastery Card

    private var masteryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "chart.bar.fill", title: "MASTERY PROGRESS", color: Theme.accentGreen)

            let pct = mastery?.masteryPercent ?? 0
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(topic)
                        .font(Theme.label(12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%%", pct))
                        .font(Theme.mono(11, weight: .black))
                        .foregroundColor(masteryColor(pct))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.borderDim)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [Theme.accentGreen.opacity(0.8), Theme.accentBlue],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(pct / 100), height: 6)
                            .animation(.spring(response: 0.6, dampingFraction: 0.75), value: pct)
                            .shadow(color: Theme.accentGreen.opacity(0.4), radius: 4)
                    }
                }
                .frame(height: 6)

                if let m = mastery, m.totalXPEarned > 0 {
                    Text("Total XP earned from this dungeon: \(m.totalXPEarned)")
                        .font(Theme.label(10))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
        .ariseCard()
    }

    // MARK: - Results Banner

    private var resultsBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: correctCount == (dungeon?.questions.count ?? 0)
                      ? "crown.fill" : "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.accentAmber)

                VStack(alignment: .leading, spacing: 3) {
                    Text(resultTitle)
                        .font(Theme.label(14, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Quest Complete. +\(xpAwarded) XP awarded. INT +\(correctCount * 2).")
                        .font(Theme.label(11))
                        .foregroundColor(Theme.accentAmber)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.accentAmber.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.accentAmber.opacity(0.4), lineWidth: 0.75)
                )
        )
        .shadow(color: Theme.accentAmber.opacity(0.25), radius: 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var resultTitle: String {
        let q = dungeon?.questions.count ?? 3
        switch correctCount {
        case q:      return "Shadow Dungeon Cleared! Perfect mastery."
        case q - 1:  return "Dungeon Conquered. Near-perfect."
        case 1:      return "A start. The dungeon weakened you."
        default:     return "Dungeon Complete. Review the gaps."
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(Theme.mono(9, weight: .black))
                .foregroundColor(color.opacity(0.9))
                .tracking(1.5)
        }
    }

    private func masteryBadge(percent: Double) -> some View {
        Text(String(format: "%.0f%%", percent))
            .font(Theme.mono(10, weight: .black))
            .foregroundColor(masteryColor(percent))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(masteryColor(percent).opacity(0.15))
                    .overlay(Capsule().stroke(masteryColor(percent).opacity(0.4), lineWidth: 0.5))
            )
    }

    private func masteryColor(_ pct: Double) -> Color {
        switch pct {
        case 80...: return Theme.accentGreen
        case 50...: return Theme.accentBlue
        case 20...: return Theme.accentAmber
        default:    return Theme.accentRed
        }
    }

    // MARK: - Logic

    private func loadDungeon() async {
        isLoading = true
        defer { isLoading = false }

        dungeon = await DungeonService.shared.enterLearningDungeon(topic: topic)
        mastery = DungeonService.shared.fetchMastery(for: topic)

        if dungeon == nil && loadError == nil {
            loadError = "ARISE could not complete the research. Check your API key or network."
        }
    }

    private func submitQuiz(questions: [LearningDungeon.Question]) {
        correctCount = questions.filter { selectedAnswers[$0.id] == $0.answer }.count
        let base     = correctCount * LearningDungeon.xpPerCorrectAnswer
        let bonus    = correctCount == questions.count ? LearningDungeon.perfectScoreBonus : 0
        xpAwarded    = base + bonus

        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            submitted = true
        }

        DungeonService.shared.recordQuizResult(
            topic:          topic,
            correctAnswers: correctCount,
            outOf:          questions.count
        )
        mastery = DungeonService.shared.fetchMastery(for: topic)

        // Speak the result
        let total   = questions.count
        let message = "Quest Complete. +\(xpAwarded) XP awarded. You answered \(correctCount) of \(total) correctly."
        VoiceOutputService.shared.speak(message)
    }
}
