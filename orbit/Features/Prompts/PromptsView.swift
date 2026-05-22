import SwiftUI

struct PromptsView: View {
    @AppStorage(PromptSettings.defaultPromptKey)
    private var defaultPrompt = PromptSettings.defaultPromptText

    @AppStorage(PromptSettings.userPreferencesKey)
    private var userPreferences = PromptSettings.defaultPreferencesText

    @AppStorage(PromptSettings.includeLocalContextKey)
    private var includeLocalContext = PromptSettings.defaultIncludeLocalContext

    @State private var showResetConfirm = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column — editable prompt fields
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            // Right column — local context panel
            contextPanel
                .frame(width: 268)
        }
        .background(Color.oBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("prompts_view")
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: OSpacing.xs) {
                        Text("Prompts")
                            .font(.oTitle1)
                            .foregroundStyle(Color.oTextPrimary)
                            .accessibilityIdentifier("prompts_title")

                        Text("Customize how Orbit responds and the context it uses.")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextSecondary)
                    }

                    Spacer()

                    Button {
                        showResetConfirm = true
                    } label: {
                        Text("Reset to defaults")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "This will restore the default system prompt and clear your preferences.",
                        isPresented: $showResetConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Reset to defaults", role: .destructive) {
                            withAnimation {
                                defaultPrompt = PromptSettings.defaultPromptText
                                userPreferences = PromptSettings.defaultPreferencesText
                                includeLocalContext = PromptSettings.defaultIncludeLocalContext
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }

                // Default system prompt card
                promptCard(
                    title: "Default system prompt",
                    tooltip: "Customize the base behaviour of your AI assistant.",
                    description: "This is the base instruction set used for every new chat.",
                    text: $defaultPrompt,
                    placeholder: PromptSettings.defaultPromptText
                )

                // User preferences card
                promptCard(
                    title: "Your preferences & notes",
                    tooltip: nil,
                    description: "Any useful things about you or how you like AI answers.",
                    text: $userPreferences,
                    placeholder: "I live in Australia.\nI prefer metric units.\nI'm interested in finance, productivity and technology."
                )

                // Tips
                tipsSection
            }
            .padding(OSpacing.xl)
        }
    }

    // MARK: - Prompt card

    private func promptCard(
        title: String,
        tooltip: String?,
        description: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            // Title row
            HStack(spacing: OSpacing.xs) {
                Text(title)
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)

                if let tip = tooltip {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.oTextTertiary)
                        .help(tip)
                }
            }

            Text(description)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)

            // Editable text area
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: ORadius.md)
                    .fill(Color.oSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: ORadius.md)
                            .stroke(Color.oDivider, lineWidth: 1)
                    )

                TextEditor(text: text)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(OSpacing.sm)
                    .frame(minHeight: 120)
                    .accessibilityLabel(title)
            }

            // Character count
            HStack {
                Spacer()
                Text("\(text.wrappedValue.count) characters")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                    .monospacedDigit()
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurface)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .stroke(Color.oDivider, lineWidth: 0.5)
        )
    }

    // MARK: - Tips section

    private var tipsSection: some View {
        HStack(alignment: .top, spacing: OSpacing.sm) {
            Image(systemName: "lightbulb")
                .font(.system(size: 14))
                .foregroundStyle(Color.oAccent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("Tips")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)

                tipBullet("Be specific about your location so Orbit can give relevant answers.")
                tipBullet("Mention your profession or interests so answers are tailored to you.")
                tipBullet("Enable local context to automatically include your timezone and date.")
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oAccentSoft)
        )
    }

    private func tipBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: OSpacing.xs) {
            Text("·")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
            Text(text)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Context panel (right column)

    private var contextPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                // Toggle header
                VStack(alignment: .leading, spacing: OSpacing.sm) {
                    HStack {
                        Text("Include local context")
                            .font(.oBodyMedium)
                            .foregroundStyle(Color.oTextPrimary)
                        Spacer()
                        Toggle("", isOn: $includeLocalContext)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(Color.oAccent)
                            .accessibilityLabel("Include local context")
                    }

                    Text("Orbit will automatically include helpful context from this device in your chats.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Context item list
                VStack(spacing: 0) {
                    contextItem(
                        icon: "location.fill",
                        iconColor: Color.oAccent,
                        label: "Location",
                        value: PromptSettings.locationFromTimezone(),
                        active: includeLocalContext
                    )

                    contextDivider

                    contextItem(
                        icon: "clock.fill",
                        iconColor: Color.oAccent,
                        label: "Timezone",
                        value: TimeZone.current.identifier,
                        active: includeLocalContext
                    )

                    contextDivider

                    contextItem(
                        icon: "calendar",
                        iconColor: Color.oAccent,
                        label: "Date & time",
                        value: PromptSettings.formattedDateTime(),
                        active: includeLocalContext
                    )

                    contextDivider

                    contextItem(
                        icon: "laptopcomputer",
                        iconColor: Color.oAccent,
                        label: "Device",
                        value: PromptSettings.deviceModel(),
                        active: includeLocalContext
                    )

                    contextDivider

                    contextItem(
                        icon: "globe",
                        iconColor: Color.oAccent,
                        label: "Language",
                        value: PromptSettings.languageDescription(),
                        active: includeLocalContext
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: ORadius.lg)
                        .fill(Color.oSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ORadius.lg)
                        .stroke(Color.oDivider, lineWidth: 0.5)
                )

                // Footer note
                Text("Context is read locally from your device. Nothing is sent automatically.")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                    .lineSpacing(2)
            }
            .padding(OSpacing.md)
        }
    }

    private func contextItem(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        active: Bool
    ) -> some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(active ? iconColor : Color.oTextTertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.oCaptionMed)
                    .foregroundStyle(active ? Color.oTextPrimary : Color.oTextTertiary)

                Text(value)
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if active {
                activeBadge
            }
        }
        .padding(.horizontal, OSpacing.sm)
        .padding(.vertical, OSpacing.sm)
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    private var activeBadge: some View {
        Text("Active")
            .font(.oMicroMed)
            .foregroundStyle(Color.oSuccessGreen)
            .padding(.horizontal, OSpacing.xs)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.oSuccessGreen.opacity(0.12))
            )
    }

    private var contextDivider: some View {
        Divider()
            .padding(.leading, OSpacing.xl + OSpacing.sm)
    }
}

#Preview {
    PromptsView()
        .frame(width: 860, height: 640)
}
