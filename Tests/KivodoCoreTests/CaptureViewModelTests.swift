import Foundation
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

/// A store whose save(title:) suspends until resumeAll() is called, so tests
/// can interleave a second submit while the first is still in flight.
@MainActor
final class SuspendingReminderStore: ReminderStore, @unchecked Sendable {
    var savedTitles: [String] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    nonisolated init() {}

    func save(title: String) async throws {
        await withCheckedContinuation { continuations.append($0) }
        savedTitles.append(title)
    }

    func resumeAll() {
        let pending = continuations
        continuations = []
        for continuation in pending { continuation.resume() }
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
}
