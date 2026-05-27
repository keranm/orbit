import SwiftUI

/// Settings > Mesh — lets users connect to private or public meshes.
///
/// Privacy rules enforced here:
/// - No automatic mesh joining
/// - Public mesh requires explicit consent before joining
/// - Private and public mesh states are always visually distinct
struct MeshSection: View {
    @Environment(AppState.self) private var appState

    @State private var privateTokenInput = ""
    @State private var showPublicDiscovery = false
    @State private var discoveredMeshes: [DiscoveredMesh] = []
    @State private var isDiscovering = false
    @State private var hoveredFindMesh = false
    @State private var discoverError: String?
    @State private var pendingPublicJoin: DiscoveredMesh?
    @State private var joinError: String?
    @State private var isJoining = false

    private var rm: RuntimeAdapter { appState.runtimeManager }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current status
            statusCard

            // Actions based on current state
            switch rm.meshConnectionState {
            case .disconnected:
                connectOptions

            case .connectingPrivate, .connectingPublic, .reconnecting:
                connectingState

            case .connectedPrivate(let n):
                connectedPrivateCard(peerCount: n)

            case .connectedPublic(let n):
                connectedPublicCard(peerCount: n)

            case .error(let msg):
                errorCard(msg)
            }
        }
        .sheet(item: $pendingPublicJoin) { mesh in
            publicConsentSheet(mesh: mesh)
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        settingGroup {
            HStack(spacing: OSpacing.md) {
                ZStack {
                    Circle()
                        .fill(meshDotColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(meshDotColor)
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(meshStatusTitle)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text(meshStatusSubtitle)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
        }
    }

    private var meshDotColor: Color {
        switch rm.meshConnectionState {
        case .disconnected:             return Color.oTextTertiary
        case .connectedPrivate:         return Color.oMeshTeal
        case .connectedPublic:          return Color.oAccent
        case .connectingPrivate,
             .connectingPublic,
             .reconnecting:             return Color.oWarningAmber
        case .error:                    return Color.oErrorRed
        }
    }

    private var meshStatusTitle: String {
        switch rm.meshConnectionState {
        case .disconnected:                  return "Private to this Mac"
        case .connectedPrivate:              return "Connected to your devices"
        case .connectedPublic:               return "Connected to shared mesh"
        case .connectingPrivate:             return "Connecting to your mesh…"
        case .connectingPublic:              return "Connecting to shared mesh…"
        case .reconnecting:                  return "Reconnecting…"
        case .error:                         return "Connection error"
        }
    }

    private var meshStatusSubtitle: String {
        switch rm.meshConnectionState {
        case .disconnected:
            return "Orbit is running only on this Mac."
        case .connectedPrivate(let n):
            return "\(n) \(n == 1 ? "device" : "devices") connected."
        case .connectedPublic(let n):
            return "\(n) \(n == 1 ? "participant" : "participants") in the shared mesh."
        case .connectingPrivate, .connectingPublic, .reconnecting:
            return "This may take a few seconds."
        case .error(let msg):
            return msg
        }
    }

    // MARK: - Connect options (disconnected state)

    private var connectOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Your Devices")

            settingGroup {
                VStack(alignment: .leading, spacing: OSpacing.sm) {
                    Text("Connect another Mac you trust. Models can run across your own devices while staying in your private mesh.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Your invite token
                    if let token = rm.localInviteToken {
                        VStack(alignment: .leading, spacing: OSpacing.xs) {
                            Text("Share this token with your other Mac:")
                                .font(.oMicro)
                                .foregroundStyle(Color.oTextTertiary)
                            HStack(spacing: OSpacing.xs) {
                                Text(String(token.prefix(24)) + "…")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.oTextSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(token, forType: .string)
                                }
                                .buttonStyle(.plain)
                                .font(.oMicroMed)
                                .foregroundStyle(Color.oAccent)
                            }
                        }
                        .padding(OSpacing.sm)
                        .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oBackground))
                    }

                    HStack(spacing: OSpacing.sm) {
                        TextField("Paste invite token from other Mac…", text: $privateTokenInput)
                            .textFieldStyle(.plain)
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextPrimary)
                            .padding(OSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.md)
                                    .fill(Color.oBackground)
                                    .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider, lineWidth: 0.5))
                            )

                        Button("Connect") {
                            joinPrivate()
                        }
                        .buttonStyle(.plain)
                        .font(.oBodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, OSpacing.md)
                        .padding(.vertical, OSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ORadius.pill)
                                .fill(privateTokenInput.count > 20 ? Color.oMeshTeal : Color.oTextTertiary)
                        )
                        .disabled(privateTokenInput.count < 20 || isJoining)
                    }
                }
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, OSpacing.sm)
            }

            if let err = joinError {
                Text(err)
                    .font(.oCaption)
                    .foregroundStyle(Color.oWarningAmber)
                    .padding(.horizontal, OSpacing.md)
                    .padding(.top, OSpacing.xs)
            }

            sectionLabel("Shared Mesh")

            settingGroup {
                Button {
                    startDiscovery()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find a shared mesh")
                                .font(.oBodyMedium)
                                .foregroundStyle(Color.oTextPrimary)
                            Text("Access larger models through publicly available meshes.")
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextSecondary)
                        }
                        Spacer()
                        if isDiscovering {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.oTextTertiary)
                        }
                    }
                    .padding(.horizontal, OSpacing.md)
                    .padding(.vertical, OSpacing.sm)
                    .background(hoveredFindMesh ? Color.oSurfaceSecondary : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredFindMesh = $0 }
            }

            if !discoveredMeshes.isEmpty {
                discoveryResults
            }

            if let err = discoverError {
                Text(err)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .padding(.horizontal, OSpacing.md)
                    .padding(.top, OSpacing.xs)
            }
        }
    }

    private var discoveryResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Available meshes")
            settingGroup {
                VStack(spacing: 0) {
                    ForEach(Array(discoveredMeshes.enumerated()), id: \.element.id) { i, mesh in
                        if i > 0 { Divider().padding(.leading, OSpacing.md) }
                        discoveredMeshRow(mesh)
                    }
                }
            }
        }
    }

    private func discoveredMeshRow(_ mesh: DiscoveredMesh) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OSpacing.xs) {
                    Text(mesh.displayName)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    sharedBadge
                }
                Text(mesh.modelSummary)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineLimit(1)
                if let nodes = mesh.nodeCount, let clients = mesh.clientCount {
                    Text("\(nodes) nodes · \(clients) participants")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }
            }
            Spacer()
            Button("Join") {
                pendingPublicJoin = mesh
            }
            .buttonStyle(.plain)
            .font(.oCaptionMed)
            .foregroundStyle(Color.oWarningAmber)
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oWarningAmber.opacity(0.10)))
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    // MARK: - Connecting / connected states

    private var connectingState: some View {
        settingGroup {
            HStack(spacing: OSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                Spacer()
                Button("Cancel") { Task { await rm.leaveMesh() } }
                    .buttonStyle(.plain)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
        }
    }

    private func connectedPrivateCard(peerCount: Int) -> some View {
        settingGroup {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Connected to your devices")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    Button("Disconnect") { Task { await rm.leaveMesh() } }
                        .buttonStyle(.plain)
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oTextSecondary)
                }
                .padding(.horizontal, OSpacing.md)
                .padding(.top, OSpacing.sm)

                Text("\(peerCount) \(peerCount == 1 ? "device" : "devices") in your private mesh.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .padding(.horizontal, OSpacing.md)
                    .padding(.bottom, OSpacing.sm)

                if !rm.meshModels.isEmpty {
                    Divider().padding(.leading, OSpacing.md)
                    HStack {
                        Text("\(rm.meshModels.count) models available through the mesh")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, OSpacing.md)
                    .padding(.vertical, OSpacing.xs)
                }
            }
        }
    }

    private func connectedPublicCard(peerCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            settingGroup {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: OSpacing.xs) {
                            Text("Connected to shared mesh")
                                .font(.oBodyMedium)
                                .foregroundStyle(Color.oTextPrimary)
                            sharedBadge
                        }
                        Spacer()
                        Button("Disconnect") { Task { await rm.leaveMesh() } }
                            .buttonStyle(.plain)
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oTextSecondary)
                    }
                    .padding(.horizontal, OSpacing.md)
                    .padding(.top, OSpacing.sm)

                    Text("\(peerCount) participants. Conversations may be processed by other participants' computers.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                        .padding(.horizontal, OSpacing.md)
                        .padding(.bottom, OSpacing.sm)
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        settingGroup {
            HStack(spacing: OSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.oWarningAmber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't connect to the mesh")
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oTextPrimary)
                    Text(message)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
                Spacer()
                Button("Try again") {
                    Task {
                        await rm.leaveMesh()
                    }
                }
                .buttonStyle(.plain)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oAccent)
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
        }
    }

    // MARK: - Public consent sheet

    private func publicConsentSheet(mesh: DiscoveredMesh) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            HStack {
                Text("Join shared mesh?")
                    .font(.oTitle2)
                    .foregroundStyle(Color.oTextPrimary)
                Spacer()
                Button { pendingPublicJoin = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.oTextSecondary)
                        .padding(5)
                        .background(Circle().fill(Color.oSurfaceSecondary))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: OSpacing.sm) {
                HStack(spacing: OSpacing.xs) {
                    Text(mesh.displayName)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    sharedBadge
                }
                if let nodes = mesh.nodeCount, let clients = mesh.clientCount {
                    Text("\(nodes) nodes · \(clients) participants")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                }
            }
            .padding(OSpacing.md)
            .background(RoundedRectangle(cornerRadius: ORadius.lg).fill(Color.oSurfaceSecondary))

            VStack(alignment: .leading, spacing: OSpacing.sm) {
                HStack(alignment: .top, spacing: OSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.oWarningAmber)
                        .font(.system(size: 14))
                    Text("This model runs on shared computers. Your conversations may be processed by other mesh participants. Only continue if you are comfortable with that.")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(OSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oWarningAmber.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oWarningAmber.opacity(0.2), lineWidth: 1))
            )

            HStack {
                Button("Cancel") { pendingPublicJoin = nil }
                    .buttonStyle(.plain)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)

                Spacer()

                Button("I understand — join mesh") {
                    pendingPublicJoin = nil
                    Task {
                        await joinPublic(mesh)
                    }
                }
                .buttonStyle(.plain)
                .font(.oBodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.lg)
                .padding(.vertical, OSpacing.sm)
                .background(RoundedRectangle(cornerRadius: ORadius.pill).fill(Color.oWarningAmber))
            }
        }
        .padding(OSpacing.xl)
        .frame(width: 460)
        .background(Color.oBackground)
    }

    // MARK: - Actions

    private func joinPrivate() {
        let token = privateTokenInput.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        joinError = nil
        isJoining = true
        Task {
            await rm.joinPrivateMesh(inviteToken: token)
            privateTokenInput = ""
            isJoining = false
        }
    }

    private func joinPublic(_ mesh: DiscoveredMesh) async {
        joinError = nil
        UserDefaults.standard.set(true, forKey: "publicMeshConsentAcknowledged")
        await rm.joinPublicMesh(inviteToken: mesh.inviteToken, seedModelNames: mesh.modelNames)
    }

    private func startDiscovery() {
        isDiscovering = true
        discoverError = nil
        discoveredMeshes = []
        Task {
            do {
                let results = try await rm.discoverPublicMeshes()
                discoveredMeshes = results
                if results.isEmpty {
                    discoverError = "Orbit couldn't find shared meshes right now. You can try again later."
                }
            } catch {
                discoverError = "Orbit couldn't find shared meshes right now. You can try again later."
            }
            isDiscovering = false
        }
    }

    // MARK: - Shared badge

    private var sharedBadge: some View {
        Text("Shared")
            .font(.oMicroMed)
            .foregroundStyle(Color.oWarningAmber)
            .padding(.horizontal, OSpacing.xs)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.oWarningAmber.opacity(0.12)))
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
