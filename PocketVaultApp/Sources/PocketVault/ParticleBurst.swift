import SwiftUI

/// Gold particle burst fired on successful deposit. Self-dismissing —
/// just toggle `isActive` to true and it plays once and resets.
struct ParticleBurstView: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var isActive: Bool

    private struct Particle: Identifiable {
        let id = UUID()
        var angle: Double
        var distance: CGFloat
        var scale: CGFloat
        var opacity: Double
        var rotation: Double
    }

    @State private var particles: [Particle] = []

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Image(systemName: ["diamond.fill", "sparkle", "circle.fill"].randomElement()!)
                    .font(theme.font(10))
                    .foregroundStyle(theme.accent)
                    .scaleEffect(particle.scale)
                    .opacity(particle.opacity)
                    .rotationEffect(.degrees(particle.rotation))
                    .offset(
                        x: CGFloat(cos(particle.angle)) * particle.distance,
                        y: CGFloat(sin(particle.angle)) * particle.distance
                    )
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            guard active else { return }
            fire()
        }
    }

    private func fire() {
        particles = (0..<24).map { i in
            Particle(
                angle: Double(i) * (Double.pi * 2.0 / 24.0) + Double.random(in: -0.15...0.15),
                distance: 0.0,
                scale: 1.0,
                opacity: 1.0,
                // NOTE(skip): bare `0...360` here is an integer-literal
                // range. Swift infers it as ClosedRange<Double> from the
                // `Double.random(in:)` parameter type, but Skip's Kotlin
                // codegen doesn't apply that contextual inference — it
                // emits an IntRange, which doesn't match the
                // ClosedFloatingPointRange<Double> random(in:) expects.
                // Spelling out the Double literals fixes it on both
                // platforms.
                rotation: Double.random(in: 0.0...360.0)
            )
        }

        withAnimation(.easeOut(duration: 0.9)) {
            for i in particles.indices {
                // NOTE(skip): same bare-Int-range issue as `rotation`
                // above, here against CGFloat.random(in:).
                particles[i].distance = CGFloat.random(in: 90.0...160.0)
                particles[i].opacity = 0.0
                particles[i].scale = 0.3
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isActive = false
            particles = []
        }
    }
}
