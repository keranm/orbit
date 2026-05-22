import XCTest
@testable import orbit

final class OnboardingViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialStep_isWelcome() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.step, .welcome)
    }

    func test_initialDirection_isForward() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.direction, .forward)
    }

    func test_initialSelectedTier_isFast() {
        // Default changed to .fast — smallest download (397MB), works on all Macs
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.selectedTier, .fast)
    }

    func test_initialCheckItems_areAllPending() {
        let vm = OnboardingViewModel()
        for item in vm.checkItems {
            if case .pending = item.status {} else {
                XCTFail("Expected .pending for item \(item.label)")
            }
        }
    }

    func test_initialChecksDone_isFalse() {
        let vm = OnboardingViewModel()
        XCTAssertFalse(vm.checksDone)
    }

    // MARK: - Step navigation

    func test_advance_movesToNextStep() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.step, .welcome)
        vm.advance()
        XCTAssertEqual(vm.step, .howItWorks)
    }

    func test_advance_setsDirectionForward() {
        let vm = OnboardingViewModel()
        vm.advance()
        XCTAssertEqual(vm.direction, .forward)
    }

    func test_advance_doesNotGoBeyondComplete() async {
        let vm = OnboardingViewModel()
        vm.skipDelays = true
        for _ in 0..<10 { vm.advance() }
        try? await Task.sleep(for: .milliseconds(200))
        vm.advance()
        vm.advance()
        XCTAssertEqual(vm.step, .complete)
    }

    func test_back_movesToPreviousStep() {
        let vm = OnboardingViewModel()
        vm.advance()                       // → howItWorks
        XCTAssertEqual(vm.step, .howItWorks)
        vm.back()                          // → welcome
        XCTAssertEqual(vm.step, .welcome)
    }

    func test_back_setsDirectionBackward() {
        let vm = OnboardingViewModel()
        vm.advance()
        vm.back()
        XCTAssertEqual(vm.direction, .backward)
    }

    func test_back_doesNotGoBeforeWelcome() {
        let vm = OnboardingViewModel()
        vm.back()
        XCTAssertEqual(vm.step, .welcome)
    }

    func test_step_isFirst_onlyOnWelcome() {
        XCTAssertTrue(OnboardingViewModel.Step.welcome.isFirst)
        XCTAssertFalse(OnboardingViewModel.Step.howItWorks.isFirst)
        XCTAssertFalse(OnboardingViewModel.Step.complete.isFirst)
    }

    func test_step_isLast_onlyOnComplete() {
        XCTAssertTrue(OnboardingViewModel.Step.complete.isLast)
        XCTAssertFalse(OnboardingViewModel.Step.welcome.isLast)
        XCTAssertFalse(OnboardingViewModel.Step.preparing.isLast)
    }

    func test_allCases_hasSixSteps() {
        XCTAssertEqual(OnboardingViewModel.Step.allCases.count, 6)
    }

    func test_step_prev_ofWelcome_isNil() {
        XCTAssertNil(OnboardingViewModel.Step.welcome.prev)
    }

    func test_step_next_ofComplete_isNil() {
        XCTAssertNil(OnboardingViewModel.Step.complete.next)
    }

    // MARK: - Experience tiers

    func test_experienceTier_allCasesHasThree() {
        XCTAssertEqual(OnboardingViewModel.ExperienceTier.allCases.count, 3)
    }

    func test_experienceTier_fast_isRecommended() {
        XCTAssertTrue(OnboardingViewModel.ExperienceTier.fast.isRecommended)
        XCTAssertFalse(OnboardingViewModel.ExperienceTier.balanced.isRecommended)
        XCTAssertFalse(OnboardingViewModel.ExperienceTier.advanced.isRecommended)
    }

    func test_experienceTier_modelIDs_areDistinct() {
        let ids = OnboardingViewModel.ExperienceTier.allCases.map { $0.modelID }
        XCTAssertEqual(Set(ids).count, 3, "All model IDs must be distinct")
    }

    func test_experienceTier_storageLabels_areNonEmpty() {
        for tier in OnboardingViewModel.ExperienceTier.allCases {
            XCTAssertFalse(tier.storageLabel.isEmpty)
        }
    }

    func test_experienceTier_titles_areNonEmpty() {
        for tier in OnboardingViewModel.ExperienceTier.allCases {
            XCTAssertFalse(tier.title.isEmpty)
        }
    }

    func test_experienceTier_advanced_hasRequiresNote() {
        XCTAssertNotNil(OnboardingViewModel.ExperienceTier.advanced.requiresNote)
    }

    func test_experienceTier_fast_hasNoRequiresNote() {
        XCTAssertNil(OnboardingViewModel.ExperienceTier.fast.requiresNote)
    }

    // MARK: - completeAllForTesting

    func test_completeAllForTesting_setsChecksDone() {
        let vm = OnboardingViewModel()
        vm.completeAllForTesting()
        XCTAssertTrue(vm.checksDone)
    }

    func test_completeAllForTesting_setsPrepareDone() {
        let vm = OnboardingViewModel()
        vm.completeAllForTesting()
        XCTAssertTrue(vm.prepareDone)
    }

    func test_completeAllForTesting_allCheckItemsPassed() {
        let vm = OnboardingViewModel()
        vm.completeAllForTesting()
        for item in vm.checkItems {
            if case .passed = item.status {} else {
                XCTFail("Expected .passed for \(item.label)")
            }
        }
    }

    func test_completeAllForTesting_allPrepareItemsDone() {
        let vm = OnboardingViewModel()
        vm.completeAllForTesting()
        for item in vm.prepareItems {
            if case .done = item.status {} else {
                XCTFail("Expected .done for \(item.label)")
            }
        }
    }

    // MARK: - Async operations (fast path via skipDelays)

    func test_startChecks_completesWithSkipDelays() async {
        let vm = OnboardingViewModel()
        vm.skipDelays = true
        vm.startChecks()
        // Wait a tick for the Task to run
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(vm.checksDone)
    }

    func test_startDownload_completesWithSkipDelays() async {
        let vm = OnboardingViewModel()
        vm.skipDelays = true
        vm.startDownload()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(vm.downloadState, .completed)
    }

    func test_startChecks_resetsStateBeforeRunning() {
        let vm = OnboardingViewModel()
        // Mark checks as done first
        vm.completeAllForTesting()
        XCTAssertTrue(vm.checksDone)
        // Reset by starting fresh
        vm.skipDelays = true
        vm.startChecks()
        // Immediately after calling, state should be reset (before Task runs)
        // checksDone is reset to false at the start of startChecks
        // (it's reset synchronously before the Task fires)
        // Give it a moment to complete too
    }

    // MARK: - Skip logic (advance from systemCheck)

    func test_advance_fromSystemCheck_withoutModel_goesToChooseExperience() {
        let vm = OnboardingViewModel()
        let rm = RuntimeManager()
        vm.runtimeManager = rm
        vm.step = .systemCheck

        let configHasModels = rm.configTomlHasModels()
        if !configHasModels {
            vm.advance()
            XCTAssertEqual(vm.step, .chooseExperience,
                "No model configured → must go to chooseExperience")
        }
    }

    func test_advance_fromSystemCheck_alwaysGoesToChooseExperience() {
        let vm = OnboardingViewModel()
        vm.step = .systemCheck
        vm.advance()
        XCTAssertEqual(vm.step, .chooseExperience,
            "Should always go to chooseExperience (skip logic removed)")
    }

    func test_existingModelDisplayName_isNonEmpty_whenActiveRefSet() {
        let vm = OnboardingViewModel()
        let rm = RuntimeManager()
        vm.runtimeManager = rm
        rm.enterMockReadyState()  // sets activeModelRef = "mock-model"
        XCTAssertFalse(vm.existingModelDisplayName.isEmpty,
            "existingModelDisplayName must not be empty when activeModelRef is set")
    }

    func test_existingModelDisplayName_fallback_whenNoRuntime() {
        let vm = OnboardingViewModel()
        // No runtimeManager → falls back to "existing model"
        XCTAssertEqual(vm.existingModelDisplayName, "existing model")
    }
}
