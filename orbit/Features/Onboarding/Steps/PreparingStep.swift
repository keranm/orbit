import SwiftUI

struct PreparingStep: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        HStack(alignment: .top, spacing: OSpacing.xl) {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Preparing Your AI")
                        .font(.oTitle1)
                        .foregroundStyle(Color.oTextPrimary)

                    Text("Setting up \(viewModel.selectedTier.displayName) for your first conversation.")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                }

                VStack(spacing: OSpacing.xs) {
                    ForEach(viewModel.prepareItems) { item in
                        prepareRow(item)
                    }
                }
                .padding(OSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.lg)
                        .fill(Color.oSurfaceSecondary)
                )

                if let error = viewModel.prepareError {
                    errorFooter(message: error)
                } else if viewModel.prepareDone {
                    HStack(spacing: OSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.oSuccessGreen)
                        Text("Your model is ready.")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    startupNote
                }
            }

            Spacer()

            CharacterPoseView(poseName: "Helping")
                .accessibilityHidden(true)
                .padding(.top, OSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, OSpacing.md)
        .onAppear {
            viewModel.startServing()
        }
    }

    // MARK: - Startup note

    private var startupNote: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text("Your model is being prepared. This may take a moment on first run.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
                .lineSpacing(2)
        }
    }

    // MARK: - Prepare row

    private func prepareRow(_ item: OnboardingViewModel.PrepareItem) -> some View {
        VStack(spacing: OSpacing.xs) {
            HStack(spacing: OSpacing.md) {
                statusIcon(for: item.status)
                    .frame(width: 18)

                Text(item.label)
                    .font(.oBody)
                    .foregroundStyle(statusTextColor(for: item.status))

                if let detail = item.detail {
                    Text(detail)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                }

                Spacer()

                statusDetail(for: item)
            }

            if case .active(let progress) = item.status {
                ProgressView(value: progress > 0 ? progress : nil, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(Color.oAccent)
                    .frame(height: 4)
                    .padding(.top, OSpacing.xs)
            }
        }
        .padding(.vertical, OSpacing.xs)
    }

    @ViewBuilder
    private func statusIcon(for status: OnboardingViewModel.PrepareItem.Status) -> some View {
        switch status {
        case .pending:
            Circle()
                .stroke(Color.oDivider, lineWidth: 1.5)
                .frame(width: 14, height: 14)
        case .active:
            ProgressView()
                .controlSize(.small)
                .tint(Color.oAccent)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.oSuccessGreen)
                .font(.system(size: 16))
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.oWarningAmber)
                .font(.system(size: 16))
        }
    }

    @ViewBuilder
    private func statusDetail(for item: OnboardingViewModel.PrepareItem) -> some View {
        switch item.status {
        case .active(let progress) where progress > 0:
            Text("\(Int(progress * 100))%")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oAccent)
                .monospacedDigit()
        case .failed(let reason):
            Text(reason)
                .font(.oCaption)
                .foregroundStyle(Color.oWarningAmber)
        default:
            EmptyView()
        }
    }


    private func statusTextColor(for status: OnboardingViewModel.PrepareItem.Status) -> Color {
        switch status {
        case .pending:       return Color.oTextTertiary
        case .active:        return Color.oTextPrimary
        case .done:          return Color.oTextSecondary
        case .failed:        return Color.oWarningAmber
        }
    }

    // MARK: - Error footer

    private func errorFooter(message: String) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            Text(message)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
                .lineSpacing(2)

            Button {
                viewModel.retryServing()
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
            .accessibilityIdentifier("prepare_retry_button")
        }
    }
}


