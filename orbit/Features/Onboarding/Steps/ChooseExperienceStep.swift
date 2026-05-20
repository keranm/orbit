import SwiftUI

struct ChooseExperienceStep: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("Choose Your First Model")
                    .accessibilityIdentifier("step_choose_experience_title")
                    .font(.oTitle1)
                    .foregroundStyle(Color.oTextPrimary)

                Text("Pick a model to get started. You can add more later from the Models screen.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineSpacing(2)
            }

            VStack(spacing: OSpacing.sm) {
                ForEach(OnboardingViewModel.ExperienceTier.allCases, id: \.self) { tier in
                    tierCard(tier)
                }
            }

            Spacer(minLength: OSpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, OSpacing.md)
    }

    private func tierCard(_ tier: OnboardingViewModel.ExperienceTier) -> some View {
        let isSelected = viewModel.selectedTier == tier

        return Button {
            withAnimation(.spring(duration: 0.2)) {
                viewModel.selectedTier = tier
            }
        } label: {
            HStack(spacing: OSpacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: ORadius.md)
                        .fill(isSelected ? Color.oAccent : Color.oAccentSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: tier.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.oAccent)
                }

                // Text
                VStack(alignment: .leading, spacing: OSpacing.xxs) {
                    HStack(spacing: OSpacing.xs) {
                        Text(tier.title)
                            .font(.oBodyMedium)
                            .foregroundStyle(Color.oTextPrimary)

                        if tier.isRecommended {
                            Text("Recommended")
                                .font(.oMicroMed)
                                .foregroundStyle(Color.oAccent)
                                .padding(.horizontal, OSpacing.xs)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.oAccentSoft))
                        }
                        if let note = tier.requiresNote {
                            Text(note)
                                .font(.oMicroMed)
                                .foregroundStyle(Color.oWarningAmber)
                                .padding(.horizontal, OSpacing.xs)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.oWarningAmber.opacity(0.12)))
                        }
                    }

                    Text(tier.subtitle)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Storage
                Text(tier.storageLabel)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextTertiary)

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.oAccent : Color.oDivider)
                    .font(.system(size: 18))
            }
            .padding(OSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(isSelected ? Color.oAccentSoft : Color.oSurfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: ORadius.lg)
                            .stroke(isSelected ? Color.oAccent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.title) — \(tier.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
