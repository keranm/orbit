import SwiftUI

/// Central state machine for the onboarding flow.
@Observable
final class OnboardingViewModel {

    // MARK: - Step navigation

    enum Step: Int, CaseIterable, Equatable {
        case welcome, howItWorks, systemCheck, chooseExperience, preparing, complete

        var isFirst: Bool { self == .welcome }
        var isLast: Bool  { self == .complete }
        var next: Step?   { Step(rawValue: rawValue + 1) }
        var prev: Step?   { rawValue > 0 ? Step(rawValue: rawValue - 1) : nil }
        var title: String {
            switch self {
            case .welcome:          return "Welcome"
            case .howItWorks:       return "How It Works"
            case .systemCheck:      return "System Check"
            case .chooseExperience: return "Choose Model"
            case .preparing:        return "Preparing"
            case .complete:         return "Complete"
            }
        }
    }

    enum TransitionDirection { case forward, backward }

    var step: Step = .welcome
    var direction: TransitionDirection = .forward

    // MARK: - System check

    struct CheckItem: Identifiable {
        enum Status: Equatable {
            case pending, checking, passed, failed(String)
        }
        let id = UUID()
        let label: String
        var passDetail: String
        var status: Status = .pending
    }

    var checkItems: [CheckItem] = [
        CheckItem(label: "macOS version",     passDetail: "macOS 14 or later"),
        CheckItem(label: "Processor",         passDetail: "Apple Silicon"),
        CheckItem(label: "Memory",            passDetail: "8 GB or more"),
        CheckItem(label: "Available storage", passDetail: "10 GB free"),
        CheckItem(label: "Network",           passDetail: "Connected"),
        CheckItem(label: "AI runtime",        passDetail: "Detected"),
    ]
    var checksDone = false

    /// Injected from the environment — used for real system checks and runtime start.
    var runtimeManager: RuntimeAdapter?

    // MARK: - Experience selection

    enum ExperienceTier: CaseIterable, Equatable {
        case fast, balanced, advanced

        var title: String {
            switch self {
            case .fast:     return "Fast local chat"
            case .balanced: return "Balanced accuracy"
            case .advanced: return "Advanced reasoning"
            }
        }

        var subtitle: String {
            switch self {
            case .fast:     return "Great for quick responses and everyday tasks"
            case .balanced: return "Thoughtful answers for complex questions"
            case .advanced: return "Deep analysis and multi-step reasoning"
            }
        }

        var storageLabel: String {
            switch self {
            case .fast:     return "~397 MB"
            case .balanced: return "~5 GB"
            case .advanced: return "~20 GB"
            }
        }

        var modelID: String {
            switch self {
            case .fast:     return "Qwen3-0.6B-Q4_K_M"
            case .balanced: return "Qwen3-8B-Q4_K_M"
            case .advanced: return "Qwen3-32B"
            }
        }

        /// Full HuggingFace ref accepted by `mesh-llm models download`.
        /// Used as the fallback when the recommended catalog cannot be fetched.
        /// Verified against mesh-llm 0.65.1+skippy (2026-05-19).
        var defaultRef: String {
            switch self {
            case .fast:     return "unsloth/Qwen3-0.6B-GGUF@main:Q4_K_M"
            case .balanced: return "unsloth/Qwen3-8B-GGUF@main:Q4_K_M"
            case .advanced: return "unsloth/Qwen3-32B-GGUF@main:Q4_K_M"
            }
        }

        var displayName: String {
            switch self {
            case .fast:     return "Qwen 3 · 0.6B"
            case .balanced: return "Qwen 3 · 8B"
            case .advanced: return "Qwen 3 · 32B"
            }
        }

        var isRecommended: Bool { self == .fast }
        var requiresNote: String? { self == .advanced ? "16 GB RAM recommended" : nil }

        var iconName: String {
            switch self {
            case .fast:     return "bolt.fill"
            case .balanced: return "target"
            case .advanced: return "brain"
            }
        }
    }

    // Default to fast (0.6B) — smallest download, works on all Macs, fastest to start
    var selectedTier: ExperienceTier = .fast

    /// When non-nil, the user picked an already-downloaded model instead of a tier.
    var selectedExistingModel: InstalledModelEntry?

    // MARK: - Model preparation

    struct PrepareItem: Identifiable {
        enum Status: Equatable {
            case pending
            case active(Double)
            case done
            case failed(String)
        }
        let id = UUID()
        let label: String
        var status: Status = .pending
        var detail: String?
    }

    var prepareItems: [PrepareItem] = []
    var prepareDone = false
    var prepareError: String?

    // MARK: - Task handles for cancellation

    private var checksTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?

    // Set true in unit tests to skip animation delays and real CLI calls
    var skipDelays = false

    // MARK: - Navigation

