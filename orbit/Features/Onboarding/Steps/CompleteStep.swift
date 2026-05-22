import SwiftUI

struct CompleteStep: View {
    var viewModel: OnboardingViewModel
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: OSpacing.lg) {
            Spacer(minLength: 0)

            // Nova — celebrating with confetti
            CharacterPoseView(poseName: "Celebrating", showConfetti: true)
                .accessibilityHidden(true)

            // Heading
            VStack(spacing: OSpacing.sm) {
                Text("You're all set!")
                    .font(.oTitle1)
                    .foregroundStyle(Color.oTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Orbit is ready. Start a conversation with your AI.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Summary card
            VStack(alignment: .leading, spacing: OSpacing.sm) {
                summaryRow(
                    icon: "cpu",
                    label: "Model",
                    value: viewModel.selectedTier.displayName
                )
                Divider()
                summaryRow(
                    icon: "lock.fill",
                    label: "Privacy",
                    value: "Private to this Mac"
                )
                Divider()
                summaryRow(
                    icon: "house.fill",
                    label: "Running",
                    value: "Locally"
                )
            }
            .padding(OSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oSurfaceSecondary)
            )

            // CTA button
            Button(action: onComplete) {
                HStack(spacing: OSpacing.sm) {
                    Text("Start using Orbit")
                        .font(.oBodyMedium)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OSpacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(Color.oAccent)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding_start_orbit")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OSpacing.xxl)
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.oTextTertiary)
                .frame(width: 16)

            Text(label)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)

            Spacer()

            Text(value)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextPrimary)
        }
    }
}
