import SwiftUI

struct CharacterPoseView: View {
    let poseName: String
    var showConfetti = false
    @State private var floatOffset: CGFloat = 0
    @State private var breatheScale: CGFloat = 1

    private let pastelColors: [Color] = [
        Color(red: 1, green: 0.8, blue: 0.86),
        Color(red: 0.7, green: 0.85, blue: 1),
        Color(red: 0.75, green: 1, blue: 0.8),
        Color(red: 0.85, green: 0.75, blue: 1),
        Color(red: 1, green: 0.9, blue: 0.7),
        Color(red: 1, green: 0.78, blue: 0.7),
    ]

    var body: some View {
        ZStack {
            if showConfetti {
                ConfettiBurst(colors: pastelColors)
            }

            Image(poseName)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .scaleEffect(breatheScale)
                .offset(y: floatOffset)
                .shadow(
                    color: .black.opacity(0.15 - Double(floatOffset / 40) * 0.05),
                    radius: 8 + floatOffset * 0.5,
                    x: 0,
                    y: 4 + floatOffset * 0.5
                )
        }
        .frame(width: showConfetti ? 400 : 180, height: showConfetti ? 400 : 200)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -7
            }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                breatheScale = 1.03
            }
        }
    }
}

private enum ShapeType { case circle, capsule, diamond, rectangle, star }

private struct ConfettiBurst: View {
    let colors: [Color]

    private static let vividColors: [Color] = [
        Color(red: 1, green: 0.6, blue: 0.7),
        Color(red: 0.5, green: 0.75, blue: 1),
        Color(red: 0.5, green: 1, blue: 0.6),
        Color(red: 0.75, green: 0.5, blue: 1),
        Color(red: 1, green: 0.85, blue: 0.4),
        Color(red: 1, green: 0.65, blue: 0.5),
        Color(red: 0.4, green: 0.9, blue: 0.9),
        Color(red: 1, green: 0.4, blue: 0.6),
        Color(red: 0.9, green: 0.9, blue: 1),
        Color(red: 0.6, green: 1, blue: 0.9),
    ]

    private struct ConfettiPiece: Identifiable {
        let id = UUID()
        var color: Color
        var shape: ShapeType
        var angle: Double
        var distance: CGFloat
        var rotation: Double
        var delay: Double
        var size: CGFloat
        var isSecondary: Bool
    }

    @State private var pieces: [ConfettiPiece] = []

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                ConfettiShape(shape: piece.shape, size: piece.size)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * (piece.shape == .capsule ? 1.6 : 1.2))
                    .modifier(ConfettiAnimation(
                        angle: piece.angle,
                        distance: piece.distance,
                        rotation: piece.rotation,
                        delay: piece.delay,
                        isSecondary: piece.isSecondary
                    ))
            }
        }
        .onAppear {
            var generated: [ConfettiPiece] = []
            for i in 0..<80 {
                let color = Self.vividColors.randomElement() ?? colors[0]
                let shape: ShapeType = [.circle, .capsule, .diamond, .rectangle, .star].randomElement() ?? .circle
                let angle = Double.random(in: -180...(-10))
                let distance = CGFloat.random(in: 120...320)
                let rotation = Double.random(in: -1080...1080)
                let delay = Double(i) * 0.03
                let size = CGFloat.random(in: 7...18)
                let isSecondary = i >= 40
                generated.append(ConfettiPiece(color: color, shape: shape, angle: angle, distance: distance, rotation: rotation, delay: delay, size: size, isSecondary: isSecondary))
            }
            pieces = generated
        }
    }
}

private struct ConfettiShape: Shape {
    let shape: ShapeType
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .circle:
            return Circle().path(in: rect)
        case .capsule:
            return Capsule().path(in: rect)
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case .rectangle:
            return RoundedRectangle(cornerRadius: 2).path(in: rect)
        case .star:
            return starPath(in: rect)
        }
    }

    private func starPath(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX, cy = rect.midY
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.4
        var angle = -90.0
        let step = 360.0 / 5
        path.move(to: CGPoint(x: cx + outer * cos(angle * .pi / 180),
                               y: cy + outer * sin(angle * .pi / 180)))
        for _ in 0..<5 {
            angle += step
            path.addLine(to: CGPoint(x: cx + inner * cos(angle * .pi / 180),
                                      y: cy + inner * sin(angle * .pi / 180)))
            angle += step
            path.addLine(to: CGPoint(x: cx + outer * cos(angle * .pi / 180),
                                      y: cy + outer * sin(angle * .pi / 180)))
        }
        path.closeSubpath()
        return path
    }
}

private struct ConfettiAnimation: ViewModifier {
    var angle: Double
    var distance: CGFloat
    var rotation: Double
    var delay: Double
    var isSecondary: Bool

    @State private var isAnimating = false

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        let dx = cos(radians) * distance * (isAnimating ? 1 : 0)
        let dy = sin(radians) * distance * (isAnimating ? 1 : 0)

        return content
            .opacity(isAnimating ? 0 : 0.95)
            .scaleEffect(isAnimating ? 1.1 : 0.3)
            .offset(x: dx, y: dy)
            .rotationEffect(.degrees(isAnimating ? rotation : 0))
            .onAppear {
                let duration = isSecondary ? 1.4 : 0.9
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    isAnimating = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        CharacterPoseView(poseName: "Welcome")
        CharacterPoseView(poseName: "Celebrating", showConfetti: true)
    }
    .padding()
    .background(Color.oBackground)
}