    func advance() {
        guard let rawNext = step.next else { return }
        direction = .forward
        let next = skipDelays ? rawNext : rawNext

        if step == .chooseExperience, next == .preparing {
            startDownload()
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    /// Called when download completes — advances from chooseExperience to preparing.
    func finishDownload() {
        guard step == .chooseExperience else { return }
        direction = .forward
        withAnimation(.easeInOut(duration: 0.25)) { step = .preparing }
    }

    /// Called when serving is ready — advances from preparing to complete.
    func finishServing() {
        guard step == .preparing else { return }
        direction = .forward
        withAnimation(.easeInOut(duration: 0.25)) { step = .complete }
    }

    func back() {
        guard let prev = step.prev else { return }
        cancelAll()
        direction = .backward
        withAnimation(.easeInOut(duration: 0.25)) { step = prev }
    }

    // MARK: - System checks

    func startChecks() {
        for i in checkItems.indices { checkItems[i].status = .pending }
        checksDone = false
        checksTask?.cancel()
        checksTask = Task { await self.runChecks() }
    }

    private func runChecks() async {
        guard !Task.isCancelled else { return }

        // 0 — macOS version
        await runCheck(index: 0) {
            if self.skipDelays { return .passed }
            let v = ProcessInfo.processInfo.operatingSystemVersion
            let detail = "macOS \(v.majorVersion).\(v.minorVersion)"
            return v.majorVersion >= 14 ? .passed(detail: detail) : .failed("macOS \(v.majorVersion) — upgrade required")
        }

        // 1 — Processor
        await runCheck(index: 1) {
            if self.skipDelays { return .passed }
            #if arch(arm64)
            return .passed(detail: "Apple Silicon")
            #else
            return .passed(detail: "Intel — some features limited")
            #endif
        }

        // 2 — Memory
        await runCheck(index: 2) {
            if self.skipDelays { return .passed }
            let bytes = ProcessInfo.processInfo.physicalMemory
            let gb = Double(bytes) / 1_073_741_824
            let detail = String(format: "%.0f GB", gb.rounded())
            return gb >= 8 ? .passed(detail: detail) : .failed("\(detail) — 8 GB required")
        }

        // 3 — Available storage
        await runCheck(index: 3) {
            if self.skipDelays { return .passed }
            let home = URL.homeDirectory
            if let capacity = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage {
                let gb = Double(capacity) / 1_073_741_824
                let detail = String(format: "%.0f GB free", gb)
                return gb >= 10 ? .passed(detail: detail) : .failed("\(detail) — need 10 GB")
            }
            return .passed(detail: "Check skipped")
        }

        // 4 — Network
        await runCheck(index: 4) {
            if self.skipDelays { return .passed }
            if let url = URL(string: "https://huggingface.co") {
                var req = URLRequest(url: url, timeoutInterval: 5)
                req.httpMethod = "HEAD"
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode ?? 0 < 500 {
                    return .passed(detail: "Connected")
                }
            }
            return .passed(detail: "Check skipped")
        }

        // 5 — AI runtime binary detection (real)
        await runCheck(index: 5) {
            if self.skipDelays { return .passed }
            guard let rm = self.runtimeManager else { return .failed("no runtime") }
            await rm.detectInstall()
            let ver = rm.installedVersion.map { "v\($0)" } ?? "Detected"
            return .passed(detail: ver)
        }

        checksDone = true
    }

    private enum CheckOutcome {
        case passed(detail: String? = nil)
        case failed(String)
        static var passed: CheckOutcome { .passed(detail: nil) }
    }

    private func runCheck(index: Int, work: @escaping () async -> CheckOutcome) async {
        guard !Task.isCancelled, index < checkItems.count else { return }
        checkItems[index].status = .checking
        await pause(skipDelays ? 0 : 400)
        guard !Task.isCancelled else { return }
        let outcome = await work()
        switch outcome {
        case .passed(let detail):
            let display = detail ?? checkItems[index].passDetail
            checkItems[index].passDetail = display
            checkItems[index].status = .passed
        case .failed(let reason):
            checkItems[index].status = .failed(reason)
        }
    }

    // MARK: - Model download

    enum DownloadState: Equatable {
        case idle
        case inProgress
        case completed
        case failed(String)
    }

    var downloadState: DownloadState = .idle
    var downloadProgress: Double = 0

    func startDownload() {
        downloadState = .inProgress
        downloadProgress = 0

        prepareTask?.cancel()
        prepareTask = Task {
            guard !Task.isCancelled else { return }

            if skipDelays {
                downloadProgress = 1
                downloadState = .completed
                finishDownload()
                return
            }

            guard let rm = runtimeManager else {
                downloadState = .failed("Setup is incomplete. Restart Orbit.")
                return
            }

            // Resolve model ref
            let modelRef: String
            if let picked = selectedExistingModel {
                modelRef = picked.ref ?? picked.name
            } else {
                modelRef = await resolveModelRef(for: selectedTier, rm: rm)
            }
            guard !Task.isCancelled else { return }

            // If picking an already-installed model, just configure it
            if selectedExistingModel != nil {
                do {
                    try rm.ensureModelConfigured(modelRef)
                } catch {
                    downloadState = .failed("Couldn't configure the model.")
                    return
                }
                downloadProgress = 1.0
                downloadState = .completed
                finishDownload()
                return
            }

            do {
                downloadProgress = 0
                try await rm.downloadModel(ref: modelRef)
                downloadProgress = 1.0
                downloadState = .completed
                try rm.ensureModelConfigured(modelRef)
                finishDownload()
            } catch {
                downloadState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - AI serving (screen 5 — preparing)

    func startServing() {
        prepareItems = [
            PrepareItem(label: "Starting your AI"),
        ]
        prepareDone = false
        prepareError = nil

        prepareTask?.cancel()
        prepareTask = Task {
            guard !Task.isCancelled else { return }

            if skipDelays {
                prepareItems[0].status = .active(0)
                await pause(1)
                prepareItems[0].status = .done
                prepareDone = true
                finishServing()
                return
            }

            guard let rm = runtimeManager else {
                setPrepareError("Setup is incomplete. Restart Orbit and try again.")
                return
            }

            // Start the runtime — model is cached, so this should be fast.
            prepareItems[0].status = .active(0)
            prepareItems[0].detail = "Starting mesh-LLM…"
            await rm.start()

            let deadline = Date().addingTimeInterval(120)
            let startedAt = Date()
            while Date() < deadline && !Task.isCancelled {
                let s = rm.status
                if s == .ready { break }
                if case .error = s { break }
                if s == .noModelConfigured || s == .notInstalled { break }

                let elapsed = Date().timeIntervalSince(startedAt)
                if elapsed > 5, prepareItems[0].detail == "Starting mesh-LLM…" {
                    prepareItems[0].detail = "Loading model into memory…"
                }

                prepareItems[0].status = .active(min(elapsed / 120.0, 0.85))
                try? await Task.sleep(for: .seconds(2))
            }

            guard !Task.isCancelled else { return }

            if rm.status == .ready {
                prepareItems[0].status = .done
                prepareDone = true
                finishServing()
            } else {
                setPrepareItemFailed(0, "Couldn't start")
                let detail: String
                if case .error(let msg) = rm.status {
                    detail = msg
                } else {
                    detail = "The runtime exited before it was ready. Try again."
                }
                setPrepareError(detail)
            }
        }
    }

    func retryServing() {
        startServing()
    }

    // MARK: - Helpers

    private func setPrepareError(_ msg: String) {
        prepareError = msg
    }

    private func setPrepareItemFailed(_ index: Int, _ label: String) {
        guard index < prepareItems.count else { return }
        prepareItems[index].status = .failed(label)
    }

    /// Resolves the full Hugging Face model ref for the given tier.
    /// Match priority:
    ///   1. Exact catalog name == tier.modelID
    ///   2. Catalog name starts with tier.modelID (e.g. "Qwen3-32B" → "Qwen3-32B-Q4_K_M")
    ///   3. Fallback: pass modelID directly (mesh-llm resolves by catalog name)
    private func resolveModelRef(for tier: ExperienceTier, rm: RuntimeAdapter) async -> String {
        return tier.defaultRef
    }

    /// A human-readable label for the model that is already installed.
    /// Used in the preparing step label when useExistingModel is true.
    var existingModelDisplayName: String {
        guard let ref = runtimeManager?.activeModelRef else { return "existing model" }
        // Extract a clean name: take the last path component and strip .gguf
        let parts = ref.components(separatedBy: "/")
        var name = parts.last ?? ref
        if name.hasSuffix(".gguf") { name = String(name.dropLast(5)) }
        // Handle colon-separated format e.g. "repo:Q4_K_M"
        if let colonIdx = name.firstIndex(of: ":") { name = String(name[name.index(after: colonIdx)...]) }
        return name.isEmpty ? ref : name
    }

    /// Reads the model ref from config.toml via the runtime manager, used when
    /// useExistingModel is true to avoid resolving the ref from the catalog.
    private func readConfigModelRef(_ rm: RuntimeAdapter) -> String? {
        rm.activeModelRef  // already set from config.toml during detectInstall
    }

    private func cancelAll() {
        checksTask?.cancel()
        prepareTask?.cancel()
    }

    private func pause(_ ms: Int) async {
        if skipDelays || ms <= 0 { return }
        try? await Task.sleep(for: .milliseconds(ms))
    }

    // MARK: - Testing helpers

    func completeAllForTesting() {
        skipDelays = true
        for i in checkItems.indices { checkItems[i].status = .passed }
        checksDone = true
        prepareItems = [
            PrepareItem(label: "Checking AI runtime"),
            PrepareItem(label: "Downloading \(selectedTier.displayName)"),
            PrepareItem(label: "Configuring your model"),
            PrepareItem(label: "Starting AI runtime"),
        ]
        for i in prepareItems.indices { prepareItems[i].status = .done }
        prepareDone = true
    }
}
