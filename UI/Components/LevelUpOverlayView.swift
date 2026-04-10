import SwiftUI

// MARK: - LevelUpOverlayView

/// Solo Leveling inspired full-screen "LEVEL UP" overlay.
/// Features a dark pulsating background with upward-flowing energy particles
/// and bold, stylized typography. Automatically dismisses itself after 4 seconds.
struct LevelUpOverlayView: View {

    let level: Int
    let title: String
    let onDismiss: () -> Void

    @State private var phase: Double = 0
    @State private var appear = false
    @State private var glowOpacity = 0.0

    // MARK: - Particle System

    struct Particle: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var size: Double
        var opacity: Double
    }

    @State private var particles: [Particle] = []

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background dimming
            Color.black.opacity(appear ? 0.8 : 0)
                .ignoresSafeArea()

            // Energy Particles
            Canvas { context, size in
                for p in particles {
                    context.opacity = p.opacity
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x * size.width, y: p.y * size.height, width: p.size, height: p.size)),
                        with: .color(Theme.accentPurple)
                    )
                }
            }
            .ignoresSafeArea()
            .opacity(appear ? 1 : 0)

            // Center Content
            VStack(spacing: 12) {
                Text("LEVEL UP")
                    .font(Theme.rounded(64, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Theme.accentPurple.opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Theme.accentPurple.opacity(0.8), radius: 20)
                    .shadow(color: .white.opacity(0.5), radius: 5)
                    .tracking(8)
                    .scaleEffect(appear ? 1.0 : 0.8)
                    .opacity(appear ? 1.0 : 0.0)

                VStack(spacing: 4) {
                    Text("Level \(level)")
                        .font(Theme.mono(24, weight: .bold))
                        .foregroundColor(Theme.accentBlue)

                    Text(title.uppercased())
                        .font(Theme.mono(14, weight: .black))
                        .foregroundColor(Theme.textPrimary)
                        .tracking(4)
                }
                .opacity(glowOpacity)
                .offset(y: glowOpacity > 0 ? 0 : 20)
            }
        }
        // Dismiss entirely when tapped
        .onTapGesture { dismiss() }
        .onAppear {
            setupParticles()

            // 1. Enter animation
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                appear = true
            }

            // 2. Fade in subtext
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                glowOpacity = 1.0
            }

            // 3. Drive particles
            Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
                guard appear else {
                    timer.invalidate()
                    return
                }
                updateParticles()
            }

            // 4. Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { dismiss() }

            // 5. Voice
            VoiceOutputService.shared.speak("Your power grows, Player. Level \(level) achieved.")
        }
    }

    private func dismiss() {
        guard appear else { return }
        withAnimation(.easeOut(duration: 0.5)) {
            appear = false
            glowOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onDismiss()
        }
    }

    // MARK: - Particle Logic

    private func setupParticles() {
        particles = (0..<40).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.005...0.02)
            return Particle(
                x: 0.5,
                y: 0.5,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                size: Double.random(in: 4...10),
                opacity: Double.random(in: 0.5...1.0)
            )
        }
    }

    private func updateParticles() {
        for i in particles.indices {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            
            // Fade out over 1.5s (90 ticks at 60fps -> slightly faster)
            particles[i].opacity -= 0.015
            if particles[i].opacity < 0 { particles[i].opacity = 0 }
        }
    }
}
