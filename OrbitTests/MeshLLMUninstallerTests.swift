import XCTest
@testable import orbit

/// Unit tests for MeshLLMUninstaller path definitions and result logic.
/// Integration tests (actual file removal) are skipped in CI since they require
/// a real binary and would mutate the user's filesystem.
final class MeshLLMUninstallerTests: XCTestCase {

    // MARK: - Known paths

    func test_knownBinaryPaths_containsLocalBin() {
        let paths = MeshLLMUninstaller.knownBinaryPaths
        let localBin = ("~/.local/bin/mesh-llm" as NSString).expandingTildeInPath
        XCTAssertTrue(paths.contains(localBin),
            "~/.local/bin/mesh-llm must be in the known binary paths (official installer location)")
    }

    func test_knownBinaryPaths_containsCargoBin() {
        let paths = MeshLLMUninstaller.knownBinaryPaths
        let cargoBin = ("~/.cargo/bin/mesh-llm" as NSString).expandingTildeInPath
        XCTAssertTrue(paths.contains(cargoBin),
            "~/.cargo/bin/mesh-llm must be in the known binary paths (cargo install location)")
    }

    func test_knownBinaryPaths_doesNotContainSystemBin() {
        // /usr/local/bin might require sudo to remove — intentionally excluded.
        let paths = MeshLLMUninstaller.knownBinaryPaths
        XCTAssertFalse(paths.contains("/usr/local/bin/mesh-llm"),
            "/usr/local/bin/mesh-llm must not be auto-removed (may require sudo)")
    }

    func test_knownBinaryPaths_areNonEmpty() {
        XCTAssertFalse(MeshLLMUninstaller.knownBinaryPaths.isEmpty)
    }

    func test_knownBinaryPaths_areAllAbsolutePaths() {
        for path in MeshLLMUninstaller.knownBinaryPaths {
            XCTAssertTrue(path.hasPrefix("/"),
                "Binary path '\(path)' must be an absolute path (tildes must be expanded)")
        }
    }

    func test_configDirPath_isMeshLLMDirectory() {
        let dir = MeshLLMUninstaller.configDirPath
        XCTAssertTrue(dir.hasSuffix("/.mesh-llm"),
            "configDirPath must point to ~/.mesh-llm — got: \(dir)")
    }

    func test_configDirPath_isAbsolute() {
        XCTAssertTrue(MeshLLMUninstaller.configDirPath.hasPrefix("/"),
            "configDirPath must be an absolute path")
    }

    func test_configDirPath_doesNotDeleteHuggingFaceCache() {
        let dir = MeshLLMUninstaller.configDirPath
        XCTAssertFalse(dir.contains("huggingface"),
            "configDirPath must NOT be inside the HuggingFace cache — would delete unrelated content")
    }

    // MARK: - UninstallResult helpers

    func test_uninstallResult_summaryLines_emptyWhenNothingDone() {
        let result = MeshLLMUninstaller.UninstallResult()
        XCTAssertTrue(result.summaryLines.isEmpty)
    }

    func test_uninstallResult_summaryLines_includesStoppedRuntime() {
        var result = MeshLLMUninstaller.UninstallResult()
        result.stoppedRuntime = true
        XCTAssertTrue(result.summaryLines.contains(where: { $0.contains("Stopped") }))
    }

    func test_uninstallResult_summaryLines_includesModelCount_singular() {
        var result = MeshLLMUninstaller.UninstallResult()
        result.removedModelRefs = ["one-model"]
        let lines = result.summaryLines.joined()
        // "Removed 1 downloaded model" — singular, no trailing 's'
        XCTAssertTrue(lines.contains("1 downloaded model"),
            "Singular model line must contain '1 downloaded model'")
        XCTAssertFalse(lines.contains("1 downloaded models"),
            "Singular model line must not say 'models'")
    }

    func test_uninstallResult_summaryLines_includesModelCount_plural() {
        var result = MeshLLMUninstaller.UninstallResult()
        result.removedModelRefs = ["model-a", "model-b", "model-c"]
        let lines = result.summaryLines.joined()
        XCTAssertTrue(lines.contains("3 downloaded models"),
            "Plural model count must say 'models'")
    }

    func test_uninstallResult_summaryLines_includesConfigDir() {
        var result = MeshLLMUninstaller.UninstallResult()
        result.removedConfigDir = true
        XCTAssertTrue(result.summaryLines.contains(where: { $0.lowercased().contains("config") }))
    }

    func test_uninstallResult_summaryLines_includesBinary() {
        var result = MeshLLMUninstaller.UninstallResult()
        result.removedBinaryPaths = ["/Users/test/.local/bin/mesh-llm"]
        XCTAssertTrue(result.summaryLines.contains(where: { $0.lowercased().contains("binary") || $0.lowercased().contains("runtime") }))
    }

    func test_uninstallResult_hasErrors_falseWhenNoErrors() {
        let result = MeshLLMUninstaller.UninstallResult()
        XCTAssertFalse(result.hasErrors)
    }

    func test_uninstallResult_hasErrors_trueWhenErrorsPresent() {
        var result = MeshLLMUninstaller.UninstallResult()
        result.errors = ["Something failed"]
        XCTAssertTrue(result.hasErrors)
    }

    func test_uninstallResult_removedModelCount_matchesRefCount() {
        var result = MeshLLMUninstaller.UninstallResult()
        result.removedModelRefs = ["a", "b"]
        XCTAssertEqual(result.removedModelCount, 2)
    }

    // MARK: - Safety: HuggingFace cache

    func test_huggingFaceRoot_isNotInKnownBinaryPaths() {
        let hfRoot = ("~/.cache/huggingface" as NSString).expandingTildeInPath
        for path in MeshLLMUninstaller.knownBinaryPaths {
            XCTAssertFalse(path.hasPrefix(hfRoot),
                "Binary path '\(path)' must not be inside the HuggingFace cache")
        }
    }

    func test_configDirPath_isNotHuggingFaceRoot() {
        let hfRoot = ("~/.cache/huggingface" as NSString).expandingTildeInPath
        XCTAssertFalse(MeshLLMUninstaller.configDirPath.hasPrefix(hfRoot))
    }

    // MARK: - Integration (skipped unless binary is present and filesystem is expendable)

    @MainActor
    func test_uninstall_integration_requiresBinaryPresent() async throws {
        guard RuntimeManager.resolveBinary() != nil else {
            throw XCTSkip("mesh-llm binary not found — integration test skipped")
        }
        throw XCTSkip("Destructive integration test — run manually only, not in CI")
    }
}
