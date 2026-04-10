import SwiftUI

// MARK: - MenuBarView

/// Compact frosted-glass popover anchored to the menu-bar "waveform" icon.
struct MenuBarView: View {

    let onOpenDashboard: () -> Void
    let onStartVoice:    () -> Void

    @StateObject  private var engine  = QuestEngine.shared
    @State private var hovered: String? = nil

    // MARK: - Body

    var body: some View {
        ZStack {
            // Frosted blur background
            VisualEffectView.hudDark
                .ignoresSafeArea()

            // Dark navy overlay + grid
            ARISEWindowBackground()

            // Content
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                separator

                statsRow
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                separator

                questList
                    .padding(.horizontal, 14)

                Spacer(minLength: 0)

                actionButtons
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 340, height: 490)
        .onAppear { engine.loadFromDatabase() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // XP ring
            xpRing
            // Player info
            VStack(alignment: .leading, spacing: 3) {
                Text(engine.playerStats?.title ?? "Awaiting Awakening")
                    .font(Theme.rounded(15, weight: .black))
                    .foregroundColor(Theme.textPrimary)

                Text("Shadow Monarch's Chosen")
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.accentPurple.opacity(0.75))

                xpBar
            }
        }
        .padding(.bottom, 12)
    }

    private var xpRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.accentPurple.opacity(0.2), lineWidth: 5)
                .frame(width: 60, height: 60)

            Circle()
                .trim(from: 0, to: CGFloat(engine.playerStats?.levelProgress ?? 0))
                .stroke(
                    AngularGradient(
                        colors: [Theme.accentPurple, Theme.accentBlue, Theme.accentPurple],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
                .animation(.spring(response: 0.6), value: engine.playerStats?.levelProgress)

            VStack(spacing: 0) {
                Text("LVL")
                    .font(Theme.mono(7, weight: .black))
                    .foregroundColor(Theme.accentPurple.opacity(0.8))
                Text("\(engine.playerStats?.level ?? 1)")
                    .font(Theme.rounded(20, weight: .black))
                    .foregroundColor(.white)
            }
        }
        .purpleGlow(radius: 10, opacity: 0.4)
    }

    private var xpBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accentPurple.opacity(0.12)).frame(height: 4)
                Capsule()
                    .fill(Theme.gradientPurpleBlue)
                    .frame(width: geo.size.width * CGFloat(engine.playerStats?.levelProgress ?? 0), height: 4)
                    .animation(.spring(response: 0.5), value: engine.playerStats?.levelProgress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Separator

    private var separator: some View {
        Rectangle()
            .fill(Theme.borderGlow)
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 6) {
            ForEach(StatKey.allCases, id: \.self) { stat in
                miniStatBadge(stat: stat)
            }
        }
    }

    private func miniStatBadge(stat: StatKey) -> some View {
        let value = engine.playerStats?[stat] ?? 0
        let color = Theme.statColor(stat)
        return VStack(spacing: 3) {
            Text(stat.rawValue)
                .font(Theme.mono(8, weight: .black))
                .foregroundColor(color.opacity(0.9))
            Text(String(format: "%.0f", value))
                .font(Theme.rounded(13, weight: .black))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 0.5))
        )
    }

    // MARK: - Quest List

    private var questList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ACTIVE QUESTS")
                    .font(Theme.mono(9, weight: .black))
                    .foregroundColor(Theme.textDisabled)
                Spacer()
                Text("\(engine.activeQuests.count)")
                    .font(Theme.mono(9, weight: .bold))
                    .foregroundColor(Theme.accentBlue.opacity(0.8))
            }
            .padding(.top, 10)

            if engine.activeQuests.isEmpty {
                Text("No active quests. Open Dashboard to generate.")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.textDisabled)
                    .italic()
                    .padding(.vertical, 10)
            } else {
                ForEach(engine.activeQuests.prefix(3)) { quest in
                    miniQuestRow(quest: quest)
                }
            }
        }
    }

    private func miniQuestRow(quest: Quest) -> some View {
        HStack(spacing: 9) {
            // Rank pill
            Text(quest.rank.rawValue)
                .font(Theme.mono(10, weight: .black))
                .foregroundColor(Theme.rankColor(quest.rank))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.rankColor(quest.rank).opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(quest.title)
                    .font(Theme.label(11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(quest.domain.emoji) \(quest.domain.rawValue)")
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            Text("⚡\(Int(quest.totalXPReward))")
                .font(Theme.mono(9, weight: .bold))
                .foregroundColor(Theme.accentAmber.opacity(0.85))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderDim, lineWidth: 0.4))
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            menuActionButton(label: "waveform", title: "Speak",     id: "voice", action: onStartVoice)
            menuActionButton(label: "scroll",   title: "Dashboard", id: "dash",  action: onOpenDashboard)
        }
        .padding(.top, 10)
    }

    private func menuActionButton(label: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        let isHov = hovered == id
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: label)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Theme.label(12, weight: .bold))
            }
            .foregroundColor(isHov ? .white : Theme.textMuted)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHov
                          ? AnyShapeStyle(Theme.gradientPurpleBlue)
                          : AnyShapeStyle(Theme.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderGlow, lineWidth: 0.5))
            )
            .shadow(color: isHov ? Theme.accentPurple.opacity(0.4) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.easeInOut(duration: 0.15)) { hovered = over ? id : nil } }
    }
}
