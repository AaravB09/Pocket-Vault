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
                angle: Double(i) * (.pi * 2 / 24) + Double.random(in: -0.15...0.15),
                distance: 0,
                scale: 1.0,
                opacity: 1.0,
                rotation: Double.random(in: 0...360)
            )
        }

        withAnimation(.easeOut(duration: 0.9)) {
            for i in particles.indices {
                particles[i].distance = CGFloat.random(in: 90...160)
                particles[i].opacity = 0
                particles[i].scale = 0.3
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isActive = false
            particles = []
        }
    }
}
