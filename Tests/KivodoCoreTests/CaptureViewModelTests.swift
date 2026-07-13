import Foundation
import Testing
@testable import KivodoCore

@MainActor
final class MockReminderStore: ReminderStore, @unchecked Sendable {
    var savedTitles: [String] = []
    var savedListIDs: [String?] = []
    var errorToThrow: Error?
    var listsToReturn: [ReminderList] = []

    nonisolated init() {}

    func save(title: String, to listID: String?) async throws {
        if let errorToThrow { throw errorToThrow }
        savedTitles.append(title)
        savedListIDs.append(listID)
    }

    func availableLists() async throws -> [ReminderList] {
        if let errorToThrow { throw errorToThrow }
        return listsToReturn
    }
}

/// A store whose save(title:to:) suspends until resumeAll() is called, so
/// tests can interleave a second submit while the first is still in flight.
@MainActor
final class SuspendingReminderStore: ReminderStore, @unchecked Sendable {
    var savedTitles: [String] = []
    var savedListIDs: [String?] = []
    var errorToThrow: Error?
    private var continuations: [CheckedContinuation<Void, Never>] = []

    nonisolated init() {}

    func save(title: String, to listID: String?) async throws {
        await withCheckedContinuation { continuations.append($0) }
        if let errorToThrow { throw errorToThrow }
        savedTitles.append(title)
        savedListIDs.append(listID)
    }

    func availableLists() async throws -> [ReminderList] {
        []
    }

    func resumeAll() {
        let pending = continuations
        continuations = []
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
struct CaptureViewModelTests {
    private let work = ReminderList(id: "work-id", title: "Work")
    private let home = ReminderList(id: "home-id", title: "Home")

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
        #expect(vm.text == "Buy milk")
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
        #expect(vm.presentationCount == 1)
    }

    @Test func genericErrorReportsLocalizedDescription() async {
        let store = MockReminderStore()
        let error = NSError(
            domain: "KivodoTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The disk is full."]
        )
        store.errorToThrow = error
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        #expect(vm.phase == .failed("The disk is full."))
    }

    @Test func ignoresSubmitWhileSaveInFlight() async {
        let store = SuspendingReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"

        let firstSubmit = Task { await vm.submit() }
        while vm.phase != .saving { await Task.yield() }

        // Second Enter press while the first save is still awaiting the store.
        let secondSubmit = Task { await vm.submit() }
        for _ in 0..<10 { await Task.yield() }

        store.resumeAll()
        await firstSubmit.value
        await secondSubmit.value

        #expect(store.savedTitles == ["Buy milk"])
        #expect(vm.phase == .saved)
    }

    @Test func staleSaveDoesNotClobberNewPresentation() async {
        let store = SuspendingReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "Old todo"

        let submit = Task { await vm.submit() }
        while vm.phase != .saving { await Task.yield() }

        // Save wedges (first-run TCC dialog); user reopens the panel and types.
        vm.reset()
        vm.text = "New todo"

        store.resumeAll()
        await submit.value

        #expect(vm.text == "New todo")
        #expect(vm.phase == .idle)
    }

    @Test func staleSaveErrorDoesNotClobberNewPresentation() async {
        let store = SuspendingReminderStore()
        store.errorToThrow = ReminderError.accessDenied
        let vm = CaptureViewModel(store: store)
        vm.text = "Old todo"

        let submit = Task { await vm.submit() }
        while vm.phase != .saving { await Task.yield() }

        vm.reset()
        vm.text = "New todo"

        store.resumeAll()
        await submit.value

        #expect(vm.text == "New todo")
        #expect(vm.phase == .idle)
    }

    // MARK: - Destinations

    @Test func submitPassesNilListIDWhenUnconfigured() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        #expect(store.savedListIDs == [nil])
    }

    @Test func submitPassesSelectedListIDAndToggleSwitchesIt() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.updateDestinations([work, home])
        vm.text = "Buy milk"
        await vm.submit()
        #expect(store.savedListIDs == ["work-id"])

        vm.toggleDestination()
        vm.text = "Call plumber"
        await vm.submit()
        #expect(store.savedListIDs == ["work-id", "home-id"])
    }

    @Test func toggleDestinationNoOpsBelowTwoDestinations() {
        let vm = CaptureViewModel(store: MockReminderStore())

        vm.toggleDestination()
        #expect(vm.selectedDestinationIndex == 0)
        #expect(vm.selectedDestination == nil)

        vm.updateDestinations([work])
        vm.toggleDestination()
        #expect(vm.selectedDestinationIndex == 0)
        #expect(vm.selectedDestination == work)
    }

    @Test func updateDestinationsPreservesSelectionByIDOrFallsBackToFirst() {
        let vm = CaptureViewModel(store: MockReminderStore())
        vm.updateDestinations([work, home])
        vm.toggleDestination()
        #expect(vm.selectedDestination == home)

        // Same id survives a reorder and a title change: still selected.
        let renamedHome = ReminderList(id: "home-id", title: "Household")
        vm.updateDestinations([renamedHome, work])
        #expect(vm.selectedDestinationIndex == 0)
        #expect(vm.selectedDestination == renamedHome)

        // The selected id disappears: back to the first list.
        vm.updateDestinations([work, ReminderList(id: "errands-id", title: "Errands")])
        #expect(vm.selectedDestinationIndex == 0)
        #expect(vm.selectedDestination == work)
    }

    @Test func listNotFoundReportsSettingsHintAndKeepsText() async {
        let store = MockReminderStore()
        store.errorToThrow = ReminderError.listNotFound
        let vm = CaptureViewModel(store: store)
        vm.updateDestinations([work, home])
        vm.text = "Buy milk"
        await vm.submit()
        #expect(vm.phase == .failed("That list no longer exists — pick it again in Settings."))
        #expect(vm.text == "Buy milk")
    }

    @Test func clearingDestinationsFallsBackToDefaultList() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.updateDestinations([work, home])
        vm.toggleDestination()

        // User cleared the pair in Settings; PanelController pushes [] on show.
        vm.updateDestinations([])
        #expect(vm.selectedDestination == nil)

        vm.text = "Buy milk"
        await vm.submit()
        #expect(store.savedListIDs == [nil])
    }

    @Test func resetKeepsDestinationsAndSelection() {
        let vm = CaptureViewModel(store: MockReminderStore())
        vm.updateDestinations([work, home])
        vm.toggleDestination()
        vm.reset()
        #expect(vm.destinations == [work, home])
        #expect(vm.selectedDestinationIndex == 1)
        #expect(vm.selectedDestination == home)
    }
}
