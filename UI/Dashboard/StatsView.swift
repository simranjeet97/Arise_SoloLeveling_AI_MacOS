import SwiftUI

// MARK: - StatsView

struct StatsView: View {

    @StateObject private var engine = QuestEngine.shared
    @State private var barsLoaded = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: stat cards list
            statCardsColumn
                .frame(maxWidth: 300)
                .padding(.horizontal, Theme.spacingL)

            // Vertical separator
            Rectangle()
                .fill(Theme.borderDim)
                .frame(width: 0.5)
                .padding(.vertical, Theme.spacingL)

            // Right: radar + rank + title
            radarColumn
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.spacingL)
        }
        .onAppear {
            // Stagger progress-bar animation in slightly after layout
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    barsLoaded = true
                }
            }
        }
    }

    // MARK: - Stat Cards Column

    private var statCardsColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                columnHeader("ATTRIBUTES", icon: "slider.horizontal.3")

                ForEach(StatKey.allCases, id: \.self) { stat in
                    StatCardView(
                        stat:     stat,
                        value:    engine.playerStats?[stat] ?? 10,
                        maxValue: 100
                    )
                    .opacity(barsLoaded ? 1 : 0)
                    .offset(x: barsLoaded ? 0 : -20)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.75)
                        .delay(Double(StatKey.allCases.firstIndex(of: stat)!) * 0.07),
                        value: barsLoaded
                    )
                }

                // XP progress bar
                xpProgressCard

                // Power Index card
                powerIndexCard

                Spacer(minLength: Theme.spacingL)
            }
            .padding(.top, Theme.spacingS)
            .padding(.bottom, Theme.spacingL)
        }
    }

    // MARK: - XP Progress Card

    private var xpProgressCard: some View {
        let stats = engine.playerStats
        let progress = stats?.levelProgress ?? 0
        let xp = stats?.xp ?? 0
        let xpNext = stats?.xpToNextLevel ?? 100
        let level = stats?.level ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("XP PROGRESS")
                    .font(Theme.mono(9, weight: .black))
                    .foregroundColor(Theme.textDisabled)
                Spacer()
                Text("Lv \(level)")
                    .font(Theme.mono(10, weight: .black))
                    .foregroundColor(Theme.accentBlue)
            }

            // Animated XP bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.accentBlue.opacity(0.12))
                        .frame(height: 8)

                    Capsule()
                        .fill(LinearGradient(
                            colors: [Theme.accentBlue.opacity(0.7), Theme.accentPurple],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(
                            width: barsLoaded ? geo.size.width * CGFloat(progress) : 0,
                            height: 8
                        )
                        .animation(.spring(response: 0.8, dampingFraction: 0.75), value: barsLoaded)
                        .animation(.spring(response: 0.6), value: progress)

                    // Glow
                    Capsule()
                        .fill(Theme.accentPurple.opacity(0.3))
                        .frame(
                            width: barsLoaded ? geo.size.width * CGFloat(progress) : 0,
                            height: 8
                        )
                        .blur(radius: 4)
                        .animation(.spring(response: 0.8, dampingFraction: 0.75), value: barsLoaded)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(xp) / \(xpNext) XP")
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textMuted)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: xp)
                Spacer()
                Text(String(format: "%.0f%%", progress * 100))
                    .font(Theme.mono(9, weight: .black))
                    .foregroundColor(Theme.accentPurple.opacity(0.8))
            }
        }
        .ariseCard()
    }

    // MARK: - Power Index Card

    private var powerIndexCard: some View {
        let pi = powerIndex
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("POWER INDEX")
                    .font(Theme.mono(9, weight: .black))
                    .foregroundColor(Theme.textDisabled)
                Text(String(format: "%.0f", pi))
                    .font(Theme.rounded(28, weight: .black))
                    .foregroundColor(Theme.accentAmber)
                    .shadow(color: Theme.accentAmber.opacity(0.5), radius: 8)
                    .contentTransition(.numericText())
            }
            Spacer()
            Image(systemName: "bolt.fill")
                .font(.system(size: 30))
                .foregroundColor(Theme.accentAmber.opacity(0.3))
        }
        .ariseCard()
    }

    private var powerIndex: Double {
        guard let s = engine.playerStats else { return 0 }
        return Double(s.strength + s.agility + s.stamina + s.intelligence + s.sense)
            * Double(s.level) / 5.0
    }

    // MARK: - Radar Column

    private var radarColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                columnHeader("HUNTER PROFILE", icon: "chart.radar.hexagon.fill")

                // Radar chart card
                ZStack {
                    ARISECardBackground(radius: 16)
                    RadarChartView(stats: engine.playerStats)
                        .frame(width: 260, height: 260)
                        .padding(20)
                }
                .frame(height: 300)

                // Rank badge + title
                rankAndTitleBadge

                Spacer(minLength: Theme.spacingL)
            }
            .padding(.top, Theme.spacingS)
            .padding(.bottom, Theme.spacingL)
        }
    }

    private func columnHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.accentPurple.opacity(0.7))
            Text(title)
                .font(Theme.mono(10, weight: .black))
                .foregroundColor(Theme.textDisabled)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Rank & Title Badge

    private var rankAndTitleBadge: some View {
        let rank  = currentRank
        let color = Theme.rankColor(rank)
        let titleStr = engine.playerStats?.title ?? "Awaiting Awakening"

        return VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(rank.rawValue)
                    .font(Theme.rounded(48, weight: .black))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.6), radius: 12)
                Text("RANK")
                    .font(Theme.mono(14, weight: .black))
                    .foregroundColor(color.opacity(0.7))
            }

            Text(titleStr)
                .font(Theme.mono(11, weight: .bold))
                .foregroundColor(color.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(color.opacity(0.15))
                        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
                )

            Text("Level \(engine.playerStats?.level ?? 1)")
                .font(Theme.label(11))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 28)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.35), lineWidth: 0.75))
        )
        .opacity(barsLoaded ? 1 : 0)
        .scaleEffect(barsLoaded ? 1 : 0.9)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.4), value: barsLoaded)
    }

    private var currentRank: QuestRank {
        switch engine.playerStats?.level ?? 1 {
        case ..<5:   return .E
        case ..<10:  return .D
        case ..<20:  return .C
        case ..<35:  return .B
        case ..<50:  return .A
        default:     return .S
        }
    }
}

