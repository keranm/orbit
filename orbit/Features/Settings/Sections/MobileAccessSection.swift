import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI

struct MobileAccessSection: View {
    @Environment(AppState.self) private var appState
    @State private var vm = MobileAccessViewModel()

    @State private var showQRSheet        = false
    @State private var showRenameMacSheet = false
    @State private var deviceToForget:  MobileAccessViewModel.PairedDevice? = nil
    @State private var deviceToRename:  MobileAccessViewModel.PairedDevice? = nil
    @State private var showCopiedToast  = false

    private var runtimeReady: Bool {
        if case .ready = appState.runtimeStatus { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chat with your Mac from your iPhone on the same Wi‑Fi network.")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
                .padding(.bottom, OSpacing.lg)

            if !runtimeReady {
                runtimeBanner
                    .padding(.bottom, OSpacing.md)
            }

            toggleCard

            sectionLabel("Status")
            statusCard

            pairedDevicesHeader
            pairedDevicesCard

            sectionLabel("How to Connect")
            howToConnectCard

            Spacer(minLength: OSpacing.xl)
            footer
        }
        .sheet(isPresented: $showQRSheet) {
            QRPairingSheet(vm: vm)
        }
        .sheet(isPresented: $showRenameMacSheet) {
            RenameSheet(title: "Rename Mac", initialValue: vm.macDisplayName, maxLength: 40) {
                vm.macDisplayName = $0
            }
        }
        .sheet(item: $deviceToRename) { device in
            RenameSheet(title: "Rename Device", initialValue: device.displayName, maxLength: 40) {
                vm.renameDevice(device, to: $0)
            }
        }
        .confirmationDialog(
            "Forget this device?",
            isPresented: Binding(get: { deviceToForget != nil }, set: { if !$0 { deviceToForget = nil } }),
            titleVisibility: .visible,
            presenting: deviceToForget
        ) { device in
            Button("Forget Device", role: .destructive) {
                vm.forgetDevice(device)
                deviceToForget = nil
            }
            Button("Cancel", role: .cancel) { deviceToForget = nil }
        } message: { _ in
            Text("This device will need to pair again before it can connect to Orbit on this Mac.")
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                copiedToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, OSpacing.md)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
        .task {
            vm.coordinator = appState.mobileAccessCoordinator
            await vm.refreshNetworkStatus()
        }
    }

    // MARK: - Runtime banner

