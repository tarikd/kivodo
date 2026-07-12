import Foundation
import Observation

@MainActor
@Observable
public final class CaptureViewModel {
    public enum Phase: Equatable {
        case idle
        case saving
        case saved
        case needsPermission
        case failed(String)
    }

    public var text = ""
    public private(set) var phase: Phase = .idle
    public private(set) var shakeCount = 0
    /// Changes every time the panel is shown; the view observes it to refocus the field.
    public private(set) var presentationCount = 0

    private let store: ReminderStore

    public init(store: ReminderStore) {
        self.store = store
    }

    public func submit() async {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            shakeCount += 1
            return
        }
        phase = .saving
        do {
            try await store.save(title: title)
            phase = .saved
            text = ""
        } catch ReminderError.accessDenied {
            phase = .needsPermission
        } catch ReminderError.noDefaultList {
            phase = .failed("No default Reminders list is configured.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func reset() {
        phase = .idle
        text = ""
        presentationCount += 1
    }
}
