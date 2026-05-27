import SwiftUI

struct ChooseExperienceStep: View {
    @State private var showProgress = false
    var viewModel: OnboardingViewModel

    var body: some View {
        HStack(alignment: .top, spacing: OSpacing.xl) {
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

                if let installed = viewModel.runtimeManager?.installedModels, !installed.isEmpty {
                    VStack(alignment: .leading, spacing: OSpacing.sm) {
                        Text("Already installed")
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oTextTertiary)
                            .padding(.top, OSpacing.sm)

                        ForEach(installed) { model in
                            installedModelCard(model)
                        }
                    }
                }

            if case .failed(let msg) = viewModel.downloadState {
                HStack(spacing: OSpacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.oWarningAmber)
                    Text(msg)
                        .font(.oCaption)
                        .foregroundStyle(Color.oWarningAmber)
                }
                .padding(.top, OSpacing.xs)
            }
        }

        Spacer()

        CharacterPoseView(poseName: "Thinking")
            .accessibilityHidden(true)
            .padding(.top, OSpacing.sm)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, OSpacing.md)
}

    private func installedModelCard(_ model: InstalledModelEntry) -> some View {
        let isPicked = viewModel.selectedExistingModel?.id == model.id

        return Button {
            withAnimation(.spring(duration: 0.2)) {
                if isPicked {
                    viewModel.selectedExistingModel = nil
                } else {
                    viewModel.selectedExistingModel = model
                    viewModel.selectedTier = .fast  // deselect tier selection
                }
            }
        } label: {
            HStack(spacing: OSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: ORadius.md)
                        .fill(isPicked ? Color.oMeshTeal : Color.oAccentSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: "square.stack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPicked ? Color.white : Color.oAccent)
                }

                VStack(alignment: .leading, spacing: OSpacing.xxs) {
                    Text(model.displayName)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    if let size = model.size {
                        Text("\(size) — Already downloaded")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                    }
                }

                Spacer()

                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? Color.oMeshTeal : Color.oDivider)
                    .font(.system(size: 18))
            }
            .padding(OSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(isPicked ? Color.oMeshTeal.opacity(0.08) : Color.oSurfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: ORadius.lg)
                            .stroke(isPicked ? Color.oMeshTeal.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func tierCard(_ tier: OnboardingViewModel.ExperienceTier) -> some View {
        let isSelected = viewModel.selectedTier == tier && viewModel.selectedExistingModel == nil

        return Button {
            withAnimation(.spring(duration: 0.2)) {
                viewModel.selectedTier = tier
                viewModel.selectedExistingModel = nil  // deselect any existing model
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
