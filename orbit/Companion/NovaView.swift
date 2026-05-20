import SwiftUI

// MARK: - Public API

/// Nova — Orbit's ambient companion presence.
///
/// Renders the Nova PNG body with a state-driven glow halo, orbital particle dots,
/// and a gentle floating animation. Fully respects `accessibilityReduceMotion`.
///
/// State transitions cross-fade via `.id(state)` so animation always starts clean.
/// Place in a parent that allows the required canvas size: `size * 1.8`.
struct NovaView: View {
    var state: NovaState = .idle
    /// Body diameter in points. Total frame width/height is `size × 1.8` to include glow.
    var size: CGFloat = 80

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NovaCore(
                config: NovaAnimator.config(for: state),
                size: size,
                reduceMotion: reduceMotion
            )
            .id(state)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.4), value: state)
        .frame(width: size * 1.8, height: size * 1.8)
        .accessibilityLabel(NovaAccessibility.label(for: state))
        .accessibilityIdentifier("nova_companion")
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Animated core (private, recreated on state change via .id)

private struct NovaCore: View {
    let config: NovaAnimConfig
    let size: CGFloat
    let reduceMotion: Bool

    @State private var floatOffset: CGFloat = 0
    @State private var glowOpacity: Double

    init(config: NovaAnimConfig, size: CGFloat, reduceMotion: Bool) {
        self.config = config
        self.size = size
        self.reduceMotion = reduceMotion
        _glowOpacity = State(initialValue: config.glowOpacity * 0.5)
    }

    var body: some View {
        ZStack {
            glowHalo
            if !reduceMotion && config.particleCount > 0 {
                NovaParticles(
                    orbitRadius: size * 0.70,
                    count: config.particleCount,
                    dotSize: max(3, size * 0.068),
                    color: config.glowColor,
                    opacity: config.particleOpacity,
                    duration: config.particleOrbitDuration
                )
                .frame(width: size * 1.8, height: size * 1.8)
            }
            novaImage
        }
        .offset(y: reduceMotion ? 0 : floatOffset)
        .onAppear { startAnimations() }
    }

    // MARK: Layers

    private var glowHalo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        config.glowColor.opacity(glowOpacity),
                        config.glowColor.opacity(0)
                    ],
                    center: .center,
                    startRadius: size * 0.10,
                    endRadius: size * 0.78
                )
            )
            .blur(radius: config.glowRadius)
            .frame(width: size * 1.55, height: size * 1.55)
    }

    private var novaImage: some View {
        Image("Nova")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(config.imageOpacity)
    }

    // MARK: Animation startup

    private func startAnimations() {
        guard !reduceMotion else {
            // Static mode: show glow at full opacity immediately.
            glowOpacity = config.glowOpacity
            return
        }

        // Vertical float (sinusoidal via reversing easeInOut)
        if config.floatAmplitude > 0 {
            withAnimation(
                .easeInOut(duration: config.floatDuration)
                .repeatForever(autoreverses: true)
            ) {
                floatOffset = config.floatAmplitude
            }
        }

        // Glow pulse from half-intensity to full
        withAnimation(
            .easeInOut(duration: config.glowPulseDuration)
            .repeatForever(autoreverses: true)
        ) {
            glowOpacity = config.glowOpacity
        }
    }
}

// MARK: - Preview

#Preview("All states") {
    let states: [NovaState] = [
        .idle, .listening, .thinking, .responding,
        .success, .alert, .offline, .error
    ]
    return ScrollView(.horizontal) {
        HStack(spacing: OSpacing.xl) {
            ForEach(states, id: \.self) { state in
                VStack(spacing: OSpacing.sm) {
                    NovaView(state: state, size: 72)
                    Text(NovaAccessibility.label(for: state))
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextSecondary)
                }
            }
        }
        .padding(OSpacing.xl)
    }
    .background(Color.oBackground)
    .frame(height: 200)
}
