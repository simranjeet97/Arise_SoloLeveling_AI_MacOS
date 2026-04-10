import SwiftUI

// MARK: - QuestLogView

struct QuestLogView: View {

    @StateObject private var engine    = QuestEngine.shared
    @State private var filter:         QuestStatus = .active
    @State private var isGenerating                = false

    private var displayedQuests: [Quest] {
        switch filter {
        case .active:    return engine.activeQuests
        case .completed: return engine.completedQuests
        default:         return engine.activeQuests
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Filter chips
            filterBar
                .padding(.horizontal, Theme.spacingL)
                .padding(.bottom, 12)

            // ── System alert banner
            if !engine.lastSystemAlert.isEmpty {
                systemAlertBanner
                    .padding(.horizontal, Theme.spacingL)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── Quest list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if displayedQuests.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayedQuests) { quest in
                            QuestRowView(
                                quest:      quest,
                                onComplete: filter == .active ? { engine.completeQuest(quest) } : nil,
                                onAbandon:  filter == .active ? { engine.abandonQuest(quest) }  : nil
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal:   .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingL)
                .padding(.bottom, Theme.spacingL)
                .animation(.spring(response: 0.35, dampingFraction: 0.8),
                           value: displayedQuests.map(\.id))
            }

            // ── Generate button (only in Active tab)
            if filter == .active {
                generateButton
                    .padding(.horizontal, Theme.spacingL)
                    .padding(.bottom, Theme.spacingL)
            }
        }
        .animation(.spring(response: 0.3), value: engine.lastSystemAlert)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 2) {
            filterChip("Active",    .active,    count: engine.activeQuests.count)
            filterChip("Completed", .completed, count: engine.completedQuests.count)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderDim, lineWidth: 0.5))
        )
    }

    @ViewBuilder
    private func filterChip(_ label: String, _ value: QuestStatus, count: Int) -> some View {
        let active = filter == value
        Button { withAnimation { filter = value } } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(Theme.label(12, weight: .bold))
                Text("\(count)")
                    .font(Theme.mono(10, weight: .black))
                    .foregroundColor(active ? Theme.accentAmber : Theme.textDisabled)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accentAmber.opacity(active ? 0.15 : 0.05)))
            }
            .foregroundColor(active ? .white : Theme.textMuted)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if active {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.accentPurple.opacity(0.55), Theme.accentBlue.opacity(0.4)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.accentPurple.opacity(0.5), lineWidth: 0.5)
                            )
                            .padding(3)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - System Alert Banner

    private var systemAlertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(Theme.accentPurple)

            Text(engine.lastSystemAlert)
                .font(Theme.label(11))
                .foregroundColor(Theme.textMuted)
                .lineLimit(2)

            Spacer()

            Button {
                withAnimation { engine.lastSystemAlert = "" }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textDisabled)
                    .padding(5)
                    .background(Circle().fill(Theme.bgCard))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.accentPurple.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.borderGlow, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accentPurple.opacity(0.07))
                    .frame(width: 80, height: 80)
                Image(systemName: filter == .active ? "scroll" : "checkmark.seal")
                    .font(.system(size: 34))
                    .foregroundColor(Theme.accentPurple.opacity(0.35))
            }
            Text(filter == .active ? "No Active Quests" : "No Completed Quests")
                .font(Theme.rounded(17, weight: .bold))
                .foregroundColor(Theme.textMuted)
            if filter == .active {
                Text("Generate new quests below to begin your ascent.")
                    .font(Theme.label(12))
                    .foregroundColor(Theme.textDisabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        let busy = isGenerating || engine.isGenerating
        return Button {
            Task {
                isGenerating = true
                await engine.generateNewQuests()
                isGenerating = false
            }
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(busy ? "Summoning Quests…" : "Generate New Quests")
                    .font(Theme.label(14, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(busy
                          ? AnyShapeStyle(Theme.bgCard)
                          : AnyShapeStyle(Theme.gradientPurpleBlue))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.borderGlow, lineWidth: busy ? 0.5 : 0)
                    )
            )
            .shadow(color: busy ? .clear : Theme.accentPurple.opacity(0.55), radius: 14, y: 5)
            .scaleEffect(busy ? 0.98 : 1.0)
            .animation(.spring(response: 0.3), value: busy)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}
