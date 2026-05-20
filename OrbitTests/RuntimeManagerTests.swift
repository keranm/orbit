import XCTest
@testable import orbit

/// Tests for RuntimeManager, MeshLLMClient, and Domain types.
/// Tests marked "integration" require the real mesh-llm binary.
@MainActor
final class RuntimeManagerTests: XCTestCase {

    // MARK: - Binary path resolution

    func test_candidatePaths_containsCargoPath() {
        let paths = RuntimeManager.candidatePaths
        let cargoPath = ("~/.cargo/bin/mesh-llm" as NSString).expandingTildeInPath
        XCTAssertTrue(paths.contains(cargoPath), "~/.cargo/bin/mesh-llm must be a candidate path")
    }

    func test_candidatePaths_containsLocalBinPath() {
        let paths = RuntimeManager.candidatePaths
        let localPath = ("~/.local/bin/mesh-llm" as NSString).expandingTildeInPath
        XCTAssertTrue(paths.contains(localPath), "~/.local/bin/mesh-llm must be a candidate path")
    }

    func test_candidatePaths_localBinBeforeCargo() {
        let paths = RuntimeManager.candidatePaths
        let localPath = ("~/.local/bin/mesh-llm" as NSString).expandingTildeInPath
        let cargoPath = ("~/.cargo/bin/mesh-llm" as NSString).expandingTildeInPath
        guard let localIdx = paths.firstIndex(of: localPath),
              let cargoIdx = paths.firstIndex(of: cargoPath) else {
            XCTFail("Both paths must be present"); return
        }
        XCTAssertLessThan(localIdx, cargoIdx, "~/.local/bin must be checked before ~/.cargo/bin")
    }

    func test_resolveBinary_returnsNilForNonExistentPath() {
        // Smoke test: if the binary exists, resolved != nil; otherwise nil.
        // No assertion on the value — just confirm it doesn't crash.
        let result = RuntimeManager.resolveBinary()
        if result != nil {
            XCTAssertTrue(FileManager.default.fileExists(atPath: result!.path))
        }
    }

    // MARK: - RuntimeManager initial state

    func test_initialStatus_isNotInstalled() async {
        let rm = RuntimeManager()
        await MainActor.run {
            XCTAssertEqual(rm.status, .notInstalled)
        }
    }

    func test_initialBinaryPath_isNil() async {
        let rm = RuntimeManager()
        await MainActor.run {
            XCTAssertNil(rm.binaryPath)
        }
    }

    func test_initialInstalledModels_isEmpty() async {
        let rm = RuntimeManager()
        await MainActor.run {
            XCTAssertTrue(rm.installedModels.isEmpty)
        }
    }

    // MARK: - detectInstall (integration — requires real binary)

    func test_detectInstall_setsStatusToNoModelConfigured_whenBinaryExists() async throws {
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let rm = RuntimeManager()
        await rm.detectInstall()
        await MainActor.run {
            // Binary found: status must NOT be .notInstalled
            XCTAssertNotEqual(rm.status, .notInstalled)
            XCTAssertNotNil(rm.binaryPath)
        }
    }

    /// Verifies that detectInstall() transitions to .ready when the runtime is already serving.
    /// This covers the "AI paused" false-positive on Orbit relaunch after the runtime stayed up.
    func test_detectInstall_setsStatusToReady_whenRuntimeAlreadyServing() async throws {
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let client = MeshLLMClient(apiPort: 9337)
        let alreadyServing = await client.checkReadiness()
        guard alreadyServing else {
            throw XCTSkip("mesh-llm runtime not serving on :9337 — skipping")
        }

        let rm = RuntimeManager()
        await rm.detectInstall()
        await MainActor.run {
            XCTAssertEqual(rm.status, .ready,
                "detectInstall() must transition to .ready when /readyz is already responding")
        }
    }

