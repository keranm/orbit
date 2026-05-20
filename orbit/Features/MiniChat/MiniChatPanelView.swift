import SwiftUI

/// The Nova-anchored Mini-Chat overlay.
///
/// Layout model — compact state:
///
///   [ ◯ Nova ◯ ]   ← Nova is a circle/pill, centered on screen
///
/// Listening state (input expands leftward from Nova):
///
///   [ type here... ◯ Nova ◯ ]
///
/// Nova is the right anchor. The text field grows to Nova's left.
/// Conversation card slides below the pill on first send.
///
/// Hosted in a transparent, borderless NSPanel — no chrome.
struct MiniChatPanelView: View {
    @State var viewModel: MiniChatPanelViewModel

    @FocusState private var inputFocused: Bool
    @AppStorage("showModelReasoning") private var showReasoning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Pill width: starts at novaSlotWidth (compact), expands to fullInputWidth
    @State private var inputPillWidth: CGFloat

    // Nova visual size inside the pill
    private let novaDisplaySize: CGFloat  = 64
    // The slot Nova occupies in the pill (slightly larger than Nova for breathing room)
    private let novaSlotWidth:   CGFloat  = 76
    // Pill height — equal to novaSlotWidth for a perfect right-cap circle
    private let pillHeight:      CGFloat  = 58
    // Full expanded width (Nova slot + text field)
    private let fullInputWidth:  CGFloat  = 500

    init(viewModel: MiniChatPanelViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
        // Start at just the Nova slot width (compact — no text field visible)
        self._inputPillWidth = State(initialValue: 76)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Transparent capture for click-outside dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { NovaOverlayViewController.shared.dismiss() }

            VStack(spacing: 0) {
                // ── Compact / expanded pill ──
                compactPill
                    .padding(.top, 48)
                    .opacity(pillOpacity)
                    .animation(
                        reduceMotion ? .linear(duration: 0.15) : .spring(duration: 0.42, bounce: 0.08),
                        value: viewModel.phase
                    )

                // ── Conversation card (slides down on first send) ──
                if showConversation {
                    conversationCard
                        .padding(.top, 10)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal:   .opacity
                                )
                        )
                }

                if let err = viewModel.streamError, !err.isEmpty {
                    errorNote(err)
                        .padding(.top, OSpacing.xs)
                        .transition(.opacity)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .onKeyPress(.escape) {
            NovaOverlayViewController.shared.dismiss()
            return .handled
        }
        .onChange(of: viewModel.phase) { _, phase in
            handlePhaseChange(phase)
        }
        .onAppear {
            handlePhaseChange(viewModel.phase)
        }
    }

    // MARK: - Phase helpers

    private var showInput: Bool {
        viewModel.phase == .listening || viewModel.phase == .conversing
    }

    private var showConversation: Bool {
        viewModel.phase == .conversing && viewModel.hasMessages
    }

    private var pillOpacity: Double {
        switch viewModel.phase {
        case .hidden:    return 0
        case .dismissing: return 0
        case .appearing: return reduceMotion ? 1 : 0.5
        default:         return 1
        }
    }

    private var novaStateForPhase: NovaState {
        switch viewModel.phase {
        case .conversing where viewModel.isStreaming: return .responding
        case .conversing:                             return .success
        default:                                      return .idle
        }
    }