    private var runtimeBanner: some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.oWarningAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Orbit isn't running fully")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Start Orbit before enabling Mobile Access.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Button("Start Orbit") {
                // stub
            }
            .buttonStyle(.plain)
            .font(.oCaptionMed)
            .foregroundStyle(Color.oAccent)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oWarningAmber.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: ORadius.lg)
                    .stroke(Color.oWarningAmber.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - Toggle card

    private var toggleCard: some View {
        settingGroup {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mobile Access")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Allow Orbit Mobile to connect to this Mac.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                    if !runtimeReady {
                        Text("Orbit needs to be running before Mobile Access can be enabled.")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                            .padding(.top, 1)
                    }
                    if case .error(let msg) = vm.toggleState {
                        Text(msg)
                            .font(.oCaption)
                            .foregroundStyle(Color.oErrorRed)
                            .padding(.top, 1)
                    }
                }
                Spacer()
                Group {
                    if vm.isTransitioning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 51)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { vm.isEnabled },
                            set: { on in Task { await vm.setEnabled(on) } }
                        ))
                        .toggleStyle(.switch)
                        .tint(Color.oAccent)
                        .labelsHidden()
                        .disabled(!runtimeReady)
                        .accessibilityLabel("Mobile Access. Allows Orbit Mobile to connect to this Mac.")
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: vm.isTransitioning)
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        settingGroup {
            networkRow
            Divider().padding(.leading, OSpacing.md + 20 + OSpacing.sm)
            macNameRow
            Divider().padding(.leading, OSpacing.md + 20 + OSpacing.sm)
            accessStatusRow
        }
    }

    private var networkRow: some View {
        HStack(spacing: OSpacing.sm) {
            statusIconView("wifi", color: vm.networkIsHealthy ? Color.oSuccessGreen : Color.oWarningAmber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Network")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                Text(vm.networkLabel)
                    .font(.oCaption)
                    .foregroundStyle(vm.networkIsHealthy ? Color.oTextSecondary : Color.oWarningAmber)
            }
            Spacer()
            if vm.isEnabled && !vm.networkIsHealthy {
                Text("Connect this Mac to Wi‑Fi so Orbit Mobile can find it.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
            }
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private var macNameRow: some View {
        HStack(spacing: OSpacing.sm) {
            statusIconView("desktopcomputer", color: Color.oTextTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mac Name")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                Text(vm.macDisplayName)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Button("Edit…") { showRenameMacSheet = true }
                .buttonStyle(.plain)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oAccent)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private var accessStatusRow: some View {
        HStack(spacing: OSpacing.sm) {
            statusIconView(statusIconName, color: statusIconColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Status")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                Text(vm.statusLabel)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private var statusIconName: String {
        switch vm.toggleState {
        case .on where vm.networkIsHealthy: return "checkmark.shield.fill"
        case .on:                           return "shield"
        case .off, .turningOff:             return "shield"
        case .turningOn:                    return "shield"
        case .error:                        return "exclamationmark.shield.fill"
        }
    }

    private var statusIconColor: Color {
        switch vm.toggleState {
        case .on where vm.networkIsHealthy: return Color.oSuccessGreen
        case .on:                           return Color.oWarningAmber
        case .off, .turningOff:             return Color.oTextTertiary
        case .turningOn:                    return Color.oWarningAmber
        case .error:                        return Color.oErrorRed
        }
    }

    private func statusIconView(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(color)
            .frame(width: 20)
    }

    // MARK: - Paired Devices

    private var pairedDevicesHeader: some View {
        HStack {
            Text("PAIRED DEVICES")
                .font(.oMicroMed)
                .foregroundStyle(Color.oTextTertiary)
            Spacer()
            Button("Manage Devices…") {
                // stub: future device management screen
            }
            .buttonStyle(.plain)
            .font(.oCaptionMed)
            .foregroundStyle(Color.oAccent)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.top, OSpacing.lg)
        .padding(.bottom, OSpacing.xs)
    }

    private var pairedDevicesCard: some View {
        settingGroup {
            if vm.pairedDevices.isEmpty {
                emptyDevices
            } else {
                ForEach(Array(vm.pairedDevices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { Divider().padding(.leading, OSpacing.md) }
                    deviceRow(device)
                }
            }
        }
    }

    private var emptyDevices: some View {
        VStack(spacing: OSpacing.xs) {
            Text("No paired devices yet.")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
            Text("Open Orbit Mobile on your iPhone and pair it with this Mac.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.lg)
    }

    private func deviceRow(_ device: MobileAccessViewModel.PairedDevice) -> some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: device.systemName)
                .font(.system(size: 18))
                .foregroundStyle(Color.oTextTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OSpacing.xs) {
                    Text(device.displayName)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    if device.isConnected {
                        Circle()
                            .fill(Color.oSuccessGreen)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(device.lastSeenLabel)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
            }
            Spacer()
            Menu {
                Button("Rename Device") { deviceToRename = device }
                Button("Disconnect") { vm.disconnectDevice(device) }
                    .disabled(!device.isConnected)
                Divider()
                Button("Forget Device", role: .destructive) { deviceToForget = device }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.oTextSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .accessibilityLabel("Manage paired device")
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    // MARK: - How to Connect card

    private var howToConnectCard: some View {
        VStack(alignment: .leading, spacing: OSpacing.md) {
            Text("How to connect")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                stepRow(n: 1, text: "Open Orbit Mobile on your iPhone.")
                stepRow(n: 2, text: "Make sure it's on the same Wi‑Fi network.")
                stepRow(n: 3, text: "Select this Mac to connect.")
            }
            HStack(spacing: OSpacing.sm) {
                connectActionButton("Show QR Code…") {
                    if vm.pairingCode.isEmpty || vm.isPairingCodeExpired { vm.generatePairingCode() }
                    showQRSheet = true
                }
                .disabled(!vm.isEnabled)
                .accessibilityLabel("Show QR code for pairing Orbit Mobile.")

                connectActionButton("Copy Pairing Code…") {
                    vm.copyPairingCodeToClipboard()
                    showCopiedToast = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showCopiedToast = false
                    }
                }
                .disabled(!vm.isEnabled)
                .accessibilityLabel("Copy pairing code for Orbit Mobile.")
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oAccentSoft)
                .overlay(RoundedRectangle(cornerRadius: ORadius.lg)
                    .stroke(Color.oAccentMid, lineWidth: 0.5))
        )
    }

    private func stepRow(n: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OSpacing.sm) {
            Text("\(n).")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oAccent)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
        }
    }

    private func connectActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oAccent)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.md)
                        .fill(Color.oSurface)
                        .overlay(RoundedRectangle(cornerRadius: ORadius.md)
                            .stroke(Color.oAccentMid, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: OSpacing.xs) {
                Image(systemName: "lock")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.oTextTertiary)
                Text("Changes are saved automatically.")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
            }
            HStack(spacing: OSpacing.xs) {
                Image(systemName: "lock")
                    .font(.system(size: 10))
                    .foregroundStyle(.clear)
                Text("Connections are encrypted and verified between your devices.")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
            }
        }
        .padding(.top, OSpacing.md)
    }

    // MARK: - Toast

    private var copiedToast: some View {
        Text("Pairing code copied.")
            .font(.oCaption)
            .foregroundStyle(Color.oTextInverse)
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
            .background(Capsule().fill(Color.oTextPrimary.opacity(0.88)))
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.oMicroMed)
            .foregroundStyle(Color.oTextTertiary)
            .padding(.horizontal, OSpacing.md)
            .padding(.top, OSpacing.lg)
            .padding(.bottom, OSpacing.xs)
    }

    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
            .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 0.5))
    }
}

