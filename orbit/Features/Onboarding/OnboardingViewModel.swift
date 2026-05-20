import SwiftUI

/// Central state machine for the onboarding flow.
@Observable
final class OnboardingViewModel {

    // MARK: - Step navigation

    enum Step: Int, CaseIterable, Equatable {
        case welcome, howItWorks, systemCheck, installRuntime, chooseExperience, preparing, complete

        var isFirst: Bool { self == .welcome }
        var isLast: Bool  { self == .complete }
        var next: Step?   { Step(rawValue: rawValue + 1) }
        var prev: Step?   { rawValue > 0 ? Step(rawValue: rawValue - 1) : nil }
        var title: String {
            switch self {
            case .welcome:          return "Welcome"
            case .howItWorks:       return "How It Works"
            case .systemCheck:      return "System Check"
            case .installRuntime:   return "Install Runtime"
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
    var runtimeManager: RuntimeManager?

    // MARK: - Runtime install

    var installProgress: Double = 0
    var installMessage: String = "Preparing…"
    var installDone = false
    var installError: String?

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
    }

    var prepareItems: [PrepareItem] = []
    var prepareDone = false
    var prepareError: String?

    // MARK: - Task handles for cancellation

    private var checksTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?

    // Set true in unit tests to skip animation delays and real CLI calls
    var skipDelays = false

    // MARK: - Navigation

    func advance() {
        guard let rawNext = step.next else { return }
        direction = .forward
        let next = skipDelays ? rawNext : effectiveNext(from: step, rawNext: rawNext)
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    func back() {
        guard let prev = step.prev else { return }
        cancelAll()
        useExistingModel = false  // reset skip state so back→forward re-evaluates
        direction = .backward
        withAnimation(.easeInOut(duration: 0.25)) { step = prev }
    }

    /// When true, startPrepare() uses the already-configured model ref instead of
    /// downloading a new one. Set by effectiveNext() when the system check confirms
    /// a model is already installed and configured.
    private(set) var useExistingModel = false

    /// Computes the next step, skipping steps whose work is already done.
    ///
    /// - Skips `installRuntime` if the system check confirmed the binary is present.
    /// - Skips `chooseExperience` if a model is already configured in config.toml.
    private func effectiveNext(from current: Step, rawNext: Step) -> Step {
        guard current == .systemCheck else { return rawNext }

        let binaryInstalled = runtimeManager?.binaryPath != nil
        let modelConfigured = runtimeManager?.configTomlHasModels() == true

        guard binaryInstalled else { return rawNext }  // need install → go to installRuntime

        if modelConfigured {
            // Both runtime and model are present — skip install AND model selection.
            useExistingModel = true
            return .preparing
        }
        // Runtime present but no model → skip install, pick a model.
        return .chooseExperience
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
            if let rm = self.runtimeManager {
                await rm.detectInstall()
                if rm.binaryPath != nil {
                    let ver = rm.installedVersion.map { "v\($0)" } ?? "Detected"
                    return .passed(detail: ver)
                } else {
                    return .failed("Not found — install required")
                }
            } else {
                return RuntimeManager.resolveBinary() != nil
                    ? .passed(detail: "Detected")
                    : .failed("Not found — install required")
            }
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

    // MARK: - Runtime install

    func startInstall() {
        installProgress = 0
        installDone = false
        installError = nil
        installMessage = "Checking for AI runtime…"

        installTask?.cancel()
        installTask = Task {
            guard !Task.isCancelled else { return }

            // Fast path: binary already present
            let binaryFound = skipDelays ? true : RuntimeManager.resolveBinary() != nil

            if binaryFound {
                await animateInstallProgress(stages: [
                    ("Detected existing runtime…", 0.50),
                    ("Verifying…",                 0.85),
                    ("Ready",                      1.00),
                ])
                guard !Task.isCancelled else { return }
                installDone = true
                return
            }

            // Binary not found — run the official installer
            if skipDelays {
                // Unit-test path: skip real install
                installMessage = "Ready"
                installProgress = 1.0
                installDone = true
                return
            }

            installMessage = "Connecting to installer…"
            installProgress = 0.05

            let service = InstallService()
            do {
                for try await phase in service.install() {
                    guard !Task.isCancelled else { return }
                    switch phase {
                    case .starting:
                        installMessage = "Connecting to installer…"
                        installProgress = 0.05
                    case .inProgress(let p):
                        installMessage = p < 0.5 ? "Downloading Orbit runtime…" : "Installing…"
                        installProgress = 0.05 + p * 0.90
                    case .done:
                        installMessage = "Ready"
                        installProgress = 1.0
                        installDone = true
                    case .failed(let msg):
                        installMessage = msg
                        installError = msg
                        installProgress = 0
                    }
                }
            } catch {
                installError = "Couldn't install. Check your network connection and try again."
                installMessage = installError!
            }
        }
    }

    func retryInstall() {
        startInstall()
    }

    private func animateInstallProgress(stages: [(String, Double)]) async {
        for (message, target) in stages {
            guard !Task.isCancelled else { return }
            installMessage = message
            let steps = skipDelays ? 1 : 20
            let current = installProgress
            for s in 1...steps {
                guard !Task.isCancelled else { return }
                await pause(skipDelays ? 1 : 60)
                installProgress = current + (target - current) * Double(s) / Double(steps)
            }
        }
    }

    // MARK: - Model preparation

    func startPrepare() {
        let modelLabel = useExistingModel ? existingModelDisplayName : selectedTier.displayName
        prepareItems = [
            PrepareItem(label: "Checking AI runtime"),
            PrepareItem(label: useExistingModel ? "Verifying model" : "Preparing \(modelLabel)"),
            PrepareItem(label: "Configuring your model"),
            PrepareItem(label: "Starting your AI"),
        ]
        prepareDone = false
        prepareError = nil

        prepareTask?.cancel()
        prepareTask = Task {
            guard !Task.isCancelled else { return }

            // Unit-test / skipDelays path: simulate completion without real CLI calls
            if skipDelays {
                for i in prepareItems.indices {
                    guard !Task.isCancelled else { return }
                    prepareItems[i].status = .active(0)
                    await pause(1)
                    prepareItems[i].status = .done
                }
                prepareDone = true
                return
            }

            guard let rm = runtimeManager else {
                setPrepareError("Setup is incomplete. Restart Orbit and try again.")
                return
            }

            // Step 1 — Verify runtime binary
            prepareItems[0].status = .active(0)
            if rm.binaryPath == nil { await rm.detectInstall() }
            guard !Task.isCancelled else { return }
            guard rm.binaryPath != nil else {
                setPrepareItemFailed(0, "Runtime not found")
                setPrepareError("The AI runtime isn't installed. Go back and install it first.")
                return
            }
            prepareItems[0].status = .done

            // Step 2 — Resolve the model ref.
            // We do NOT call `mesh-llm models download` here: in the +skippy binary
            // that command panics (Rust async runtime bug). Instead we pass the full ref
            // to `mesh-llm serve`, which handles downloading as part of startup.
            prepareItems[1].status = .active(0)
            let modelRef: String
            if useExistingModel, let existingRef = rm.activeModelRef {
                modelRef = existingRef
            } else {
                modelRef = await resolveModelRef(for: selectedTier, rm: rm)
            }
            prepareItems[1].status = .done
            guard !Task.isCancelled else { return }

            // Step 3 — Write config.toml (idempotent; ensures config matches selected model)
            prepareItems[2].status = .active(0)
            do {
                try rm.ensureModelConfigured(modelRef)
                prepareItems[2].status = .done
            } catch {
                setPrepareItemFailed(2, "Configuration failed")
                setPrepareError("Couldn't configure your model. Try again.")
                return
            }
            guard !Task.isCancelled else { return }

            // Step 4 — Start runtime and wait for readiness.
            // Pass modelRef: nil when using existing config so we don't rewrite it.
            prepareItems[3].status = .active(0)
            await rm.start(modelRef: useExistingModel ? nil : modelRef)

            // Poll for ready (up to 5 minutes).
            // The runtime may download a model on first start, which can take several
            // minutes on slower connections. Animate progress 0→85% over the first
            // 270 s so the user sees movement; snap to done when runtime is ready.
            let deadline = Date().addingTimeInterval(300)
            let startedAt = Date()
            while Date() < deadline && !Task.isCancelled {
                let s = rm.status
                if s == .ready { break }
                if case .error = s { break }
                if s == .noModelConfigured || s == .notInstalled { break }
                let elapsed = Date().timeIntervalSince(startedAt)
                let animated = min(elapsed / 270.0, 0.85)
                prepareItems[3].status = .active(animated)
                try? await Task.sleep(for: .seconds(2))
            }

            guard !Task.isCancelled else { return }

            if rm.status == .ready {
                prepareItems[3].status = .done
                prepareDone = true
            } else {
                setPrepareItemFailed(3, "Couldn't start")
                setPrepareError("The AI couldn't start. Check your internet connection — a small supporting model may need to download first.")
            }
        }
    }

    func retryPrepare() {
        startPrepare()
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
    private func resolveModelRef(for tier: ExperienceTier, rm: RuntimeManager) async -> String {
        let catalog = rm.recommendedModels.isEmpty
            ? (try? await rm.fetchRecommendedModels()) ?? []
            : rm.recommendedModels

        // Exact match first — avoids selecting wrong tier model (e.g. "Coder-7B" when we want "8B")
        if let exact = catalog.first(where: { $0.name == tier.modelID }) {
            return exact.ref
        }

        // Prefix match for tiers where modelID is a prefix of the catalog name
        if let prefix = catalog.first(where: { $0.name.hasPrefix(tier.modelID) }) {
            return prefix.ref
        }

        // Fallback: use the hardcoded full HF ref that mesh-llm download accepts directly.
        // The short catalog name (tier.modelID) is rejected by the +skippy builds.
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
    private func readConfigModelRef(_ rm: RuntimeManager) -> String? {
        rm.activeModelRef  // already set from config.toml during detectInstall
    }

    private func cancelAll() {
        checksTask?.cancel()
        installTask?.cancel()
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
        installProgress = 1.0
        installMessage = "Done"
        installDone = true
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
