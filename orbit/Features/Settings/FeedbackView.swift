import SwiftUI

struct FeedbackView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    enum FeedbackType: String, CaseIterable {
        case bug = "Bug report"
        case feature = "Feature request"
        case general = "General feedback"

        var icon: String {
            switch self {
            case .bug:     return "ladybug"
            case .feature: return "sparkles"
            case .general: return "bubble.left"
            }
        }
    }

    enum SubmitState { case idle, sending, sent, failed(String) }

    @State private var type: FeedbackType = .general
    @State private var message = ""
    @State private var email = ""
    @State private var submitState: SubmitState = .idle

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: OSpacing.xxs) {
                    Text("Send Feedback")
                        .font(.oTitle2)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Help us make Orbit better.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.oTextTertiary)
                        .padding(6)
                        .background(Circle().fill(Color.oSurfaceSecondary))
                }
                .buttonStyle(.plain)
            }
            .padding(OSpacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: OSpacing.lg) {

                    // Feedback type
                    VStack(alignment: .leading, spacing: OSpacing.sm) {
                        Text("Type")
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oTextSecondary)

                        HStack(spacing: OSpacing.xs) {
                            ForEach(FeedbackType.allCases, id: \.self) { t in
                                typeChip(t)
                            }
                        }
                    }

                    // Message
                    VStack(alignment: .leading, spacing: OSpacing.sm) {
                        Text("Message")
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oTextSecondary)

                        TextEditor(text: $message)
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                            .frame(minHeight: 120, maxHeight: 200)
                            .padding(OSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.md)
                                    .fill(Color.oSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ORadius.md)
                                            .stroke(Color.oDivider, lineWidth: 1)
                                    )
                            )
                            .scrollContentBackground(.hidden)
                    }

                    // Email (optional)
                    VStack(alignment: .leading, spacing: OSpacing.sm) {
                        Text("Email (optional)")
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oTextSecondary)

                        TextField("your@email.com", text: $email)
                            .textFieldStyle(.plain)
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                            .padding(OSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.md)
                                    .fill(Color.oSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ORadius.md)
                                            .stroke(Color.oDivider, lineWidth: 1)
                                    )
                            )
                    }

                    // Success / error state
                    switch submitState {
                    case .sent:
                        HStack(spacing: OSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.oSuccessGreen)
                            Text("Thanks — feedback sent!")
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextSecondary)
                        }
                        .padding(OSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ORadius.md)
                                .fill(Color.oSuccessGreen.opacity(0.08))
                        )
                    case .failed(let msg):
                        HStack(spacing: OSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.oWarningAmber)
                            Text(msg)
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextSecondary)
                        }
                        .padding(OSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ORadius.md)
                                .fill(Color.oWarningAmber.opacity(0.08))
                        )
                    default:
                        EmptyView()
                    }
                }
                .padding(OSpacing.xl)
            }

            Divider()

            // Footer
            HStack {
                Text("Your feedback is read by the Orbit team.")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
                HStack(spacing: OSpacing.sm) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.oBody)
                        .foregroundStyle(Color.oTextSecondary)

                    sendButton
                }
            }
            .padding(.horizontal, OSpacing.xl)
            .padding(.vertical, OSpacing.md)
        }
        .frame(width: 480)
        .background(Color.oBackground)
    }

    private func typeChip(_ t: FeedbackType) -> some View {
        let active = type == t
        return Button { type = t } label: {
            HStack(spacing: OSpacing.xxs) {
                Image(systemName: t.icon)
                    .font(.system(size: 11))
                Text(t.rawValue)
                    .font(.oCaption)
            }
            .foregroundStyle(active ? Color.oAccent : Color.oTextSecondary)
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, OSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: ORadius.pill)
                    .fill(active ? Color.oAccentSoft : Color.oSurfaceSecondary)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sendButton: some View {
        switch submitState {
        case .sending:
            HStack(spacing: OSpacing.xs) {
                ProgressView().controlSize(.small)
                Text("Sending…").font(.oBodyMedium).foregroundStyle(Color.oTextTertiary)
            }
            .padding(.horizontal, OSpacing.lg)
            .padding(.vertical, OSpacing.sm)
            .background(RoundedRectangle(cornerRadius: ORadius.pill).fill(Color.oSurfaceSecondary))
        case .sent:
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.oBodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.lg)
                .padding(.vertical, OSpacing.sm)
                .background(RoundedRectangle(cornerRadius: ORadius.pill).fill(Color.oSuccessGreen))
        default:
            Button { Task { await submit() } } label: {
                Text("Send Feedback")
                    .font(.oBodyMedium)
                    .foregroundStyle(canSend ? .white : Color.oTextTertiary)
                    .padding(.horizontal, OSpacing.lg)
                    .padding(.vertical, OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.pill)
                            .fill(canSend ? Color.oAccent : Color.oSurfaceSecondary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    private func submit() async {
        guard canSend else { return }
        submitState = .sending

        let payload: [String: String] = [
            "type": type.rawValue,
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "app_version": AppVersion.marketing,
            "runtime_version": appState.runtimeManager.installedVersion ?? "unknown",
        ]

        guard let url = URL(string: "https://keranmckenzie.com/feedback/"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            submitState = .failed("Couldn't build request.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status >= 200 && status < 300 {
                submitState = .sent
            } else {
                submitState = .failed("Server returned \(status). Please try again.")
            }
        } catch {
            submitState = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    FeedbackView()
        .environment(AppState())
}
