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
        guard phase != .saving else { return }
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            shakeCount += 1
            return
        }
        phase = .saving
        // If the panel is re-presented while the save is in flight (reset()
        // bumps presentationCount), the result belongs to a stale session and
        // must not touch the new one's phase or text.
        let presentation = presentationCount
        do {
            try await store.save(title: title)
            guard presentationCount == presentation else { return }
            phase = .saved
            text = ""
        } catch {
            guard presentationCount == presentation else { return }
            switch error {
            case ReminderError.accessDenied:
                phase = .needsPermission
            case ReminderError.noDefaultList:
                phase = .failed("No default Reminders list is configured.")
            default:
                phase = .failed(error.localizedDescription)
            }
        }
    }

    public func reset() {
        phase = .idle
        text = ""
        presentationCount += 1
    }
}
