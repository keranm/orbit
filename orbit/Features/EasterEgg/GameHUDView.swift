import SwiftUI

struct GameHUDView: View {
    let state: GameState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 0) {
            scoreAndLives
                .frame(minWidth: 120, alignment: .leading)
            Spacer()
            waveLabel
            Spacer()
            highScore
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.top, 32)
    }

    private var scoreAndLives: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCORE")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.white.opacity(0.7))
            Text(String(format: "%05d", state.score))
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color(red: 0.27, green: 0.65, blue: 1.0))

            HStack(spacing: 6) {
                Text("LIVES")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                ForEach(0..<max(0, state.lives), id: \.self) { _ in
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(Color(red: 0.27, green: 0.65, blue: 1.0))
                }
            }
        }
    }

    private var highScore: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("HIGH SCORE")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.white.opacity(0.7))
            Text(String(format: "%05d", state.highScore))
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.white)

            if state.phase == .boss {
                bossHealthBar
            }
        }
    }

    private var bossHealthBar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("BOSS HEALTH")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.white.opacity(0.7))
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.2))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.red)
                            .frame(width: geo.size.width * state.bossHPPercent)
                    }
                }
                .frame(width: 140, height: 10)
                Text("\(Int(state.bossHPPercent * 100))%")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private var waveLabel: some View {
        Group {
            switch state.phase {
            case .wave1:
                Text("—  WAVE \(state.wave)  —")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.white)
            case .bossIntro, .boss:
                Text("BOSS FIGHT")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 1.0))
                    .shadow(color: .purple.opacity(0.8), radius: 6)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 20) {
            Spacer()
            keyChip("←  →", label: "Move")
            keyChip("Space", label: "Shoot", prominent: true)
            keyChip("ESC", label: "Exit")
            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.6))
    }

    private func keyChip(_ key: String, label: String, prominent: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(prominent ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.12, green: 0.12, blue: 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.3), lineWidth: 1))
                )
                .foregroundStyle(Color.white)
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}
