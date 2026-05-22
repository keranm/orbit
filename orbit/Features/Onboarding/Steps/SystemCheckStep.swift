import SwiftUI

struct SystemCheckStep: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        HStack(alignment: .top, spacing: OSpacing.xl) {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("System Check")
                        .font(.oTitle1)
                        .foregroundStyle(Color.oTextPrimary)

                    Text("Checking that your Mac is ready for Orbit…")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextSecondary)
                }

                VStack(spacing: OSpacing.xs) {
                    ForEach(viewModel.checkItems) { item in
                        checkRow(item)
                    }
                }

                if viewModel.checksDone {
                    HStack(spacing: OSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.oSuccessGreen)
                            .font(.system(size: 13))
                        Text("Your Mac is ready.")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            Spacer()

            CharacterPoseView(poseName: "Exploring")
                .accessibilityHidden(true)
                .padding(.top, OSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, OSpacing.md)
        .onAppear { viewModel.startChecks() }
    }

    private func checkRow(_ item: OnboardingViewModel.CheckItem) -> some View {
        HStack(spacing: OSpacing.md) {
            statusIcon(for: item.status)
                .frame(width: 20)

            Text(item.label)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)

            Spacer()

            statusDetail(for: item)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurfaceSecondary)
        )
    }

    @ViewBuilder
    private func statusIcon(for status: OnboardingViewModel.CheckItem.Status) -> some View {
        switch status {
        case .pending:
            Circle()
                .stroke(Color.oDivider, lineWidth: 1.5)
                .frame(width: 16, height: 16)
        case .checking:
            SpinnerView()
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.oSuccessGreen)
                .font(.system(size: 16))
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.oErrorRed)
                .font(.system(size: 16))
        }
    }

    @ViewBuilder
    private func statusDetail(for item: OnboardingViewModel.CheckItem) -> some View {
        switch item.status {
        case .pending:
            Text("Waiting…")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        case .checking:
            Text("Checking…")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        case .passed:
            Text(item.passDetail)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oSuccessGreen)
                .transition(.opacity)
        case .failed(let reason):
            Text(reason)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oErrorRed)
        }
    }
}

// Lightweight spinner using rotation animation
private struct SpinnerView: View {
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.oAccent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
