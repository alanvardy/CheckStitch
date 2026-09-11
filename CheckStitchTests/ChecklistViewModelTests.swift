@testable import CheckStitchCore
import Testing

@MainActor
struct ChecklistViewModelTests {
    private func makeViewModel(_ spy: SpyReminderCreator) -> ChecklistViewModel {
        ChecklistViewModel(
            environment: AppEnvironment(reminderCreator: spy), spinnerDuration: .zero)
    }

    @Test
    func viewModelStartsWithSeededItems() {
        let viewModel = makeViewModel(SpyReminderCreator())
        #expect(viewModel.items.map(\.title) == ["one", "two", "three"])
        #expect(viewModel.checklistName == "checklist")
        #expect(!viewModel.isCreatingChecklist)
        #expect(!viewModel.isChecklistCreated)
    }

    @Test
    func createChecklistSetsCreatedFlagOnSuccess() async {
        let spy = SpyReminderCreator()
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        await viewModel.createChecklist()
        #expect(viewModel.isChecklistCreated)
        #expect(!viewModel.isCreatingChecklist)
        #expect(spy.createdTitles == ["one"])
    }

    @Test
    func createChecklistTogglesSpinnerAroundWork() async {
        let spy = SpyReminderCreator()
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        var spinnerDuringWork = false
        spy.onCreate = { spinnerDuringWork = viewModel.isCreatingChecklist }
        await viewModel.createChecklist()
        #expect(spinnerDuringWork, "spinner must be on while reminders are being created")
        #expect(!viewModel.isCreatingChecklist)
    }

    @Test
    func permissionDeniedLeavesCreatedFlagFalse() async {
        let spy = SpyReminderCreator()
        spy.accessGranted = false
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        await viewModel.createChecklist()
        #expect(!viewModel.isChecklistCreated)
        #expect(!viewModel.isCreatingChecklist)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func failedCreationLeavesCreatedFlagFalse() async {
        let spy = SpyReminderCreator()
        spy.createError = TestError.boom
        let viewModel = makeViewModel(spy)
        viewModel.items = [makeItem("one")]
        await viewModel.createChecklist()
        #expect(!viewModel.isChecklistCreated)
        #expect(!viewModel.isCreatingChecklist)
    }
}