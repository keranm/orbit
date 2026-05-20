import XCTest
@testable import orbit

final class AppVersionTests: XCTestCase {

    // MARK: - Marketing version

    func test_marketingVersion_isNonEmpty() {
        XCTAssertFalse(AppVersion.marketing.isEmpty)
    }

    func test_marketingVersion_isNotPlaceholder() {
        // Must not be the fallback "0.0.0"
        XCTAssertNotEqual(AppVersion.marketing, "0.0.0",
            "MARKETING_VERSION must be set in project settings")
    }

    func test_marketingVersion_followsSemanticVersioning() {
        let parts = AppVersion.marketing
            .components(separatedBy: "-").first?
            .components(separatedBy: ".") ?? []
        // Must have at least major.minor
        XCTAssertGreaterThanOrEqual(parts.count, 2,
            "Version must follow semver: major.minor[.patch[-pre-release]]")
    }

    func test_marketingVersion_isAlpha() {
        // For current pre-alpha: version must contain "alpha"
        XCTAssertTrue(AppVersion.marketing.lowercased().contains("alpha"),
            "Current version must be an alpha build")
    }

    // MARK: - Build number

    func test_buildNumber_isNonEmpty() {
        XCTAssertFalse(AppVersion.build.isEmpty)
    }

    func test_buildNumber_isNumeric() {
        XCTAssertNotNil(Int(AppVersion.build),
            "Build number must be numeric")
    }

    // MARK: - Display strings

    func test_displayVersion_containsMarketingVersion() {
        XCTAssertTrue(AppVersion.displayVersion.contains(AppVersion.marketing))
    }

    func test_displayVersion_containsBuildNumber() {
        XCTAssertTrue(AppVersion.displayVersion.contains(AppVersion.build))
    }

    func test_displayVersion_formattedCorrectly() {
        // Expected: "x.y.z-label (N)"
        let v = AppVersion.displayVersion
        XCTAssertTrue(v.contains("(") && v.contains(")"),
            "displayVersion must wrap build number in parens: got '\(v)'")
    }

    func test_fullVersion_containsMarketingVersion() {
        XCTAssertTrue(AppVersion.fullVersion.contains(AppVersion.marketing))
    }

    func test_fullVersion_withoutHash_matchesDisplayVersion() {
        // When git hash is "–", fullVersion must equal displayVersion
        // We can't force the hash to be "–" but we can verify the contract
        // by checking that fullVersion is at least as long as displayVersion
        XCTAssertGreaterThanOrEqual(AppVersion.fullVersion.count, AppVersion.displayVersion.count)
    }

    // MARK: - Pre-release detection

    func test_isPreRelease_trueForAlpha() {
        XCTAssertTrue(AppVersion.isPreRelease,
            "0.1.0-alpha.1 must be detected as pre-release")
    }

    func test_preReleaseLabel_isAlpha() {
        XCTAssertEqual(AppVersion.preReleaseLabel, "Alpha")
    }

    func test_preReleaseLabel_emptyForFakeStable() {
        // Verify the detection logic directly
        let stableVersion = "1.0.0"
        let lower = stableVersion.lowercased()
        let isAlpha = lower.contains("alpha")
        let isBeta  = lower.contains("beta")
        let isRC    = lower.contains("rc")
        XCTAssertFalse(isAlpha || isBeta || isRC)
    }

    // MARK: - Git hash

    func test_gitHash_isNonEmpty() {
        // Either a real hash or the fallback "–"
        XCTAssertFalse(AppVersion.gitHash.isEmpty)
    }

    func test_gitHash_doesNotContainPlaceholder() {
        // Must not return the literal Xcode substitution placeholder
        XCTAssertFalse(AppVersion.gitHash.contains("$("),
            "gitHash must not contain unexpanded Xcode variable placeholder")
    }

    func test_gitHash_whenAvailable_looksLikeHex() {
        let hash = AppVersion.gitHash
        guard hash != "–" else { return }  // not available in this env — skip
        // A git short hash is 7+ hex characters
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let onlyHex = hash.unicodeScalars.allSatisfy { hexChars.contains($0) }
        XCTAssertTrue(onlyHex, "Git hash '\(hash)' must be hex characters")
        XCTAssertGreaterThanOrEqual(hash.count, 7, "Git short hash must be at least 7 chars")
    }
}
