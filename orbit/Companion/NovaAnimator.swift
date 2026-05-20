import SwiftUI

/// Per-state animation parameters. All values tuned for calm, ambient feel.
struct NovaAnimConfig {
    /// Primary glow colour (used for halo + particles)
    let glowColor: Color
    /// Peak glow opacity (pulses between half and this value)
    let glowOpacity: Double
    /// Blur radius applied to the glow halo
    let glowRadius: CGFloat
    /// Half-cycle duration for the opacity pulse (s)
    let glowPulseDuration: Double
    /// Peak vertical float displacement (pts)
    let floatAmplitude: CGFloat
    /// Half-cycle duration for the float (s)
    let floatDuration: Double
    /// Image opacity — dimmed for offline/error
    let imageOpacity: Double
    /// Number of orbital satellite dots (0 = no particles)
    let particleCount: Int
    /// Full orbit rotation period (s)
    let particleOrbitDuration: Double
    /// Satellite dot opacity
    let particleOpacity: Double
}

enum NovaAnimator {
    static func config(for state: NovaState) -> NovaAnimConfig {
        switch state {
        case .idle:
            return NovaAnimConfig(
                glowColor: .oOrbGlow,
                glowOpacity: 0.28,
                glowRadius: 20,
                glowPulseDuration: 3.5,
                floatAmplitude: 5,
                floatDuration: 3.2,
                imageOpacity: 1.0,
                particleCount: 3,
                particleOrbitDuration: 10.0,
                particleOpacity: 0.30
            )

        case .listening:
            return NovaAnimConfig(
                glowColor: .oAccent,
                glowOpacity: 0.32,
                glowRadius: 22,
                glowPulseDuration: 2.5,
                floatAmplitude: 3,
                floatDuration: 4.0,
                imageOpacity: 1.0,
                particleCount: 3,
                particleOrbitDuration: 8.0,
                particleOpacity: 0.40
            )

        case .thinking:
            return NovaAnimConfig(
                glowColor: .oAccent,
                glowOpacity: 0.38,
                glowRadius: 24,
                glowPulseDuration: 1.8,
                floatAmplitude: 4,
                floatDuration: 2.5,
                imageOpacity: 1.0,
                particleCount: 4,
                particleOrbitDuration: 5.5,
                particleOpacity: 0.50
            )

        case .responding:
            return NovaAnimConfig(
                glowColor: .oAccent,
                glowOpacity: 0.42,
                glowRadius: 26,
                glowPulseDuration: 1.4,
                floatAmplitude: 5,
                floatDuration: 2.0,
                imageOpacity: 1.0,
                particleCount: 4,
                particleOrbitDuration: 4.5,
                particleOpacity: 0.55
            )

        case .success:
            return NovaAnimConfig(
                glowColor: .oSuccessGreen,
                glowOpacity: 0.30,
                glowRadius: 22,
                glowPulseDuration: 2.5,
                floatAmplitude: 7,
                floatDuration: 3.0,
                imageOpacity: 1.0,
                particleCount: 3,
                particleOrbitDuration: 9.0,
                particleOpacity: 0.38
            )

        case .alert:
            return NovaAnimConfig(
                glowColor: .oWarningAmber,
                glowOpacity: 0.32,
                glowRadius: 20,
                glowPulseDuration: 2.2,
                floatAmplitude: 3,
                floatDuration: 3.5,
                imageOpacity: 1.0,
                particleCount: 2,
                particleOrbitDuration: 10.0,
                particleOpacity: 0.32
            )

        case .offline:
            return NovaAnimConfig(
                glowColor: .oTextTertiary,
                glowOpacity: 0.15,
                glowRadius: 16,
                glowPulseDuration: 5.0,
                floatAmplitude: 3,
                floatDuration: 5.0,
                imageOpacity: 0.55,
                particleCount: 0,
                particleOrbitDuration: 14.0,
                particleOpacity: 0.0
            )

        case .error:
            return NovaAnimConfig(
                glowColor: .oWarningAmber,
                glowOpacity: 0.20,
                glowRadius: 18,
                glowPulseDuration: 3.0,
                floatAmplitude: 0,
                floatDuration: 4.0,
                imageOpacity: 0.80,
                particleCount: 0,
                particleOrbitDuration: 14.0,
                particleOpacity: 0.0
            )
        }
    }
}
