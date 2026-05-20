import XCTest
@testable import orbit

final class AppStateTests: XCTestCase {

    // MARK: - AppState defaults

    func test_appState_default_route_is_newChat() {
        let state = AppState()
        XCTAssertEqual(state.route, .newChat)
    }

    func test_appState_default_nova_state_is_idle() {
        let state = AppState()
        XCTAssertEqual(state.novaState, .idle)
    }

    func test_appState_default_runtime_status_is_notInstalled() {
        let state = AppState()
        XCTAssertEqual(state.runtimeStatus, .notInstalled)
    }

    // hasCompletedOnboarding is persisted via @AppStorage in RootView — not on AppState.

    // MARK: - RuntimeStatus

    func test_runtimeStatus_all_cases_are_equatable() {
        XCTAssertEqual(RuntimeStatus.notInstalled,      RuntimeStatus.notInstalled)
        XCTAssertEqual(RuntimeStatus.noModelConfigured, RuntimeStatus.noModelConfigured)
        XCTAssertEqual(RuntimeStatus.starting,          RuntimeStatus.starting)
        XCTAssertEqual(RuntimeStatus.ready,             RuntimeStatus.ready)
        XCTAssertEqual(RuntimeStatus.stopping,          RuntimeStatus.stopping)
        XCTAssertEqual(RuntimeStatus.offline,           RuntimeStatus.offline)
        XCTAssertEqual(RuntimeStatus.error("msg"),      RuntimeStatus.error("msg"))
    }

    func test_runtimeStatus_error_equality_uses_message() {
        XCTAssertNotEqual(RuntimeStatus.error("a"), RuntimeStatus.error("b"))
    }

    func test_runtimeStatus_has_six_cases() {
        // Exhaustive switch — any new case added without updating this test will
        // cause a compile error, which is the intent.
        let statuses: [RuntimeStatus] = [
            .notInstalled, .noModelConfigured, .starting,
            .ready, .stopping, .offline, .error("x")
        ]
        var count = 0
        for s in statuses {
            switch s {
            case .notInstalled, .noModelConfigured, .starting,
                 .ready, .stopping, .offline, .error:
                count += 1
            }
        }
        XCTAssertEqual(count, 7)
    }

    // MARK: - NovaState (replaces CompanionState from Stage 1)

    func test_novaState_all_cases_are_equatable() {
        let cases: [NovaState] = [
            .idle, .listening, .thinking, .responding,
            .success, .alert, .offline, .error
        ]
        for c in cases {
            XCTAssertEqual(c, c)
        }
    }

    func test_novaState_has_eight_cases() {
        let cases: [NovaState] = [
            .idle, .listening, .thinking, .responding,
            .success, .alert, .offline, .error
        ]
        var count = 0
        for c in cases {
            switch c {
            case .idle, .listening, .thinking, .responding,
                 .success, .alert, .offline, .error:
                count += 1
            }
        }
        XCTAssertEqual(count, 8)
    }

    func test_novaState_is_hashable() {
        var set = Set<NovaState>()
        set.insert(.idle)
        set.insert(.error)
        XCTAssertEqual(set.count, 2)
    }
}