    private func handlePhaseChange(_ phase: MiniChatPanelViewModel.Phase) {
        switch phase {
        case .listening:
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(duration: 0.40, bounce: 0.10)) {
                inputPillWidth = fullInputWidth
            }
            // Delay focus slightly so the expansion animation is visible first
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.12)) {
                inputFocused = true
            }
        case .hidden, .dismissing:
            inputPillWidth = novaSlotWidth
            inputFocused = false
        default:
            break
        }
    }

    // MARK: - Compact pill (Nova right-anchored, input expands left)

    private var compactPill: some View {
        ZStack(alignment: .trailing) {
            // ── Pill background ──
            // Width grows leftward; Nova stays at the right edge
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.13), radius: 16, x: 0, y: 5)
                .overlay(
                    Capsule().stroke(Color.oDivider.opacity(0.35), lineWidth: 0.5)
                )
                .frame(width: inputPillWidth, height: pillHeight)

            // ── Input field (grows into the left of the pill) ──
            if showInput {
                HStack(spacing: 0) {
                    TextField("Ask anything…", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            if viewModel.canSend { Task { await viewModel.send() } }
                            return .handled
                        }
                        .accessibilityLabel("Mini-Chat input")
                        .padding(.leading, OSpacing.md)
                        .padding(.trailing, OSpacing.xs)

                    sendButton
                        .padding(.trailing, novaSlotWidth + 4)
                }
                .frame(width: inputPillWidth, height: pillHeight)
                .transition(
                    reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)),
                        removal:   .opacity
                    )
                )
            }

            // ── Nova — right anchor ──
            // NovaView provides glow + orbital particles + float animation.
            // It overflows the pill (glow extends beyond the capsule shape),
            // creating the ambient anchor effect.
            novaOrb
                .frame(width: novaSlotWidth, height: pillHeight)
                .allowsHitTesting(false)
        }
        // The pill's overall frame is centered relative to the screen;
        // as inputPillWidth grows, the pill extends leftward from Nova's position.
        .frame(width: inputPillWidth, height: pillHeight)
    }

    // MARK: - Nova orb (right cap of the pill)

    private var novaOrb: some View {
        ZStack {
            if reduceMotion {
                // Static: just the image with a gentle glow ring
                Circle()
                    .fill(Color.oOrbGlow.opacity(0.25))
                    .frame(width: novaDisplaySize + 8, height: novaDisplaySize + 8)
                    .blur(radius: 6)

                Image("Nova")
                    .resizable()
                    .scaledToFit()
                    .frame(width: novaDisplaySize, height: novaDisplaySize)
                    .clipShape(Circle())
            } else {
                // Full Nova: ambient glow, orbital particles, float — from the
                // existing NovaView component. The 1.8× canvas size lets the glow
                // radiate naturally beyond the pill boundary.
                NovaView(state: novaStateForPhase, size: novaDisplaySize)
            }
        }
        .scaleEffect(scaleForPhase)
        .animation(
            reduceMotion
                ? .linear(duration: 0.15)
                : .spring(duration: 0.45, bounce: 0.06),
            value: viewModel.phase
        )
    }

    private var scaleForPhase: CGFloat {
        switch viewModel.phase {
        case .hidden, .dismissing: return reduceMotion ? 1.0 : 0.50
        case .appearing:           return reduceMotion ? 1.0 : 0.82
        default:                   return 1.0
        }
    }

    // MARK: - Send / cancel button

    @ViewBuilder
    private var sendButton: some View {
        if viewModel.isStreaming {
            Button { viewModel.cancel() } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.oWarningAmber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop response")
        } else {
            Button { Task { await viewModel.send() } } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(viewModel.canSend
                        ? Color.oAccent
                        : Color.oTextTertiary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send")
        }
    }

    // MARK: - Conversation card

    private var conversationCard: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { msg in
                            messageBubble(msg).id(msg.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(OSpacing.md)
                }
                .frame(maxHeight: 340)
                .onChange(of: viewModel.messages.count) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                Button("Open in Orbit") { escalateToMainApp() }
                    .buttonStyle(.plain)
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)

                Spacer()

                Button("Clear") {
                    withAnimation { viewModel.clearSession() }
                }
                .buttonStyle(.plain)
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)

                Button("Dismiss") { NovaOverlayViewController.shared.dismiss() }
                    .buttonStyle(.plain)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextSecondary)
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
        }
        .frame(width: fullInputWidth)
        .background(
            RoundedRectangle(cornerRadius: ORadius.xl)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.13), radius: 18, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ORadius.xl)
                .stroke(Color.oDivider.opacity(0.35), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: ORadius.xl))
    }

    // MARK: - Message bubble

    @ViewBuilder
    private func messageBubble(_ msg: Message) -> some View {
        let isUser = msg.role == "user"
        let parsed = ReasoningParser.parse(msg.content)
        let cursor = msg.isStreaming ? "▍" : ""

        HStack(spacing: 0) {
            if isUser { Spacer(minLength: OSpacing.xxl) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if showReasoning && !isUser && parsed.hasReasoning {
                    Text(parsed.reasoning)
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                        .padding(.horizontal, OSpacing.sm)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: ORadius.sm)
                                .fill(Color.oSurfaceSecondary)
                        )
                        .lineLimit(3)
                }

                messageContent(msg: msg, isUser: isUser, parsed: parsed, cursor: cursor)
                    .padding(.horizontal, OSpacing.sm)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.lg)
                            .fill(isUser ? Color.oAccent : Color.oSurface.opacity(0.7))
                    )

                if msg.isInterrupted {
                    Text("Interrupted")
                        .font(.oMicro)
                        .foregroundStyle(Color.oWarningAmber)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if !isUser { Spacer(minLength: OSpacing.xxl) }
        }
    }

    @ViewBuilder
    private func messageContent(msg: Message, isUser: Bool,
                                 parsed: ReasoningParser.Result, cursor: String) -> some View {
        if msg.isStreaming && parsed.visible.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    NovaMiniDot(delay: Double(i) * 0.18)
                }
            }
        } else {
            Text((isUser ? msg.content : parsed.visible) + cursor)
                .font(.oBody)
                .foregroundStyle(isUser ? Color.oTextInverse : Color.oTextPrimary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Error note

    private func errorNote(_ message: String) -> some View {
        HStack(spacing: OSpacing.xs) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.oWarningAmber)
            Text(message)
                .font(.oMicro)
                .foregroundStyle(Color.oTextSecondary)
        }
        .padding(.horizontal, OSpacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: ORadius.sm)
                .fill(Color.oWarningAmber.opacity(0.08))
        )
    }

    // MARK: - Escalation

    private func escalateToMainApp() {
        NovaOverlayViewController.shared.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            AppState.current?.route = .newChat
        }
    }
}

// MARK: - Thinking dot

private struct NovaMiniDot: View {
    let delay: Double
    @State private var scale: CGFloat = 0.5
    var body: some View {
        Circle()
            .fill(Color.oTextTertiary)
            .frame(width: 5, height: 5)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) { scale = 1.0 }
            }
    }
}
