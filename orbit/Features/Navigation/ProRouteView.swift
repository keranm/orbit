import SwiftUI

/// Renders the appropriate Pro screen for a given ProRoute.
/// Placeholder views will be replaced with real implementations in Phases 1-5.
struct ProRouteView: View {
    let route: ProRoute

    var body: some View {
        switch route {
        case .dashboard:
            ProPlaceholderView(
                title: "Dashboard",
                subtitle: "Mesh inference metrics and system monitoring."
            )
        case .coding:
            ProPlaceholderView(
                title: "Code",
                subtitle: "AI-augmented code editor."
            )
        case .playground:
            ProPlaceholderView(
                title: "Playground",
                subtitle: "Model testing and parameter experimentation."
            )
        case .prompts:
            ProPlaceholderView(
                title: "Prompts",
                subtitle: "Prompt template library."
            )
        case .promptEditor(let id):
            ProPlaceholderView(
                title: "Prompt Editor",
                subtitle: "Editing prompt \(id.uuidString.prefix(8))…"
            )
        }
    }
}

// MARK: - Placeholder

private struct ProPlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.oTextTertiary)

            Text(title)
                .font(.oTitle2)
                .foregroundStyle(Color.oTextPrimary)

            Text(subtitle)
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
    }
}
