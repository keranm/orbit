import SwiftUI
import SwiftData

struct ProDashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var meshViewMode = "Map"
    @State private var recentRuns: [PromptRunRecord] = []
    @State private var currentCPU: Double = 0
    @State private var pollTask: Task<Void, Never>?
    @State private var showActivitySheet = false
    @State private var selectedTimeRange: TimeRange = .last24h

    enum TimeRange: String, CaseIterable {
        case last24h = "Last 24 Hours"
        case last7d = "Last 7 Days"
        case last30d = "Last 30 Days"

        var dateThreshold: Date {
            let seconds: TimeInterval
            switch self {
            case .last24h: seconds = 86400
            case .last7d:  seconds = 604800
            case .last30d: seconds = 2592000
            }
            return Date.now.addingTimeInterval(-seconds)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dashHeader
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: OSpacing.md) {
                    VStack(alignment: .leading, spacing: OSpacing.md) {
                        metricsRow
                        HStack(alignment: .top, spacing: OSpacing.md) {
                            meshNetworkPanel
                            networkTrafficPanel
                        }
                        HStack(alignment: .top, spacing: OSpacing.md) {
                            inferenceLoadPanel
                            recentActivityPanel
                        }
                    }
                    VStack(spacing: OSpacing.md) {
                        modelsPanel
                        systemResourcesPanel
                    }
                    .frame(width: 260)
                }
                .padding(OSpacing.md)
            }
            ProStatusBar(dashboardVariant: true)
        }
        .background(Color.oBackground)
        .sheet(isPresented: $showActivitySheet) {
            activitySheet
        }
        .onAppear {
            pollSystemResources()
            fetchRecentRuns()
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: - Polling

    private func pollSystemResources() {
        pollTask?.cancel()
        pollTask = Task { [weak rm = appState.runtimeManager] in
            while !Task.isCancelled {
                guard let rm else { break }
                currentCPU = rm.systemResources.cpuUsage()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func fetchRecentRuns() {
        let threshold = selectedTimeRange.dateThreshold
        let descriptor = FetchDescriptor<PromptRunRecord>(
            predicate: #Predicate { $0.runAt >= threshold },
            sortBy: [SortDescriptor(\.runAt, order: .reverse)]
        )
        recentRuns = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Header

    private var meshDotColor: Color {
        appState.runtimeManager.meshConnectionState.isConnected
            ? Color.oSuccessGreen : Color.oTextTertiary
    }

    private var dashHeader: some View {
        HStack(spacing: OSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pro Dashboard")
                    .font(.oLargeTitle)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Real-time overview of your AI runtime, models, and mesh activity.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Menu {
                ForEach(TimeRange.allCases, id: \.rawValue) { range in
                    Button(range.rawValue) {
                        selectedTimeRange = range
                        fetchRecentRuns()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedTimeRange.rawValue)
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.oTextTertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            HStack(spacing: OSpacing.xs) {
                Circle()
                    .fill(meshDotColor)
                    .frame(width: 7, height: 7)
                Text(appState.runtimeManager.meshConnectionState.statusLabel)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextPrimary)
                if let count = appState.runtimeManager.meshConnectionState.peerCountOptional {
                    Text("\(count) peers")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, OSpacing.xs)
            .background(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.md)
        .background(Color.oSurface)
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack(spacing: OSpacing.sm) {
            metricTile("Total Inference",
                       value: formattedCount(metrics?.requestCount),
                       unit: "requests", source: .live)
            metricTile("Tokens Processed",
                       value: formattedTokenCount(metrics?.completionTokensObserved),
                       unit: "tokens", source: .live)
            metricTile("Avg. Latency",
                       value: metrics.map { String(format: "%.0f", $0.avgAttemptMs ?? 0) } ?? "—",
                       unit: "ms", source: metrics?.avgAttemptMs != nil ? .live : .unavailable)
            let localShare = metrics?.pressure?.localServiceShare
            metricTile("Local First",
                       value: localShare.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                       unit: "of requests", source: localShare != nil ? .live : .unavailable)
        }
    }

    private var metrics: RoutingMetrics? {
        appState.runtimeManager.routingMetrics
    }

    private enum MetricSource {
        case live, unavailable
    }

    private func metricTile(_ title: String, value: String, unit: String, source: MetricSource) -> some View {
        let isUnavailable = source == .unavailable
        return VStack(alignment: .leading, spacing: OSpacing.xs) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.oCaption)
                    .foregroundStyle(isUnavailable ? Color.oTextTertiary : Color.oTextSecondary)
                if isUnavailable {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.oTextTertiary)
                }
            }
            Text(value)
                .font(.oLargeTitle)
                .foregroundStyle(isUnavailable ? Color.oTextTertiary : Color.oTextPrimary)
            Text(unit)
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
            if isUnavailable {
                Text("No data source")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
            }
        }
        .padding(OSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(isUnavailable ? Color.oSurface : Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 1))
        .opacity(isUnavailable ? 0.55 : 1)
    }

    // MARK: - Mesh Network Panel

    private var meshNetworkPanel: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("Mesh Network")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextTertiary)
                let pc = appState.runtimeManager.meshConnectionState.peerCountOptional ?? 0
                Text("\(pc) peers online")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                Spacer()
                Picker("", selection: $meshViewMode) {
                    Text("Map").tag("Map")
                    Text("Table").tag("Table")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            if meshViewMode == "Map" {
                meshNodeGraph
                    .frame(height: 240)
            } else {
                meshTable
                    .frame(height: 240)
            }

            HStack(spacing: OSpacing.md) {
                legendItem(solid: true, label: "Active")
                legendItem(solid: false, label: "Idle")
                HStack(spacing: 4) {
                    Circle().fill(Color.oSuccessGreen).frame(width: 6, height: 6)
                    Text("High Capacity").font(.oCaption).foregroundStyle(Color.oTextSecondary)
                }
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private func legendItem(solid: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(solid ? Color.oAccent : Color.clear)
                .frame(width: 16, height: 1.5)
                .overlay(
                    solid ? nil :
                    Rectangle().fill(Color.oTextTertiary).frame(width: 16, height: 1)
                        .mask(
                            HStack(spacing: 2) {
                                ForEach(0..<4, id: \.self) { _ in
                                    Rectangle().frame(width: 3, height: 1)
                                }
                            }
                        )
                )
            Text(label).font(.oCaption).foregroundStyle(Color.oTextSecondary)
        }
    }

    private var meshNodeGraph: some View {
        let peers = appState.runtimeManager.meshPeers
        let peerCount = appState.runtimeManager.meshConnectionState.peerCountOptional ?? 0
        if peers.isEmpty && peerCount == 0 {
            return AnyView(
                VStack(spacing: OSpacing.sm) {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.oTextTertiary)
                    Text("No peers connected")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextTertiary)
                    Text("Other nodes will appear here when they join the mesh.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            )
        }

        return AnyView(Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2

            let centerX = cx
            let centerY = cy
            let radius: CGFloat = 60

            var nodes: [(String, CGPoint, Bool)] = [
                ("This Mac (" + (appState.runtimeManager.systemResources.cpuModelLabel) + ")", CGPoint(x: cx, y: cy), true),
            ]

            for (i, peer) in peers.enumerated() {
                let angle = (Double(i) / Double(max(peers.count, 1))) * 2 * .pi - .pi / 2
                let px = centerX + cos(angle) * radius
                let py = centerY + sin(angle) * radius
                nodes.append((peer.name ?? peer.nodeId ?? "Peer \(i + 1)", CGPoint(x: px, y: py), false))
            }

            for node in nodes {
                let isCenter = node.2
                let nRadius: CGFloat = isCenter ? 16 : 10
                let rect = CGRect(x: node.1.x - nRadius, y: node.1.y - nRadius,
                                  width: nRadius * 2, height: nRadius * 2)
                ctx.fill(Circle().path(in: rect), with: .color(isCenter ? Color.oAccent.opacity(0.15) : Color.oSurfaceSecondary))
                ctx.stroke(Circle().path(in: rect), with: .color(isCenter ? Color.oAccent : Color.oDivider), style: StrokeStyle(lineWidth: isCenter ? 2 : 1))

                if isCenter {
                    let innerRect = CGRect(x: node.1.x - 5, y: node.1.y - 5, width: 10, height: 10)
                    ctx.fill(Circle().path(in: innerRect), with: .color(Color.oAccent))
                }

                let shortName = node.0.components(separatedBy: " (").first ?? node.0
                let nameText = Text(shortName).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.oTextPrimary)
                let yOffset = isCenter ? nRadius + 6 : nRadius + 4
                ctx.draw(nameText, at: CGPoint(x: node.1.x, y: node.1.y + yOffset), anchor: .top)
            }
        })
    }

    private var meshTable: some View {
        let peers = appState.runtimeManager.meshPeers
        if peers.isEmpty {
            return AnyView(
                VStack {
                    Spacer()
                    Text("No peers connected")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextTertiary)
                    Spacer()
                }
            )
        }
        return AnyView(
            VStack(spacing: 0) {
                ForEach(Array(peers.enumerated()), id: \.offset) { _, peer in
                    HStack {
                        Text(peer.name ?? peer.nodeId ?? "Unknown")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Connected")
                            .font(.oCaption)
                            .foregroundStyle(Color.oSuccessGreen)
                            .frame(width: 80)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, OSpacing.xs)
                    Divider()
                }
            }
        )
    }

    // MARK: - Inference Activity Panel

    private var networkTrafficPanel: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("Inference Activity")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Spacer()
                Text("tokens over time")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
            }
            VStack(spacing: OSpacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.oTextTertiary)
                Text("Token history will appear as you use the chat.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Models Panel

    private var modelsPanel: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("Models")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
                Button("Manage") { appState.route = .models }
                    .buttonStyle(.plain)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oAccent)
            }

            let models = appState.runtimeManager.installedModels
            if models.isEmpty {
                Text("No models installed")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(models.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: OSpacing.sm) {
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.oAccent)
                            .frame(width: 20)
                        Text(entry.displayName)
                            .font(.oBodyMedium)
                            .foregroundStyle(Color.oTextPrimary)
                        Text("Local")
                            .font(.oMicro)
                            .foregroundStyle(Color.oSuccessGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.oSuccessGreen.opacity(0.12)))
                        Spacer()
                        Text(entry.size ?? "—")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                        Circle()
                            .fill(Color.oSuccessGreen)
                            .frame(width: 6, height: 6)
                    }
                    .padding(.vertical, 4)
                    if entry.name != models.last?.name { Divider() }
                }
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 1))
    }

    // MARK: - System Resources Panel

    private var systemResourcesPanel: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            Text("System Resources")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)

            let rm = appState.runtimeManager
            let memTotal = rm.systemResources.totalMemory
            let memUsed = rm.systemResources.usedMemory
            let memFrac = memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0
            let memValue = "\(ByteCountFormatter.string(fromByteCount: Int64(memUsed), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(memTotal), countStyle: .binary))"

            resourceRow("CPU",
                        value: String(format: "%.0f%%", currentCPU),
                        data: [currentCPU / 100],
                        color: Color.oAccent)
            resourceRow("Memory",
                        value: memValue,
                        data: [memFrac],
                        color: .purple)
            resourceRow("GPU (\(rm.systemResources.gpuModelLabel ?? "—"))",
                        value: gpuVRAMString,
                        data: gpuVRAMFraction.map { [$0] } ?? [0],
                        color: Color.oWarningAmber)
            resourceRow("Disk",
                        value: diskUsageString,
                        data: [rm.systemResources.diskFraction],
                        color: Color.oAccent)
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 1))
    }

    private var gpuVRAMString: String {
        guard let gpu = appState.runtimeManager.gpuInfo?.first,
              let total = gpu.vramBytes,
              let reserved = gpu.reservedBytes
        else { return "—" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(reserved), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .binary))"
    }

    private var gpuVRAMFraction: Double? {
        guard let gpu = appState.runtimeManager.gpuInfo?.first,
              let total = gpu.vramBytes,
              let reserved = gpu.reservedBytes,
              total > 0
        else { return nil }
        return Double(reserved) / Double(total)
    }

    private var diskUsageString: String {
        let rm = appState.runtimeManager.systemResources
        guard let total = rm.totalDiskSpace, let free = rm.freeDiskSpace else { return "—" }
        let used = total - free
        return "\(ByteCountFormatter.string(fromByteCount: used, countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .binary))"
    }

    private func resourceRow(_ label: String, value: String, data: [CGFloat], color: Color) -> some View {
        HStack(spacing: OSpacing.sm) {
            Text(label)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
                .fixedSize()
            sparkline(data: data, color: color)
                .frame(width: 70, height: 22)
        }
    }

    private func sparkline(data: [CGFloat], color: Color) -> some View {
        Canvas { ctx, size in
            guard data.count > 1 else {
                // Single data point — draw a horizontal line at that level
                let h = size.height
                var path = Path()
                let y = data.first.map { h - $0 * h } ?? h
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5))
                return
            }
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h - data[0] * h))
            for i in 1..<data.count {
                path.addLine(to: CGPoint(x: CGFloat(i) / CGFloat(data.count - 1) * w,
                                         y: h - data[i] * h))
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5))
        }
    }

    // MARK: - Inference Load Panel

    private var inferenceLoadPanel: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("Inference Load")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextTertiary)
            }
            HStack(spacing: OSpacing.md) {
                legendDot(Color.oAccent, "Local")
                legendDot(Color.oSuccessGreen, "Mesh")
                legendDot(Color.oWarningAmber, "Queued")
            }
            HStack(alignment: .bottom, spacing: OSpacing.md) {
                VStack(alignment: .leading, spacing: 0) {
                    inferenceChart
                        .frame(height: 140)
                }
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Current").font(.oCaption).foregroundStyle(Color.oTextTertiary)
                    Text("\(appState.runtimeManager.routingMetrics?.requestCount ?? 0)")
                        .font(.oLargeTitle).foregroundStyle(Color.oTextPrimary)
                    Text("requests").font(.oCaption).foregroundStyle(Color.oTextTertiary)
                    Divider().padding(.vertical, 4)
                    let local = appState.runtimeManager.routingMetrics?.pressure?.localServiceShare ?? 0
                    let remote = appState.runtimeManager.routingMetrics?.pressure?.remoteServiceShare ?? 0
                    Text("Local   \(String(format: "%.0f", local * 100))%")
                        .font(.oCaption).foregroundStyle(Color.oTextPrimary)
                    Text("Mesh    \(String(format: "%.0f", remote * 100))%")
                        .font(.oCaption).foregroundStyle(Color.oTextPrimary)
                }
                .frame(width: 120)
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.oCaption).foregroundStyle(Color.oTextSecondary)
        }
    }

    private var inferenceChart: some View {
        let samples = appState.runtimeManager.routingMetrics?.throughputSamples ?? []
        if samples.isEmpty {
            return AnyView(
                HStack {
                    Spacer()
                    Text("Throughput data accumulates over time")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                    Spacer()
                }
            )
        }
        let maxVal = samples.max() ?? 1
        return AnyView(Canvas { ctx, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h - CGFloat(samples[0] / maxVal) * h))
            for i in 1..<samples.count {
                path.addLine(to: CGPoint(x: CGFloat(i) / CGFloat(samples.count - 1) * w,
                                         y: h - CGFloat(samples[i] / maxVal) * h))
            }
            ctx.stroke(path, with: .color(Color.oAccent), lineWidth: 1.5)
        })
    }

    // MARK: - Recent Activity Panel

    private var recentActivityPanel: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("Recent Activity")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Spacer()
                Button("View All") { showActivitySheet = true }
                    .buttonStyle(.plain)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oAccent)
            }
            if recentRuns.isEmpty {
                Text("No activity yet")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(recentRuns.prefix(5).enumerated()), id: \.offset) { _, record in
                    HStack(spacing: OSpacing.sm) {
                        Text("Run")
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oAccent)
                        Text(record.runAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                        Spacer()
                        Text("\(record.tokenCount) tok")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextPrimary)
                        Text(String(format: "%.1fs", record.latency))
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                        Circle()
                            .fill(record.wasSuccess ? Color.oSuccessGreen : Color.oErrorRed)
                            .frame(width: 5, height: 5)
                    }
                    .padding(.vertical, 4)
                    if record.id != recentRuns.prefix(5).last?.id { Divider() }
                }
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.lg)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Activity Sheet

    private var activitySheet: some View {
        NavigationStack {
            List {
                if recentRuns.isEmpty {
                    ContentUnavailableView("No Activity", systemImage: "tray", description: Text("Run prompts to see activity here."))
                } else {
                    ForEach(recentRuns, id: \.id) { record in
                        HStack(spacing: OSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.runAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.oBodyMedium)
                                    .foregroundStyle(Color.oTextPrimary)
                                Text("Prompt run")
                                    .font(.oCaption)
                                    .foregroundStyle(Color.oTextSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(record.tokenCount) tok")
                                    .font(.oCaptionMed)
                                    .foregroundStyle(Color.oTextPrimary)
                                Text(String(format: "%.1fs", record.latency))
                                    .font(.oCaption)
                                    .foregroundStyle(Color.oTextTertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Recent Activity")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showActivitySheet = false }
                }
            }
            .frame(width: 500, height: 400)
        }
    }

    // MARK: - Formatters

    private func formattedCount(_ val: Int?) -> String {
        guard let val else { return "—" }
        if val >= 1_000_000 { return String(format: "%.1fM", Double(val) / 1_000_000) }
        if val >= 1_000 { return String(format: "%.1fK", Double(val) / 1_000) }
        return "\(val)"
    }

    private func formattedTokenCount(_ val: Int?) -> String {
        guard let val else { return "—" }
        if val >= 1_000_000 { return String(format: "%.1fM", Double(val) / 1_000_000) }
        if val >= 1_000 { return String(format: "%.1fK", Double(val) / 1_000) }
        return "\(val)"
    }
}
