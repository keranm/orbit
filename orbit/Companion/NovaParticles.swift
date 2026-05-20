import SwiftUI

/// Orbital satellite dots rendered via TimelineView for smooth circular motion.
/// Each dot orbits the centre at equal angular spacing.
struct NovaParticles: View {
    let orbitRadius: CGFloat
    let count: Int
    let dotSize: CGFloat
    let color: Color
    let opacity: Double
    let duration: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let progress = elapsed.truncatingRemainder(dividingBy: duration) / duration
                let baseAngle = progress * 2.0 * .pi

                for i in 0..<count {
                    let phase = (2.0 * .pi / Double(count)) * Double(i)
                    let angle = baseAngle + phase
                    let x = cx + CGFloat(cos(angle)) * orbitRadius - dotSize / 2
                    let y = cy + CGFloat(sin(angle)) * orbitRadius - dotSize / 2
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
        }
    }
}