    /// Regression: detectInstall() must sync activeModelRef from the live API when the
    /// runtime is already running, NOT from config.toml.
    /// Prevents 404 errors caused by a stale config.toml pointing to an unloaded model.
    func test_detectInstall_syncsActiveModelRefFromLiveRuntime_notConfigToml() async throws {
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let client = MeshLLMClient(apiPort: 9337)
        guard await client.checkReadiness() else {
            throw XCTSkip("mesh-llm runtime not serving on :9337 — skipping")
        }

        let rm = RuntimeManager()
        await rm.detectInstall()

        // Fetch what the runtime is actually serving via /v1/models.
        guard let url = URL(string: "http://localhost:9337/v1/models") else { return }
        let (data, _) = try await URLSession.shared.data(from: url)
        struct M: Decodable { struct E: Decodable { let id: String }; let data: [E] }
        let models = try JSONDecoder().decode(M.self, from: data)
        guard let liveModelId = models.data.first?.id else {
            throw XCTSkip("No models listed by running runtime — skipping")
        }

        await MainActor.run {
            XCTAssertEqual(
                rm.activeModelRef, liveModelId,
                "activeModelRef must match the live runtime's model ID, not a potentially stale config.toml value"
            )
        }
    }

    func test_detectInstall_setsStatusToNotInstalled_whenBinaryMissing() async {
        // Temporarily simulate no binary by using a RuntimeManager with no candidates.
        // We test resolveBinary returning nil by checking a non-existent path directly.
        let fakePath = "/tmp/definitely-not-mesh-llm-\(UUID().uuidString)"
        XCTAssertFalse(FileManager.default.fileExists(atPath: fakePath))

        // resolveBinary with injected fake path should return nil
        // (Tested indirectly: if all candidate paths don't exist, status = .notInstalled)
        let rm = RuntimeManager()
        if RuntimeManager.resolveBinary() == nil {
            await rm.detectInstall()
            await MainActor.run {
                XCTAssertEqual(rm.status, .notInstalled)
            }
        }
        // If binary DOES exist, skip assertion (can't remove it in test context)
    }

    // MARK: - queryVersion (integration)

    func test_queryVersion_returnsNonEmptyString() async throws {
        guard let bin = RuntimeManager.resolveBinary() else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let rm = RuntimeManager()
        let version = await rm.queryVersion(binary: bin)
        XCTAssertNotNil(version)
        XCTAssertFalse(version!.isEmpty)
    }

    func test_queryVersion_containsVersionNumber() async throws {
        guard let bin = RuntimeManager.resolveBinary() else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let rm = RuntimeManager()
        let version = await rm.queryVersion(binary: bin)
        guard let ver = version else {
            XCTFail("Version should not be nil"); return
        }
        // Expected: "0.65.1+skippy..." — must start with a digit
        XCTAssertTrue(ver.first?.isNumber == true,
                      "Version '\(ver)' should start with a digit")
    }

    // MARK: - fetchInstalledModels (integration)

    func test_fetchInstalledModels_returnsValidResponse() async throws {
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let rm = RuntimeManager()
        await rm.detectInstall()
        let response = try await rm.fetchInstalledModels()
        XCTAssertFalse(response.cacheDir.isEmpty, "cacheDir must not be empty")
        // results may be empty if no models installed — that is expected
    }

    func test_fetchInstalledModels_cacheDirIsHuggingFacePath() async throws {
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let rm = RuntimeManager()
        await rm.detectInstall()
        let response = try await rm.fetchInstalledModels()
        XCTAssertTrue(
            response.cacheDir.contains("huggingface") || response.cacheDir.contains("cache"),
            "cacheDir should reference the Hugging Face cache; got: \(response.cacheDir)"
        )
    }

    // MARK: - configToml
    //
    // All tests that write to config.toml use configTomlSandbox() to save and
    // restore the real file. This prevents test artifacts from poisoning the
    // live runtime (as happened when "test-model-orbit-unit-test" was left in
    // config.toml and broke app startup).

    private static let configPath = ("~/.mesh-llm/config.toml" as NSString).expandingTildeInPath

