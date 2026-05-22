import SwiftUI

struct InstallRuntimeStep: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        HStack(alignment: .top, spacing: OSpacing.xl) {
            VStack(alignment: .leading, spacing: OSpacing.xl) {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Install Mesh-LLM Runtime")
                        .font(.oTitle1)
                        .foregroundStyle(Color.oTextPrimary)

                    Text("Orbit needs the Mesh-LLM runtime on your Mac. This is a one-time setup.")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                }

                if let error = viewModel.installError {
                    errorState(message: error)
                } else {
                    progressState
                }
            }

            Spacer()

            CharacterPoseView(poseName: "Working")
                .accessibilityHidden(true)
                .padding(.top, OSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, OSpacing.md)
        .onAppear { viewModel.startInstall() }
    }

    // MARK: - Progress state

    private var progressState: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(Color.oDivider)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(
                            LinearGradient(
                                colors: [Color.oAccent, Color.oMeshTeal.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(0, geometry.size.width * viewModel.installProgress),
                            height: 6
                        )
                        .animation(.easeInOut(duration: 0.12), value: viewModel.installProgress)
                }
            }
            .frame(height: 6)

            HStack {
                Text(viewModel.installMessage)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .animation(.easeInOut, value: viewModel.installMessage)

                Spacer()

                Text(viewModel.installDone ? "Done" : "\(Int(viewModel.installProgress * 100))%")
                    .font(.oCaptionMed)
                    .foregroundStyle(viewModel.installDone ? Color.oSuccessGreen : Color.oTextTertiary)
                    .monospacedDigit()
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurfaceSecondary)
        )
        .overlay(statusFooter, alignment: .bottomLeading)
        .padding(.bottom, viewModel.installDone ? 0 : OSpacing.xxl)
    }

    @ViewBuilder
    private var statusFooter: some View {
        if viewModel.installDone {
            HStack(spacing: OSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.oSuccessGreen)
                Text("Orbit runtime is ready.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
            }
            .padding(.top, OSpacing.xl)
            .offset(y: OSpacing.xxxl)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            HStack(spacing: OSpacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextTertiary)
                Text("mesh-llm runtime — no data leaves your Mac")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
            }
            .padding(.top, OSpacing.xl)
            .offset(y: OSpacing.xxxl)
        }
    }

    // MARK: - Error state

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.md) {
            HStack(alignment: .top, spacing: OSpacing.sm) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color.oWarningAmber)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Couldn't install")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)

                    Text(message)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(OSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oSurfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: ORadius.lg)
                            .stroke(Color.oWarningAmber.opacity(0.3), lineWidth: 1.5)
                    )
            )

            Button {
                viewModel.retryInstall()
            } label: {
                Text("Try again")
                    .font(.oBodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, OSpacing.lg)
                    .padding(.vertical, OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.pill)
                            .fill(Color.oAccent)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("install_retry_button")
        }
    }
}
