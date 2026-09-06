import SwiftUI

/// Elegant watercolor / ink brush stroke shape with dynamic curve points
public struct BrushStrokeShape: Shape {
    var progress: CGFloat

    public var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width * max(progress, 0.001)
        
        path.move(to: CGPoint(x: 0, y: rect.height * 0.15))
        path.addCurve(
            to: CGPoint(x: width, y: rect.height * 0.35),
            control1: CGPoint(x: width * 0.35, y: rect.height * 0.02),
            control2: CGPoint(x: width * 0.75, y: rect.height * 0.50)
        )
        path.addLine(to: CGPoint(x: width, y: rect.height * 0.65))
        path.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.85),
            control1: CGPoint(x: width * 0.60, y: rect.height * 0.95),
            control2: CGPoint(x: width * 0.20, y: rect.height * 0.70)
        )
        path.closeSubpath()
        return path
    }
}

/// Floating ambient ink particle effect
public struct AtmosphericParticles: View {
    @State private var animate = false

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.4, green: 0.8, blue: 0.95).opacity(0.3), Color.clear],
                                center: UnitPoint.center, startRadius: 1, endRadius: 15
                            )
                        )
                        // NOTE(skip): `.random(in:)` bounds below used bare
                        // Int literals (and, for x/y, one bound that was
                        // already a CGFloat from `geo.size`). Swift
                        // auto-promotes Int literals to match a
                        // ClosedRange<CGFloat>/<Double> from context; Skip's
                        // Kotlin codegen doesn't, so it built an `IntRange`
                        // instead — explicit `.0` on every bound fixes it.
                        .frame(width: CGFloat.random(in: 8.0...24.0))
                        .position(
                            x: CGFloat.random(in: 0.0...geo.size.width),
                            y: animate ? CGFloat.random(in: 0.0...geo.size.height) : CGFloat.random(in: 0.0...geo.size.height)
                        )
                        .blur(radius: 2)
                        .animation(
                            Animation.easeInOut(duration: Double.random(in: 4.0...8.0))
                                .repeatForever(autoreverses: true),
                            value: animate
                        )
                }
            }
            .onAppear { animate = true }
        }
        .allowsHitTesting(false)
    }
}
