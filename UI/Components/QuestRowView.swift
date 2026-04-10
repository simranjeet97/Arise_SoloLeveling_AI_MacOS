import SwiftUI

// MARK: - QuestRowView

/// A single compact quest row for use in lists and the menu bar popover.
/// Shows rank badge • title + reward • right-side status indicator.
struct QuestRowView: View {

    let quest:      Quest
    var onComplete: (() -> Void)? = nil
    var onAbandon:  (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var isHovered  = false
    @State private var completePulse = false

    // Flash & Float XP State
    @State private var flashOpacity: Double = 0
    @State private var xpFloatOffset: Double = 0
    @State private var xpFloatOpacity: Double = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isExpanded { detailPanel.transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .background(rowBackground)
        .overlay(floatingXPOverlay)
        .onHover { over in withAnimation(.easeInOut(duration: 0.15)) { isHovered = over } }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 10) {
            rankBadge
            centerInfo
            Spacer(minLength: 6)
            rightIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { isExpanded.toggle() } }
    }

    // MARK: - Rank Badge

    private var rankBadge: some View {
        let color = Theme.rankColor(quest.rank)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.6), lineWidth: 0.75)
                )
                .frame(width: 30, height: 30)

            Text(quest.rank.rawValue)
                .font(Theme.mono(13, weight: .black))
                .foregroundColor(color)
        }
        .shadow(color: color.opacity(0.4), radius: quest.rank == .S ? 8 : 0)
    }

    // MARK: - Center Info

    private var centerInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(quest.title)
                .font(Theme.label(12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(isExpanded ? nil : 1)

            HStack(spacing: 5) {
                Text(quest.domain.emoji)
                    .font(.system(size: 10))
                Text(quest.domain.displayName)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textMuted)

                let streak = QuestEngine.shared.currentStreak(for: quest.domain)
                if streak > 1 {
                    Text("🔥 ×\(streak)")
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundColor(Theme.accentAmber)
                }

                if !quest.statRewards.isEmpty {
                    Circle()
                        .fill(Theme.textDisabled)
                        .frame(width: 2, height: 2)
                    Text(quest.statRewards.map { $0.key.prefix(3).uppercased() + " +\($0.value)" }.joined(separator: ", "))
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.accentAmber.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Right Indicator

    @ViewBuilder
    private var rightIndicator: some View {
        switch quest.status {
        case .active:
            VStack(alignment: .trailing, spacing: 2) {
                Text("⚡ " + String(Int(quest.totalXPReward)))
                    .font(Theme.mono(9, weight: .bold))
                    .foregroundColor(Theme.accentAmber.opacity(0.9))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }
        case .completed:
            ZStack {
                Circle()
                    .fill(Theme.accentGreen.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.accentGreen)
            }
            .scaleEffect(completePulse ? 1.15 : 1.0)
            .onAppear {
                withAnimation(.spring(response: 0.4).delay(0.1)) { completePulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.3)) { completePulse = false }
                }
            }
        case .failed, .abandoned, .pending:
            Image(systemName: "xmark.circle")
                .font(.system(size: 14))
                .foregroundColor(Theme.accentRed.opacity(0.6))
        }
    }

    // MARK: - Detail Panel (Expanded)

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .background(Theme.borderGlow)
                .padding(.horizontal, 12)

            Text(quest.description)
                .font(Theme.label(11))
                .foregroundColor(Theme.textMuted)
                .lineSpacing(3)
                .padding(.horizontal, 12)

            if let complete = onComplete, let abandon = onAbandon {
                HStack(spacing: 8) {
                    // Complete
                    Button {
                        // Flash Row Background
                        withAnimation(.easeOut(duration: 0.15)) {
                            flashOpacity = 1.0
                            xpFloatOpacity = 1.0
                        }
                        // Float XP text up
                        withAnimation(.easeOut(duration: 0.8)) {
                            xpFloatOffset = -40
                        }
                        // Fade out flash
                        withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                            flashOpacity = 0.0
                        }
                        // Fade out XP text
                        withAnimation(.easeIn(duration: 0.3).delay(0.5)) {
                            xpFloatOpacity = 0.0
                        }
                        
                        // Fire callback after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            complete()
                        }
                    } label: {
                        Label("Complete", systemImage: "checkmark.seal.fill")
                            .font(Theme.label(11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.accentGreen)
                            )
                    }
                    .buttonStyle(.plain)

                    // Abandon
                    Button(action: abandon) {
                        Label("Abandon", systemImage: "xmark")
                            .font(Theme.label(11, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderDim))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 0).frame(height: 4)
        }
    }

    // MARK: - Row Background

    private var rowBackground: some View {
        ZStack {
            ARISECardBackground(radius: Theme.radiusCard)

            if isHovered {
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .fill(Theme.accentPurple.opacity(0.06))
            }

            // Flash overlay
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .fill(Theme.accentPurple.opacity(0.3))
                .opacity(flashOpacity)
        }
    }

    // MARK: - Floating XP
    
    private var floatingXPOverlay: some View {
        HStack {
            Spacer()
            Text("+\(Int(quest.totalXPReward)) XP")
                .font(Theme.mono(16, weight: .black))
                .foregroundColor(Theme.accentPurple)
                .shadow(color: Theme.accentPurple.opacity(0.8), radius: 8)
                .padding(.trailing, 20)
                .offset(y: xpFloatOffset)
                .opacity(xpFloatOpacity)
        }
        .allowsHitTesting(false)
    }
}
