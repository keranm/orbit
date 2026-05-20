import XCTest
@testable import orbit

/// Unit tests for ModelService UninstallResult and HF cache cleanup logic.
final class ModelServiceUninstallTests: XCTestCase {

    // MARK: - UninstallResult helpers

    func test_uninstallResult_summaryLines_emptyWhenNothingDone() {
        let result = ModelService.UninstallResult()
        XCTAssertTrue(result.summaryLines.isEmpty)
    }

    func test_uninstallResult_summaryLines_includesStoppedRuntime() {
        var result = ModelService.UninstallResult()
        result.stoppedRuntime = true
        XCTAssertTrue(result.summaryLines.contains(where: { $0.contains("Stopped") }))
    }

    func test_uninstallResult_summaryLines_includesModelCount_singular() {
        var result = ModelService.UninstallResult()
        result.removedModelRefs = ["one-model"]
        let lines = result.summaryLines.joined()
        XCTAssertTrue(lines.contains("1 downloaded model"),
            "Singular model line must contain '1 downloaded model'")
        XCTAssertFalse(lines.contains("1 downloaded models"),
            "Singular model line must not say 'models'")
    }

    func test_uninstallResult_summaryLines_includesModelCount_plural() {
        var result = ModelService.UninstallResult()
        result.removedModelRefs = ["model-a", "model-b", "model-c"]
        let lines = result.summaryLines.joined()
        XCTAssertTrue(lines.contains("3 downloaded models"),
            "Plural model count must say 'models'")
    }

    func test_uninstallResult_summaryLines_includesConfigDir() {
        var result = ModelService.UninstallResult()
        result.removedConfigDir = true
        XCTAssertTrue(result.summaryLines.contains(where: { $0.lowercased().contains("config") }))
    }

    func test_uninstallResult_summaryLines_includesBinary() {
        var result = ModelService.UninstallResult()
        result.removedBinaryPaths = ["/Users/test/.local/bin/mesh-llm"]
        XCTAssertTrue(result.summaryLines.contains(where: { $0.lowercased().contains("binary") || $0.lowercased().contains("runtime") }))
    }

    func test_uninstallResult_hasErrors_falseWhenNoErrors() {
        let result = ModelService.UninstallResult()
        XCTAssertFalse(result.hasErrors)
    }

    func test_uninstallResult_hasErrors_trueWhenErrorsPresent() {
        var result = ModelService.UninstallResult()
        result.errors = ["Something failed"]
        XCTAssertTrue(result.hasErrors)
    }

    func test_uninstallResult_removedModelCount_matchesRefCount() {
        var result = ModelService.UninstallResult()
        result.removedModelRefs = ["a", "b"]
        XCTAssertEqual(result.removedModelCount, 2)
    }

    // MARK: - HF cache directory cleanup

    func test_removeHFCacheDirectory_knownRefFormat() {
        // Should not crash or throw — just validate the path derivation is safe
        ModelService.removeHFCacheDirectory(for: "unsloth/Qwen3-0.6B-GGUF:Q4_K_M")
        ModelService.removeHFCacheDirectory(for: "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/file.gguf")
        ModelService.removeHFCacheDirectory(for: "org/repo@main:Q4_K_M")
        // Non-existent path — should be a no-op
        ModelService.removeHFCacheDirectory(for: "nonexistent/org/repo")
    }

    // MARK: - Integration (skipped unless binary is present and filesystem is expendable)

    @MainActor
    func test_uninstallAll_integration_requiresBinaryPresent() async throws {
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        throw XCTSkip("Destructive integration test — run manually only, not in CI")
    }
}
