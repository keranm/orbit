import XCTest
@testable import orbit

final class NovaStateTests: XCTestCase {

    // MARK: - NovaState coverage

    func test_novaState_allCases_count() {
        let all: [NovaState] = [
            .idle, .listening, .thinking, .responding,
            .success, .alert, .offline, .error
        ]
        XCTAssertEqual(all.count, 8)
    }

    func test_novaState_equatable_same() {
        XCTAssertEqual(NovaState.idle, .idle)
        XCTAssertEqual(NovaState.error, .error)
    }

    func test_novaState_equatable_different() {
        XCTAssertNotEqual(NovaState.idle, .error)
        XCTAssertNotEqual(NovaState.thinking, .responding)
    }

    func test_novaState_hashable_usable_as_set_key() {
        let set: Set<NovaState> = [.idle, .listening, .thinking, .idle]
        XCTAssertEqual(set.count, 3, "Duplicate states should collapse in a Set")
    }

    func test_novaState_hashable_usable_as_dict_key() {
        var map: [NovaState: String] = [:]
        map[.idle]    = "idle"
        map[.offline] = "offline"
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[.idle], "idle")
    }

    // MARK: - NovaAnimConfig coverage

    func test_animConfig_idle_glowOpacity_positive() {
        let c = NovaAnimator.config(for: .idle)
        XCTAssertGreaterThan(c.glowOpacity, 0)
    }

    func test_animConfig_offline_has_no_particles() {
        let c = NovaAnimator.config(for: .offline)
        XCTAssertEqual(c.particleCount, 0)
    }

    func test_animConfig_error_has_no_particles() {
        let c = NovaAnimator.config(for: .error)
        XCTAssertEqual(c.particleCount, 0)
    }

    func test_animConfig_error_floatAmplitude_is_zero() {
        let c = NovaAnimator.config(for: .error)
        XCTAssertEqual(c.floatAmplitude, 0)
    }

    func test_animConfig_offline_imageOpacity_is_dimmed() {
        let c = NovaAnimator.config(for: .offline)
        XCTAssertLessThan(c.imageOpacity, 1.0)
    }

    func test_animConfig_idle_imageOpacity_is_full() {
        let c = NovaAnimator.config(for: .idle)
        XCTAssertEqual(c.imageOpacity, 1.0)
    }

    func test_animConfig_thinking_particles_greater_than_alert() {
        let thinking = NovaAnimator.config(for: .thinking)
        let alert = NovaAnimator.config(for: .alert)
        XCTAssertGreaterThanOrEqual(thinking.particleCount, alert.particleCount)
    }

    func test_animConfig_responding_orbitDuration_faster_than_idle() {
        let responding = NovaAnimator.config(for: .responding)
        let idle = NovaAnimator.config(for: .idle)
        XCTAssertLessThan(responding.particleOrbitDuration, idle.particleOrbitDuration)
    }

    func test_animConfig_allStates_glowRadius_positive() {
        let states: [NovaState] = [
            .idle, .listening, .thinking, .responding,
            .success, .alert, .offline, .error
        ]
        for s in states {
            let c = NovaAnimator.config(for: s)
            XCTAssertGreaterThan(c.glowRadius, 0, "glowRadius must be positive for \(s)")
        }
    }

    func test_animConfig_allStates_glowPulseDuration_positive() {
        let states: [NovaState] = [
            .idle, .listening, .thinking, .responding,
            .success, .alert, .offline, .error
        ]
        for s in states {
            let c = NovaAnimator.config(for: s)
            XCTAssertGreaterThan(c.glowPulseDuration, 0, "pulseDuration must be positive for \(s)")
        }
    }

    func test_animConfig_allStates_floatDuration_positive() {
        let states: [NovaState] = [
            .idle, .listening, .thinking, .responding,
            .success, .alert, .offline, .error
        ]
        for s in states {
            let c = NovaAnimator.config(for: s)
            XCTAssertGreaterThan(c.floatDuration, 0, "floatDuration must be positive for \(s)")
        }
    }

    // MARK: - NovaAccessibility coverage

    func test_accessibility_label_idle() {
        XCTAssertEqual(NovaAccessibility.label(for: .idle), "Nova — ready")
    }

    func test_accessibility_label_listening() {
        XCTAssertEqual(NovaAccessibility.label(for: .listening), "Nova — listening")
    }

    func test_accessibility_label_thinking() {
        XCTAssertEqual(NovaAccessibility.label(for: .thinking), "Nova — thinking")
    }

    func test_accessibility_label_responding() {
        XCTAssertEqual(NovaAccessibility.label(for: .responding), "Nova — responding")
    }

    func test_accessibility_label_success() {
        XCTAssertEqual(NovaAccessibility.label(for: .success), "Nova — done")
    }

    func test_accessibility_label_alert() {
        XCTAssertEqual(NovaAccessibility.label(for: .alert), "Nova — needs attention")
    }

    func test_accessibility_label_offline() {
        XCTAssertEqual(NovaAccessibility.label(for: .offline), "Nova — offline")
    }

    func test_accessibility_label_error() {
        XCTAssertEqual(NovaAccessibility.label(for: .error), "Nova — error")
    }

    func test_accessibility_labels_all_nonEmpty() {
        let states: [NovaState] = [
            .idle, .listening, .thinking, .responding,
            .success, .alert, .offline, .error
        ]
        for s in states {
            XCTAssertFalse(NovaAccessibility.label(for: s).isEmpty, "Label empty for \(s)")
        }
    }

    func test_accessibility_shouldAnnounce_idle_isFalse() {
        XCTAssertFalse(NovaAccessibility.shouldAnnounce(.idle))
    }

    func test_accessibility_shouldAnnounce_error_isTrue() {
        XCTAssertTrue(NovaAccessibility.shouldAnnounce(.error))
    }

    func test_accessibility_shouldAnnounce_offline_isTrue() {
        XCTAssertTrue(NovaAccessibility.shouldAnnounce(.offline))
    }

    func test_accessibility_shouldAnnounce_success_isTrue() {
        XCTAssertTrue(NovaAccessibility.shouldAnnounce(.success))
    }

    func test_accessibility_shouldAnnounce_responding_isFalse() {
        XCTAssertFalse(NovaAccessibility.shouldAnnounce(.responding))
    }

}
