import SwiftUI
import AppKit

// MARK: - ARISE Design Tokens

/// Single source of truth for every colour, shadow, radius, and spacing used in ARISE.
enum Theme {

    // ──────────────────────────────────────────────
    // MARK: Colours
    // ──────────────────────────────────────────────

    /// Deep navy — primary window / panel background (translucent).
    static let bgPrimary   = Color(hex: "0A0A14").opacity(0.88)
    /// Card / secondary surface (slightly lighter translucent panel).
    static let bgCard      = Color(hex: "12122A").opacity(0.75)
    /// Elevated surface (modal, popover).
    static let bgElevated  = Color(hex: "1A1A3A").opacity(0.80)

    /// Solo Leveling signature purple/violet.
    static let accentPurple = Color(hex: "7F77DD")
    /// Holographic blue — used for info, secondary accents.
    static let accentBlue   = Color(hex: "378ADD")
    /// XP / gold / warning amber.
    static let accentAmber  = Color(hex: "EF9F27")
    /// Danger / recording red.
    static let accentRed    = Color(hex: "E0445B")
    /// Success / completion green.
    static let accentGreen  = Color(hex: "3ED98A")

    /// Primary text — pure white.
    static let textPrimary  = Color.white
    /// Secondary / muted text.
    static let textMuted    = Color.white.opacity(0.55)
    /// Disabled text.
    static let textDisabled = Color.white.opacity(0.25)

    /// Subtle purple glow border used on cards and panels.
    static let borderGlow   = Color(hex: "7F77DD").opacity(0.35)
    /// Dimmer border for less prominent elements.
    static let borderDim    = Color(hex: "7F77DD").opacity(0.15)

    // ──────────────────────────────────────────────
    // MARK: Gradients
    // ──────────────────────────────────────────────

    static let gradientPurpleBlue = LinearGradient(
        colors: [accentPurple, accentBlue],
        startPoint: .leading, endPoint: .trailing
    )

    static let gradientBackground = LinearGradient(
        colors: [Color(hex: "08080F"), Color(hex: "0C0A1E"), Color(hex: "0F0D2C")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let gradientCard = LinearGradient(
        colors: [Color(hex: "14142E").opacity(0.80), Color(hex: "0E0E22").opacity(0.75)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // ──────────────────────────────────────────────
    // MARK: Shadows
    // ──────────────────────────────────────────────

    static let shadowGlow   = Shadow(color: accentPurple.opacity(0.45), radius: 18, x: 0, y: 6)
    static let shadowCard   = Shadow(color: Color.black.opacity(0.55),  radius: 12, x: 0, y: 4)
    static let shadowButton = Shadow(color: accentPurple.opacity(0.60), radius: 14, x: 0, y: 4)

    // ──────────────────────────────────────────────
    // MARK: Radii
    // ──────────────────────────────────────────────

    static let radiusWindow: CGFloat = 16
    static let radiusCard:   CGFloat = 12
    static let radiusTag:    CGFloat = 6
    static let radiusPill:   CGFloat = 999

    // ──────────────────────────────────────────────
    // MARK: Spacing
    // ──────────────────────────────────────────────

    static let spacingXS: CGFloat = 4
    static let spacingS:  CGFloat = 8
    static let spacingM:  CGFloat = 14
    static let spacingL:  CGFloat = 20
    static let spacingXL: CGFloat = 28

    // ──────────────────────────────────────────────
    // MARK: Typography helpers
    // ──────────────────────────────────────────────

    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // ──────────────────────────────────────────────
    // MARK: Rank Colours
    // ──────────────────────────────────────────────

    static func rankColor(_ rank: QuestRank) -> Color {
        switch rank {
        case .E: return Color(hex: "8A8A9A")   // grey
        case .D: return Color(hex: "3ED98A")   // green
        case .C: return Color(hex: "378ADD")   // blue
        case .B: return Color(hex: "7F77DD")   // purple
        case .A: return Color(hex: "EF9F27")   // gold
        case .S: return Color(hex: "E8C73A")   // bright gold / legendary
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Stat Colours
    // ──────────────────────────────────────────────

    static func statColor(_ stat: StatKey) -> Color {
        switch stat {
        case .strength:      return Color(hex: "FF5C7A")
        case .agility:       return Color(hex: "5CEAFF")
        case .stamina:       return Color(hex: "3ED98A")
        case .intelligence:  return Color(hex: "7F77DD")
        case .sense:         return Color(hex: "EF9F27")
        }
    }
}

// ──────────────────────────────────────────────
// MARK: - Shadow Helper

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// ──────────────────────────────────────────────
// MARK: - View Modifiers

extension View {
    /// Applies the standard ARISE card style.
    func ariseCard(radius: CGFloat = Theme.radiusCard, padding: CGFloat = Theme.spacingM) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Theme.gradientCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(Theme.borderGlow, lineWidth: 0.5)
                    )
            )
            .shadow(color: Theme.shadowCard.color, radius: Theme.shadowCard.radius,
                    x: Theme.shadowCard.x, y: Theme.shadowCard.y)
    }

    /// Adds the signature purple glow shadow.
    func purpleGlow(radius: CGFloat = 14, opacity: Double = 0.45) -> some View {
        self.shadow(color: Theme.accentPurple.opacity(opacity), radius: radius, x: 0, y: 0)
    }

    /// Applies the ARISE primary gradient button look.
    func gradientButtonStyle(radius: CGFloat = 11) -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Theme.gradientPurpleBlue)
            )
            .shadow(color: Theme.shadowButton.color, radius: Theme.shadowButton.radius,
                    x: Theme.shadowButton.x, y: Theme.shadowButton.y)
    }
}

// ──────────────────────────────────────────────
// MARK: - Hex Color Extension (shared)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:(r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}
