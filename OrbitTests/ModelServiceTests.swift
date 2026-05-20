import XCTest
@testable import orbit

final class ModelServiceTests: XCTestCase {

    // MARK: - parseProgress — percentage patterns

    func test_parseProgress_fromPercentage_returnsCorrectFraction() {
        let result = ModelService.parseProgress(from: "Downloading... 45%")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.45, accuracy: 0.001)
    }

    func test_parseProgress_fromDecimalPercentage() {
        let result = ModelService.parseProgress(from: "45.2%")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.452, accuracy: 0.001)
    }

    func test_parseProgress_fromHundredPercent_clampedToOne() {
        let result = ModelService.parseProgress(from: "100%")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 1.0, accuracy: 0.001)
    }

    func test_parseProgress_fromZeroPercent() {
        let result = ModelService.parseProgress(from: "0%")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.0, accuracy: 0.001)
    }

    func test_parseProgress_fromMiBRatio() {
        let result = ModelService.parseProgress(from: "450 MiB / 1000 MiB")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.45, accuracy: 0.01)
    }

    func test_parseProgress_fromMBRatio() {
        let result = ModelService.parseProgress(from: "250MB/500MB")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.5, accuracy: 0.01)
    }

    func test_parseProgress_fromGiBRatio() {
        let result = ModelService.parseProgress(from: "2.5 GiB / 5 GiB")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.5, accuracy: 0.01)
    }

    func test_parseProgress_nilForEmptyString() {
        XCTAssertNil(ModelService.parseProgress(from: ""))
    }

    func test_parseProgress_nilForIrrelevantText() {
        XCTAssertNil(ModelService.parseProgress(from: "Connecting to server..."))
    }

    func test_parseProgress_nilForDoneMessage() {
        XCTAssertNil(ModelService.parseProgress(from: "Download complete"))
    }

    func test_parseProgress_picksFirstPercentage() {
        // When multiple percentages exist, picks the first
        let result = ModelService.parseProgress(from: "Model 45% (ETA 30% remaining)")
        XCTAssertNotNil(result)
        // Should pick 45
        XCTAssertEqual(result!, 0.45, accuracy: 0.01)
    }

    // MARK: - DownloadPhase equatability

    func test_downloadPhase_starting_equatable() {
        let a = ModelService.DownloadPhase.starting
        let b = ModelService.DownloadPhase.starting
        XCTAssertEqual(a, b)
    }

    func test_downloadPhase_downloading_equalWhenSameProgress() {
        XCTAssertEqual(
            ModelService.DownloadPhase.downloading(0.5),
            ModelService.DownloadPhase.downloading(0.5)
        )
    }

    func test_downloadPhase_downloading_notEqualWithDifferentProgress() {
        XCTAssertNotEqual(
            ModelService.DownloadPhase.downloading(0.3),
            ModelService.DownloadPhase.downloading(0.7)
        )
    }

    func test_downloadPhase_done_equatable() {
        XCTAssertEqual(ModelService.DownloadPhase.done, .done)
    }

    func test_downloadPhase_failed_equatableWhenSameMessage() {
        XCTAssertEqual(
            ModelService.DownloadPhase.failed("err"),
            ModelService.DownloadPhase.failed("err")
        )
    }

    // MARK: - userFacingError

    func test_userFacingError_diskFull() {
        let msg = ModelService.userFacingError(from: "no space left on device", exitCode: 1)
        XCTAssertTrue(msg.lowercased().contains("space"))
    }

    func test_userFacingError_networkError() {
        let msg = ModelService.userFacingError(from: "connection timed out", exitCode: 1)
        XCTAssertFalse(msg.isEmpty)
    }

    func test_userFacingError_notFound() {
        let msg = ModelService.userFacingError(from: "not in catalog", exitCode: 1)
        XCTAssertFalse(msg.isEmpty)
    }

    func test_userFacingError_generic() {
        let msg = ModelService.userFacingError(from: "", exitCode: 1)
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - InstallService.userFacingError

    func test_installService_permissionDenied() {
        let msg = InstallService.userFacingError(from: "permission denied while writing", exitCode: 1)
        XCTAssertTrue(msg.lowercased().contains("permission"))
    }

    func test_installService_diskFull() {
        let msg = InstallService.userFacingError(from: "no space left on device", exitCode: 1)
        XCTAssertTrue(msg.lowercased().contains("space"))
    }

    func test_installService_networkError() {
        let msg = InstallService.userFacingError(from: "could not resolve host", exitCode: 6)
        XCTAssertTrue(msg.lowercased().contains("network") || msg.lowercased().contains("connect"))
    }

    func test_installService_binaryNotFound_afterSuccessfulExit() {
        let msg = InstallService.userFacingError(from: "Installation complete", exitCode: 0)
        XCTAssertFalse(msg.isEmpty)
    }

    func test_installService_genericFailure() {
        let msg = InstallService.userFacingError(from: "", exitCode: 1)
        XCTAssertFalse(msg.isEmpty)
    }
}