// MARK: - QR code generation

private func makeQRImage(_ payload: String) -> NSImage? {
    guard !payload.isEmpty else { return nil }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(payload.utf8)
    filter.correctionLevel = "M"
    guard let ci = filter.outputImage else { return nil }
    // Scale up so the image is sharp on Retina displays
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    let context = CIContext()
    guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
}

// MARK: - QRPairingSheet

private struct QRPairingSheet: View {
    let vm: MobileAccessViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var secondsRemaining: Int = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timerLabel: String {
        String(format: "Expires in %d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OSpacing.xl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pair Orbit Mobile")
                        .font(.oTitle2)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Scan this code with Orbit Mobile to connect to this Mac.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.oTextSecondary)
                        .padding(6)
                        .background(Circle().fill(Color.oSurfaceSecondary))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: OSpacing.md) {
                Group {
                    if let qrImage = makeQRImage(vm.qrPayload), !vm.qrPayload.isEmpty {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .padding(OSpacing.lg)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 140))
                            .foregroundStyle(Color.oTextPrimary)
                            .padding(OSpacing.lg)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: ORadius.lg)
                        .fill(Color.oSurface)
                        .overlay(RoundedRectangle(cornerRadius: ORadius.lg)
                            .stroke(Color.oDivider, lineWidth: 0.5))
                )

                Text(vm.pairingCode)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.oTextPrimary)
                    .kerning(4)

                if secondsRemaining > 0 {
                    Text(timerLabel)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                } else {
                    Text("Code expired — generating new code…")
                        .font(.oCaption)
                        .foregroundStyle(Color.oWarningAmber)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: OSpacing.sm) {
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurfaceSecondary))

                Button("Copy Code") { vm.copyPairingCodeToClipboard() }
                    .buttonStyle(.plain)
                    .font(.oBodyMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccent))
            }
        }
        .padding(OSpacing.xl)
        .frame(width: 360)
        .background(Color.oBackground)
        .onAppear {
            secondsRemaining = max(0, Int((vm.pairingCodeExpiresAt ?? Date()).timeIntervalSinceNow))
        }
        .onReceive(ticker) { _ in
            let remaining = max(0, Int((vm.pairingCodeExpiresAt ?? Date()).timeIntervalSinceNow))
            if remaining == 0 && secondsRemaining > 0 { vm.generatePairingCode() }
            secondsRemaining = remaining
        }
        .onChange(of: vm.pairingCode) {
            secondsRemaining = max(0, Int((vm.pairingCodeExpiresAt ?? Date()).timeIntervalSinceNow))
        }
    }
}

// MARK: - RenameSheet

private struct RenameSheet: View {
    let title: String
    let initialValue: String
    let maxLength: Int
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var didAppear = false

    private var saveDisabled: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            Text(title)
                .font(.oTitle2)
                .foregroundStyle(Color.oTextPrimary)

            TextField("Name", text: Binding(
                get: { name },
                set: { name = String($0.prefix(maxLength)) }
            ))
            .textFieldStyle(.plain)
            .font(.oBody)
            .foregroundStyle(Color.oTextPrimary)
            .padding(OSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: ORadius.md)
                    .fill(Color.oSurfaceSecondary)
                    .overlay(RoundedRectangle(cornerRadius: ORadius.md)
                        .stroke(Color.oDivider, lineWidth: 0.5))
            )
            .onSubmit {
                guard !saveDisabled else { return }
                onSave(name.trimmingCharacters(in: .whitespaces))
                dismiss()
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                Spacer()
                Button("Save") {
                    onSave(name.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.oBodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.lg)
                .padding(.vertical, OSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(saveDisabled ? Color.oTextTertiary : Color.oAccent)
                )
                .disabled(saveDisabled)
            }
        }
        .padding(OSpacing.xl)
        .frame(width: 380)
        .background(Color.oBackground)
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            name = initialValue
        }
    }
}

#Preview {
    MobileAccessSection()
        .environment(AppState())
        .padding(OSpacing.xl)
        .frame(width: 520, height: 700)
        .background(Color.oBackground)
}