// MARK: - RadarChartView

struct RadarChartView: View {
    let stats: PlayerStats?

    private let keys      = StatKey.allCases
    private let levels    = 5
    private let maxVal    = 100.0

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 * 0.78

            ZStack {
                // Grid rings
                Canvas { ctx, _ in
                    for lvl in 1...levels {
                        let r = radius * CGFloat(lvl) / CGFloat(levels)
                        var p = Path()
                        for (i, _) in keys.enumerated() {
                            let pt = polarPoint(center: center, radius: r, index: i, count: keys.count)
                            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                        }
                        p.closeSubpath()
                        ctx.stroke(p, with: .color(Theme.borderDim), lineWidth: 0.5)
                    }
                    // Spokes
                    for (i, _) in keys.enumerated() {
                        let pt = polarPoint(center: center, radius: radius, index: i, count: keys.count)
                        var p = Path()
                        p.move(to: center); p.addLine(to: pt)
                        ctx.stroke(p, with: .color(Theme.borderDim), lineWidth: 0.5)
                    }
                }

                // Stat fill
                if let s = stats {
                    Canvas { ctx, _ in
                        var fill = Path()
                        for (i, key) in keys.enumerated() {
                            let val = min(s[key] / maxVal, 1.3)
                            let pt  = polarPoint(center: center, radius: radius * CGFloat(val), index: i, count: keys.count)
                            i == 0 ? fill.move(to: pt) : fill.addLine(to: pt)
                        }
                        fill.closeSubpath()
                        ctx.fill(fill, with: .color(Theme.accentPurple.opacity(0.2)))
                        ctx.stroke(fill, with: .linearGradient(
                            Gradient(colors: [Theme.accentPurple, Theme.accentBlue]),
                            startPoint: .zero, endPoint: CGPoint(x: geo.size.width, y: geo.size.height)
                        ), lineWidth: 2)
                    }
                }

                // Labels
                ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                    let pt = polarPoint(center: center, radius: radius + 20, index: i, count: keys.count)
                    Text(key.rawValue)
                        .font(Theme.mono(10, weight: .black))
                        .foregroundColor(Theme.statColor(key).opacity(0.9))
                        .position(pt)
                }
            }
        }
    }

    private func polarPoint(center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
        let angle = CGFloat(index) * (2 * .pi / CGFloat(count)) - .pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}
