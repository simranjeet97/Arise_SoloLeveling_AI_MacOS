import SwiftUI

// MARK: - DashboardView

/// Main ARISE window — transparent, frameless, frosted-glass Solo Leveling aesthetic.
struct DashboardView: View {

    @StateObject private var engine = QuestEngine.shared
    @State private var selectedTab: DashboardTab = .quests
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    enum DashboardTab: String, CaseIterable {
        case quests  = "Quest Log"
        case stats   = "Stats"
        case journal = "Journal"

        var icon: String {
            switch self {
            case .quests:  return "scroll.fill"
            case .stats:   return "chart.radar.hexagon.fill"
            case .journal: return "moon.stars.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .quests:  return Theme.accentPurple
            case .stats:   return Theme.accentBlue
            case .journal: return Theme.accentAmber
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                // ── Layer 0: frosted glass + navy tint + grid
                ARISEWindowBackground()

                // ── Content
                VStack(spacing: 0) {
                    headerBar
                        .padding(.horizontal, Theme.spacingL)
                        .padding(.top, 18)
                        .padding(.bottom, 14)

                    tabBar
                        .padding(.horizontal, Theme.spacingL)
                        .padding(.bottom, 14)

                    // Tab content — full remaining height
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // ── Level Up Overlay
                if let levelUp = engine.pendingLevelUp {
                    LevelUpOverlayView(
                        level: levelUp.level,
                        title: levelUp.title,
                        onDismiss: { engine.pendingLevelUp = nil }
                    )
                    // Transitions and animations are handled by LevelUpOverlayView internally
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .onAppear { engine.loadFromDatabase() }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            // Logo mark
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accentPurple.opacity(0.35), Theme.accentBlue.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.borderGlow, lineWidth: 0.75)
                    )

                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accentPurple, Theme.accentBlue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .purpleGlow(radius: 12, opacity: 0.6)

            VStack(alignment: .leading, spacing: 2) {
                Text("ARISE")
                    .font(Theme.rounded(26, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Theme.accentPurple.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .shadow(color: Theme.accentPurple.opacity(0.4), radius: 8)

                Text("Shadow Monarch's System v0.1")
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            // Settings & Hunter chip
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .ariseNotificationTapped, object: "settingsView")
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textMuted)
                        .padding(8)
                        .background(Circle().fill(Theme.bgCard))
                }
                .buttonStyle(.plain)

                if let stats = engine.playerStats {
                    hunterChip(stats: stats)
                }
            }
        }
    }

    private func hunterChip(stats: PlayerStats) -> some View {
        HStack(spacing: 14) {
            // XP ring
            ZStack {
                Circle()
                    .stroke(Theme.accentPurple.opacity(0.2), lineWidth: 3.5)
                    .frame(width: 42, height: 42)
                Circle()
                    .trim(from: 0, to: CGFloat(stats.levelProgress))
                    .stroke(
                        AngularGradient(
                            colors: [Theme.accentPurple, Theme.accentBlue, Theme.accentPurple],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 42, height: 42)
                    .animation(.spring(response: 0.6), value: stats.levelProgress)

                Text("\(stats.level)")
                    .font(Theme.rounded(16, weight: .black))
                    .foregroundColor(.white)
            }
            .purpleGlow(radius: 8, opacity: 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text("LEVEL \(stats.level)")
                    .font(Theme.mono(11, weight: .black))
                    .foregroundColor(Theme.accentPurple)
                Text("⚡ \(stats.xp) XP")
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.accentAmber.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(ARISECardBackground(radius: 12))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderDim, lineWidth: 0.5))
        )
    }

    private func tabButton(_ tab: DashboardTab) -> some View {
        let isActive = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(tab.rawValue)
                    .font(Theme.label(13, weight: .semibold))
            }
            .foregroundColor(isActive ? .white : Theme.textMuted)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(
                                LinearGradient(
                                    colors: [tab.accentColor.opacity(0.55), Theme.accentBlue.opacity(0.4)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(tab.accentColor.opacity(0.5), lineWidth: 0.75)
                            )
                            .shadow(color: tab.accentColor.opacity(0.35), radius: 8, y: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isActive)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .quests:
            QuestLogView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))

        case .stats:
            StatsView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))

        case .journal:
            journalView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
        }
    }

    // MARK: - Journal Tab

    private var journalView: some View {
        VStack(spacing: 0) {
            MoodPatternView()
                .padding(.top, 10)
            
            // Enter Dungeon Button
            Button {
                NotificationCenter.default.post(name: .ariseNotificationTapped, object: "journalView")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                    Text("Enter the Shadow Dungeon")
                        .font(Theme.mono(13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AnyShapeStyle(Theme.gradientPurpleBlue))
                        .shadow(color: Theme.accentPurple.opacity(0.4), radius: 10, y: 3)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
