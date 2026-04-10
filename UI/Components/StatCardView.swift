import SwiftUI

// MARK: - StatCardView

/// Displays a single RPG stat with an animated progress bar and subtle glow.
struct StatCardView: View {

    let stat:       StatKey
    let value:      Double
    let maxValue:   Double      // soft cap for the bar (typically 100)

    @State private var appear = false
    @State private var hovered = false

    private var progress: Double { min(value / max(maxValue, 1), 1.0) }
    private var color: Color { Theme.statColor(stat) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            progressBar
            bottomRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .onHover { over in withAnimation { hovered = over } }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double.random(in: 0...0.3))) {
                appear = true
            }
        }
    }

    // MARK: - Subviews

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline) {
            // Stat glyph
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text(statEmoji)
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(stat.rawValue)
                    .font(Theme.mono(10, weight: .black))
                    .foregroundColor(color)
                Text(stat.displayName)
                    .font(Theme.label(9))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            Text(String(format: "%.0f", value))
                .font(Theme.rounded(22, weight: .black))
                .foregroundColor(Theme.textPrimary)
                .shadow(color: color.opacity(0.5), radius: 6)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: value)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(color.opacity(0.12))
                    .frame(height: 6)

                // Fill
                Capsule()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.7), color],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: appear ? geo.size.width * CGFloat(progress) : 0, height: 6)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: appear)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75), value: progress)

                // Glow overlay on the filled portion
                Capsule()
                    .fill(color.opacity(0.25))
                    .frame(width: appear ? geo.size.width * CGFloat(progress) : 0, height: 6)
                    .blur(radius: 3)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: appear)
            }
        }
        .frame(height: 6)
    }

    private var bottomRow: some View {
        HStack {
            Text("\(Int(value * 10 / maxValue))% of cap")
                .font(Theme.mono(8))
                .foregroundColor(Theme.textDisabled)
            Spacer()
            // Mini sparkline-style tick marks
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(i) < (progress * 5) ? color.opacity(0.8) : color.opacity(0.12))
                        .frame(width: 5, height: 10)
                }
            }
        }
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        ZStack {
            ARISECardBackground(radius: Theme.radiusCard)

            // Hover: subtle inner glow in stat colour
            if hovered {
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .stroke(color.opacity(0.4), lineWidth: 0.75)
                    .blendMode(.screen)
            }
        }
    }

    // MARK: - Helpers

    private var statEmoji: String {
        switch stat {
        case .strength:     return "⚔️"
        case .agility:      return "💨"
        case .stamina:      return "🛡️"
        case .intelligence: return "🧠"
        case .sense:        return "👁️"
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
struct StatCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            ForEach(StatKey.allCases, id: \.self) { stat in
                StatCardView(stat: stat, value: Double.random(in: 10...80), maxValue: 100)
            }
        }
        .padding()
        .frame(width: 260)
        .background(Theme.bgPrimary)
    }
}
#endif
