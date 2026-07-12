import Testing
@testable import KivodoCore

@MainActor
final class MockReminderStore: ReminderStore, @unchecked Sendable {
    var savedTitles: [String] = []
    var errorToThrow: Error?

    nonisolated init() {}

    func save(title: String) async throws {
        if let errorToThrow { throw errorToThrow }
        savedTitles.append(title)
    }
}

@MainActor
struct CaptureViewModelTests {
    @Test func savesTrimmedTitleAndClearsText() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "  Buy milk  "
        await vm.submit()
        #expect(store.savedTitles == ["Buy milk"])
        #expect(vm.phase == .saved)
        #expect(vm.text.isEmpty)
    }

    @Test func emptyInputShakesWithoutSaving() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "   "
        await vm.submit()
        #expect(store.savedTitles.isEmpty)
        #expect(vm.shakeCount == 1)
        #expect(vm.phase == .idle)
    }

    @Test func accessDeniedShowsPermissionPhase() async {
        let store = MockReminderStore()
        store.errorToThrow = ReminderError.accessDenied
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        #expect(vm.phase == .needsPermission)
    }

    @Test func saveFailureKeepsTextAndReportsError() async {
        let store = MockReminderStore()
        store.errorToThrow = ReminderError.noDefaultList
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        #expect(vm.phase == .failed("No default Reminders list is configured."))
        #expect(vm.text == "Buy milk")
    }

    @Test func resetClearsStateForNextPresentation() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        vm.reset()
        #expect(vm.phase == .idle)
        #expect(vm.text.isEmpty)
    }
}
