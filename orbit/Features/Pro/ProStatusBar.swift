import SwiftUI

/// Shared bottom status bar used by all three Pro screens.
/// Dashboard variant shows Runtime + Local Model instead of peers/throughput.
struct ProStatusBar: View {
    @Environment(AppState.self) private var appState
    var dashboardVariant = false

    var body: some View {
        HStack(spacing: OSpacing.md) {
            HStack(spacing: OSpacing.xs) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                Text(appState.runtimeManager.meshConnectionState.statusLabel)
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextPrimary)
            }

            if dashboardVariant {
                if let version = appState.runtimeManager.installedVersion {
                    Text("Runtime: Mesh-LLM \(version)")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextSecondary)
                }
                if let model = appState.runtimeManager.activeModelRef {
                    Text("Local Model: \(model)")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextSecondary)
                } else {
                    Text("No model configured")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }
            } else {
                let peerCount = appState.runtimeManager.meshConnectionState.peerCountOptional
                Text("Peers: \(peerCount.map(String.init) ?? "—")")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextSecondary)
                if let version = appState.runtimeManager.installedVersion {
                    Text("Runtime: Mesh-LLM \(version)")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }
            }

            Spacer()

            if dashboardVariant {
                Button("Open Logs") {}
                    .buttonStyle(.plain)
                    .font(.oMicro)
                    .foregroundStyle(Color.oAccent)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.oTextTertiary)
            } else {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextTertiary)
            }
        }
        .padding(.horizontal, OSpacing.md)
        .frame(height: 28)
        .background(Color.oSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.oDivider).frame(height: 1)
        }
    }

    private var statusDotColor: Color {
        switch appState.runtimeStatus {
        case .ready:    return Color.oSuccessGreen
        case .starting: return Color.oWarningAmber
        default:        return Color.oTextTertiary
        }
    }
}
