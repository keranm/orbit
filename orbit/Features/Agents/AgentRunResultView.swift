import SwiftUI

struct AgentRunResultView: View {
    let agent: Agent
    let output: String
    let stepStates: [Int: StepRunState]
    let onDismiss: () -> Void

    @State private var selectedTab: ResultTab = .output
    @State private var copyConfirmed = false

    enum ResultTab: String, CaseIterable {
        case output = "Output"
        case trace  = "Trace"
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
            Divider()
            footer
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ResultTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.oCaptionMed)
                        .foregroundStyle(selectedTab == tab ? Color.oAccent : Color.oTextSecondary)
                        .padding(.horizontal, OSpacing.md)
                        .padding(.vertical, OSpacing.xs)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(Color.oAccent)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()

            // Success badge
            HStack(spacing: OSpacing.xxs) {
                Circle()
                    .fill(Color.oSuccessGreen)
                    .frame(width: 6, height: 6)
                Text("Completed")
                    .font(.oMicro)
                    .foregroundStyle(Color.oSuccessGreen)
            }
            .padding(.trailing, OSpacing.md)
        }
        .padding(.leading, OSpacing.xs)
        .background(Color.oSurface)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .output: outputTab
        case .trace:  traceTab
        }
    }

    private var outputTab: some View {
        ScrollView {
            Text(output.isEmpty ? "No output was produced." : output)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OSpacing.lg)
                .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity)
        .background(Color.oBackground)
    }

    private var traceTab: some View {
        ScrollView {
            VStack(spacing: OSpacing.sm) {
                ForEach(agent.sortedSteps, id: \.id) { step in
                    traceRow(step: step)
                }
            }
            .padding(OSpacing.md)
        }
        .frame(maxHeight: .infinity)
        .background(Color.oBackground)
    }

    private func traceRow(step: AgentStep) -> some View {
        let runState = stepStates[step.order] ?? .pending
        return HStack(alignment: .top, spacing: OSpacing.sm) {
            traceIcon(for: runState)

            VStack(alignment: .leading, spacing: OSpacing.xxs) {
                HStack {
                    Text(step.label)
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    if case .completed(let dur) = runState {
                        Text(String(format: "%.2fs", dur))
                            .font(.oMicro)
                            .foregroundStyle(Color.oTextTertiary)
                            .monospacedDigit()
                    }
                }

                Text(step.stepType.label)
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)

                if case .failed(let msg) = runState {
                    Text(msg)
                        .font(.oMicro)
                        .foregroundStyle(Color.oErrorRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(OSpacing.sm)
        .background(Color.oSurface)
        .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
        .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
    }

    @ViewBuilder
    private func traceIcon(for state: StepRunState) -> some View {
        switch state {
        case .pending:
            Circle().fill(Color.oDivider).frame(width: 8, height: 8).frame(width: 20, height: 20)
        case .running:
            ProgressView().scaleEffect(0.6).frame(width: 20, height: 20)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.oSuccessGreen)
                .frame(width: 20, height: 20)
        case .skipped:
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color.oTextTertiary)
                .frame(width: 20, height: 20)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.oErrorRed)
                .frame(width: 20, height: 20)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: OSpacing.sm) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
                withAnimation { copyConfirmed = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run { withAnimation { copyConfirmed = false } }
                }
            } label: {
                HStack(spacing: OSpacing.xxs) {
                    Image(systemName: copyConfirmed ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                    Text(copyConfirmed ? "Copied!" : "Copy output")
                        .font(.oCaptionMed)
                }
                .foregroundStyle(Color.oTextSecondary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(Color.oSurface)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Close", action: onDismiss)
                .font(.oCaptionMed)
                .buttonStyle(.bordered)
                .tint(Color.oAccent)
        }
        .padding(.horizontal, OSpacing.lg)
        .padding(.vertical, OSpacing.sm)
        .background(Color.oSurface)
    }
}
