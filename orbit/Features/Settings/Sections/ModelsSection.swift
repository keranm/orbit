import SwiftUI

struct ModelsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingGroup {
                // Installed models count
                settingRow(
                    title: "Installed models",
                    detail: installedCount
                )
                Divider().padding(.leading, OSpacing.md)
                // Cache directory
                Button { openCacheDirInFinder() } label: {
                    VStack(alignment: .leading, spacing: OSpacing.xs) {
                        HStack {
                            Text("Storage location")
                                .font(.oBody)
                                .foregroundStyle(Color.oTextPrimary)
                            Spacer()
                            Text("Open in Finder")
                                .font(.oCaptionMed)
                                .foregroundStyle(Color.oAccent)
                        }
                        Text(cacheDirDisplay)
                            .font(.oMicro)
                            .foregroundStyle(Color.oTextTertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, OSpacing.md)
                    .padding(.vertical, OSpacing.sm)
                    .settingsRowHoverable()
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: OSpacing.md)

            Button {
                appState.route = .models
            } label: {
                HStack {
                    Spacer()
                    Text("Manage Models")
                        .font(.oBodyMedium)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, OSpacing.sm)
                .background(RoundedRectangle(cornerRadius: ORadius.pill).fill(Color.oAccent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage models — open Models screen")
        }
    }

    // MARK: - Helpers

    private var installedCount: String {
        let n = appState.runtimeManager.installedModels.count
        return n == 1 ? "1 model" : "\(n) models"
    }

    private var cacheDirDisplay: String {
        let dir = appState.runtimeManager.cacheDir
        return dir.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func openCacheDirInFinder() {
        let path = appState.runtimeManager.cacheDir
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.oSurface)
        .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 0.5))
    }

    private func settingRow(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
            Spacer()
            Text(detail)
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }
}
