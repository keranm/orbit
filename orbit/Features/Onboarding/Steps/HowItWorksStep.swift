import SwiftUI

struct HowItWorksStep: View {
    var viewModel: OnboardingViewModel

    private struct Pillar: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let pillars: [Pillar] = [
        Pillar(icon: "house.fill",
               title: "Run locally",
               body: "Models run directly on your Mac — no internet required for inference."),
        Pillar(icon: "wifi",
               title: "Access the mesh",
               body: "Tap into larger models across your trusted devices and network."),
        Pillar(icon: "lock.shield.fill",
               title: "Stay in control",
               body: "All processing stays on your devices. Private by design."),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: OSpacing.xl) {
            VStack(alignment: .leading, spacing: OSpacing.xl) {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("How Orbit Works")
                        .font(.oTitle1)
                        .foregroundStyle(Color.oTextPrimary)

                    Text("Orbit is the experience layer on top of distributed AI. You control where your data goes.")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                }

                HStack(alignment: .top, spacing: OSpacing.md) {
                    ForEach(pillars) { pillar in
                        pillarCard(pillar)
                    }
                }
            }

            Spacer()

            CharacterPoseView(poseName: "Curious")
                .accessibilityHidden(true)
                .padding(.top, OSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, OSpacing.md)
    }

    private func pillarCard(_ pillar: Pillar) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: ORadius.md)
                    .fill(Color.oAccentSoft)
                    .frame(width: 36, height: 36)
                Image(systemName: pillar.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.oAccent)
            }

            Text(pillar.title)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)

            Text(pillar.body)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurfaceSecondary)
        )
    }
}
