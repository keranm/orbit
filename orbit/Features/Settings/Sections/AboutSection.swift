import SwiftUI

struct AboutSection: View {
    @Environment(AppState.self) private var appState
    @State private var showFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: OSpacing.xl) {
            // Identity block
            identityBlock

            Divider()

            // Version details
            versionBlock

            Divider()

            // Runtime
            runtimeBlock

            Divider()

            // Privacy statement
            privacyBlock

            Divider()

            // Links
            linksBlock

            Divider()

            // Copyright
            copyrightBlock
        }
    }

    // MARK: - Identity

    private var identityBlock: some View {
        HStack(spacing: OSpacing.md) {
            Image("OrbitLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.md))

            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("Orbit")
                    .font(.oTitle1)
                    .foregroundStyle(Color.oTextPrimary)

                Text("Private AI for your Mac")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)

                if AppVersion.isPreRelease {
                    Text(AppVersion.preReleaseLabel)
                        .font(.oMicroMed)
                        .foregroundStyle(Color.oAccent)
                        .padding(.horizontal, OSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.oAccentSoft))
                }
            }

            Spacer()
        }
    }

    // MARK: - Version

    private var versionBlock: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            metaRow(label: "Version", value: AppVersion.marketing)
            metaRow(label: "Build",   value: AppVersion.build)

            let hash = AppVersion.gitHash
            if hash != "–" {
                metaRow(label: "Commit", value: hash)
            }
        }
    }

    // MARK: - Runtime

    private var runtimeBlock: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text("Runtime")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextTertiary)

            if let version = appState.runtimeManager.installedVersion {
                metaRow(label: "Mesh-LLM", value: "v\(version)")
            } else {
                metaRow(label: "Mesh-LLM", value: appState.runtimeStatus == .notInstalled ? "Not installed" : "Detecting…")
            }

            if let path = appState.runtimeManager.binaryPath {
                metaRow(label: "Binary", value: path.path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            }
        }
    }

    // MARK: - Privacy

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack(spacing: OSpacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color.oAccent)
                    .font(.system(size: 14))
                Text("Private by design")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
            }

            VStack(alignment: .leading, spacing: OSpacing.xs) {
                privacyLine("Your conversations never leave your Mac")
                privacyLine("No accounts, no sign-in required")
                privacyLine("No usage telemetry or analytics")
                privacyLine("AI runs entirely on your hardware")
            }
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: OSpacing.xs) {
            Circle()
                .fill(Color.oSuccessGreen)
                .frame(width: 5, height: 5)
                .padding(.top, 5)
            Text(text)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
        }
    }

    // MARK: - Links

    private var linksBlock: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            // Feedback button
            Button { showFeedback = true } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.oAccent)
                    Text("Send Feedback")
                        .font(.oCaption)
                        .foregroundStyle(Color.oAccent)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFeedback) {
                FeedbackView().environment(appState)
            }

            linkRow(
                icon: "arrow.up.right.square",
                label: "Orbit on GitHub",
                url: "https://github.com/keranm/orbit"
            )
            linkRow(
                icon: "arrow.up.right.square",
                label: "Mesh-LLM on GitHub",
                url: "https://github.com/Mesh-LLM/mesh-llm"
            )
        }
    }

    private func linkRow(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: OSpacing.xs) {
                Text(label)
                    .font(.oCaption)
                    .foregroundStyle(Color.oAccent)
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.oAccent)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copyright

    private var copyrightBlock: some View {
        Text("© 2026 Orbit. All rights reserved.")
            .font(.oMicro)
            .foregroundStyle(Color.oTextTertiary)
    }

    // MARK: - Helpers

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