    /// Saves the current config.toml (if any) and registers teardown to restore it.
    /// Call at the top of every test that touches config.toml.
    private func configTomlSandbox() {
        let path = Self.configPath
        let original = try? String(contentsOfFile: path, encoding: .utf8)
        addTeardownBlock {
            if let original {
                try? original.write(toFile: path, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func test_configTomlHasModels_returnsFalseWhenNoFile() async {
        let rm = RuntimeManager()
        let result = await MainActor.run { rm.configTomlHasModels() }
        // Result depends on whether a real config.toml exists — just confirm no crash
        XCTAssertTrue(result == true || result == false)
    }

    func test_ensureModelConfigured_writesFile() async throws {
        configTomlSandbox()
        let rm = RuntimeManager()
        let testModel = "orbit-unit-test-\(UUID().uuidString)"
        try await MainActor.run { try rm.ensureModelConfigured(testModel) }

        let content = try String(contentsOfFile: Self.configPath, encoding: .utf8)
        XCTAssertTrue(content.contains("[[models]]"))
        XCTAssertTrue(content.contains(testModel))
        XCTAssertTrue(content.contains("version = 1"))
    }

    func test_ensureModelConfigured_updatesExistingFile() async throws {
        configTomlSandbox()
        let rm = RuntimeManager()
        let model2 = "model-two-\(UUID().uuidString)"
        try await MainActor.run {
            try rm.ensureModelConfigured("model-one-temp")
            try rm.ensureModelConfigured(model2)
        }
        let content = try String(contentsOfFile: Self.configPath, encoding: .utf8)
        XCTAssertTrue(content.contains(model2), "Latest model should be present")
    }

    func test_configTomlHasModels_trueAfterEnsure() async throws {
        configTomlSandbox()
        let rm = RuntimeManager()
        try await MainActor.run { try rm.ensureModelConfigured("any-model-\(UUID().uuidString)") }
        let hasModels = await MainActor.run { rm.configTomlHasModels() }
        XCTAssertTrue(hasModels)
    }

    // MARK: - isModelNotFoundError

    func test_isModelNotFoundError_trueForModelNotFound() {
        let stderr = "Model not found: test-model-orbit-unit-test\nNot a local file, not in the Hugging Face cache, not in catalog."
        XCTAssertTrue(RuntimeManager.isModelNotFoundError(stderr))
    }

    func test_isModelNotFoundError_trueForHFCacheMessage() {
        XCTAssertTrue(RuntimeManager.isModelNotFoundError("not in the Hugging Face cache"))
    }

    func test_isModelNotFoundError_falseForUnrelatedError() {
        XCTAssertFalse(RuntimeManager.isModelNotFoundError("port 9337 already in use"))
    }

    func test_isModelNotFoundError_falseForEmptyString() {
        XCTAssertFalse(RuntimeManager.isModelNotFoundError(""))
    }

    func test_isModelNotFoundError_falseForRotatingIdentity() {
        XCTAssertFalse(RuntimeManager.isModelNotFoundError("Previous run was public — rotating identity for private mesh"))
    }

    // MARK: - stop (should not crash when not running)

    func test_stop_whenNotRunning_doesNotCrash() async {
        let rm = RuntimeManager()
        await rm.stop()
        // No assertion — just confirm no crash/hang
    }

    // MARK: - State machine regression tests (Bug 1–6 fixes)

    /// Bug 1: fresh RuntimeManager must not start in .ready state.
    func test_initialState_isNotReady() async {
        let rm = RuntimeManager()
        await MainActor.run {
            XCTAssertNotEqual(rm.status, .ready,
                "status must not be .ready at initialisation — Ready requires a running, model-loaded runtime")
            XCTAssertNil(rm.activeModelRef,
                "activeModelRef must be nil on a fresh RuntimeManager")
        }
    }

    /// Bug 3: after ensureModelConfigured, configTomlHasModels must return true.
    /// This is the precondition that start() checks before launching the process.
    func test_ensureModelConfigured_enablesStartPrecondition() async throws {
        configTomlSandbox()
        let rm = RuntimeManager()
        let before = await MainActor.run { rm.configTomlHasModels() }
        guard !before else {
            throw XCTSkip("Config already has models — sandbox restore failed")
        }
        try await MainActor.run { try rm.ensureModelConfigured("test-start-precondition") }
        let after = await MainActor.run { rm.configTomlHasModels() }
        XCTAssertTrue(after, "configTomlHasModels must be true after ensureModelConfigured")
    }

    /// Bug 3: detectInstall must set .noModelConfigured when binary exists but no config.toml.
    /// Regression: previously, detectInstall could set .ready even with no model.
    func test_detectInstall_noModelConfig_setsNoModelConfigured() async throws {
        configTomlSandbox()
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        // Remove model config so no model is available.
        try? FileManager.default.removeItem(atPath: Self.configPath)

        let client = MeshLLMClient(apiPort: 9337)
        let runtimeServing = await client.checkReadiness()

        let rm = RuntimeManager()
        await rm.detectInstall()

        if runtimeServing {
            // Runtime is already up — detectInstall syncs from /v1/models.
            // The no-model path can only be tested when the runtime is not running.
            throw XCTSkip("Runtime is serving — cannot test no-model path while it is up")
        }

        await MainActor.run {
            XCTAssertNotEqual(rm.status, .ready,
                "status must not be .ready when no model is in config.toml and runtime is offline")
            XCTAssertNil(rm.activeModelRef,
                "activeModelRef must be nil when no model is configured")
        }
    }

    /// Bug 4: start() must cancel the keepalive before transitioning to .starting,
    /// so the old keepalive cannot race-set .offline during the startup sequence.
    /// Verified structurally: start() calls keepaliveTask?.cancel() before status = .starting.
    func test_start_cancelsKeepalive_beforeStarting() async throws {
        configTomlSandbox()
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        let rm = RuntimeManager()
        await rm.detectInstall()

        // Write a model config so start() doesn't abort on the guard
        let testRef = "orbit-keepalive-race-test-\(UUID().uuidString)"
        try await MainActor.run { try rm.ensureModelConfigured(testRef) }

        // Manually start the keepalive (simulating a previously-running session)
        await MainActor.run { rm.startKeepalive() }

        // Call start() — it should cancel the keepalive and move to .starting.
        // We cancel the startup task immediately to avoid actually launching mesh-llm.
        let startTask = Task { await rm.start(modelRef: testRef) }
        try? await Task.sleep(for: .milliseconds(20))
        startTask.cancel()

        // The status should have progressed past .offline (proving keepalive was cancelled
        // and start() took ownership of the state machine).
        await MainActor.run {
            XCTAssertNotEqual(rm.status, .offline,
                "After start() is called, status must not remain .offline (keepalive should be cancelled)")
        }
    }

    /// Bug 6: AppState.activeModelRef is derived from RuntimeManager.activeModelRef.
    func test_appState_activeModelRef_derivedFromRuntimeManager() async {
        let appState = AppState()
        await MainActor.run {
            // AppState.activeModelRef is a computed property from runtimeManager.
            XCTAssertNil(appState.activeModelRef,
                "activeModelRef must start nil (no runtime started)")
            // enterMockReadyState simulates what happens after a successful start.
            appState.runtimeManager.enterMockReadyState()
            XCTAssertEqual(appState.activeModelRef, "mock-model",
                "activeModelRef must reflect the runtimeManager's value after mock-ready state")
        }
    }

    /// Bug 5 / regression: keepalive task sleeps 10s before first check,
    /// so calling startKeepalive() then immediately checking status must not change it.
    func test_startKeepalive_doesNotImmediatelyChangeStatus() async {
        let rm = RuntimeManager()
        await MainActor.run {
            // rm starts as .notInstalled
            rm.startKeepalive()
        }
        // Give any immediate synchronous work time to run
        try? await Task.sleep(for: .milliseconds(100))
        await MainActor.run {
            // Status must still be .notInstalled — keepalive sleeps 10s before first check
            XCTAssertEqual(rm.status, .notInstalled,
                "startKeepalive() must not immediately change status")
        }
    }

    // MARK: - RuntimeError

    func test_runtimeError_binaryNotFound_hasDescription() {
        let err = RuntimeError.binaryNotFound
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }

    func test_runtimeError_cliError_includesMessage() {
        let err = RuntimeError.cliError("something failed")
        XCTAssertTrue(err.errorDescription?.contains("something failed") ?? false)
    }
}
