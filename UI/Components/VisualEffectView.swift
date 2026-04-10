import SwiftUI
import AppKit

// MARK: - VisualEffectView

/// Wraps `NSVisualEffectView` so SwiftUI views can use native macOS vibrancy/blur materials.
struct VisualEffectView: NSViewRepresentable {

    var material:     NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material     = material
        view.blendingMode = blendingMode
        view.state        = .active
        view.isEmphasized = isEmphasized
        view.wantsLayer   = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material     = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = isEmphasized
    }
}

// MARK: - Convenience Presets

extension VisualEffectView {

    /// Dark HUD-style frosted blur — the primary ARISE panel material.
    static var hudDark: VisualEffectView {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
    }

    /// Slightly lighter "under-window" blur for card surfaces.
    static var popoverPanel: VisualEffectView {
        VisualEffectView(material: .popover, blendingMode: .behindWindow)
    }

    /// Ultra-thin material for lighter overlays.
    static var ultraThin: VisualEffectView {
        VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
    }
}

// MARK: - ARISEWindowBackground

/// The root background layered under every ARISE window:
///   NSVisualEffectView (blur) → dark tinted overlay → subtle grid.
struct ARISEWindowBackground: View {

    var body: some View {
        ZStack {
            // Layer 1: native frosted blur
            VisualEffectView.hudDark
                .ignoresSafeArea()

            // Layer 2: deep navy tint
            Theme.bgPrimary
                .ignoresSafeArea()

            // Layer 3: faint hexagonal/grid texture
            GridOverlay()
                .ignoresSafeArea()
        }
    }
}

// MARK: - Grid Overlay

private struct GridOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 44
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(Theme.accentPurple.opacity(0.06)), lineWidth: 0.5)
        }
    }
}

// MARK: - ARISECardBackground

/// Standard semi-transparent card background used throughout the app.
struct ARISECardBackground: View {
    var radius: CGFloat = Theme.radiusCard
    var body: some View {
        ZStack {
            VisualEffectView(material: .menu, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: radius))
            RoundedRectangle(cornerRadius: radius)
                .fill(Theme.gradientCard)
            RoundedRectangle(cornerRadius: radius)
                .stroke(Theme.borderGlow, lineWidth: 0.5)
        }
    }
}
