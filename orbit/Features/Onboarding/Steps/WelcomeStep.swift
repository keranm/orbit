import SwiftUI

struct WelcomeStep: View {
    var viewModel: OnboardingViewModel

    private struct Pillar: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let pillars: [Pillar] = [
        Pillar(icon: "lock.shield.fill",
               title: "100% Private",
               body: "Your data stays on your devices."),
        Pillar(icon: "house.fill",
               title: "Runs Locally",
               body: "No cloud required. You're in control."),
        Pillar(icon: "network",
               title: "Mesh Assisted",
               body: "Tap into trusted devices you allow."),
        Pillar(icon: "chart.bar.xaxis.ascending",
               title: "Private by Design",
               body: "No tracking. No analytics."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: OSpacing.xl) {

            // Nova — welcoming pose
            HStack {
                Spacer()
                CharacterPoseView(poseName: "Welcome")
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.bottom, OSpacing.xs)

            // Heading
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("Welcome to Orbit")
                    .font(.oLargeTitle)
                    .foregroundStyle(Color.oTextPrimary)
                    .accessibilityIdentifier("welcome_heading_line1")

                Text("Powerful AI. Without the cloud giants.")
                    .font(.oTitle2)
                    .foregroundStyle(Color.oAccent)
                    .accessibilityIdentifier("welcome_heading_line2")
            }

            Text("Orbit connects your Mac to private local and mesh-assisted AI — no accounts, no data leaving your devices.")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Feature pillars
            HStack(alignment: .top, spacing: OSpacing.sm) {
                ForEach(pillars) { pillar in
                    pillarCard(pillar)
                }
            }

            // Privacy note
            HStack(alignment: .top, spacing: OSpacing.md) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.oAccent)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Privacy first, always.")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)

                    Text("Orbit is designed from the ground up to protect your privacy. Your conversations and data never leave your devices unless you choose to share them within your private mesh.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(OSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oAccentSoft)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pillarCard(_ pillar: Pillar) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Image(systemName: pillar.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.oAccent)

            Text(pillar.title)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextPrimary)

            Text(pillar.body)
                .font(.oMicro)
                .foregroundStyle(Color.oTextSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurface)
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ORadius.md)
                .stroke(Color.oDivider, lineWidth: 0.5)
        )
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppState())
        .frame(width: 1100, height: 700)
}
