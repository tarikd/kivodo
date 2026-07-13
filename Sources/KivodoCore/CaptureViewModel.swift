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
    /// The configured destination lists; empty when the toggle is unconfigured.
    public private(set) var destinations: [ReminderList] = []
    public private(set) var selectedDestinationIndex = 0

    public var selectedDestination: ReminderList? {
        destinations.indices.contains(selectedDestinationIndex)
            ? destinations[selectedDestinationIndex] : nil
    }

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
            try await store.save(title: title, to: selectedDestination?.id)
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
            case ReminderError.listNotFound:
                phase = .failed("That list no longer exists — pick it again in Settings.")
            default:
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Flips between the two destinations; does nothing when fewer than two
    /// are configured.
    public func toggleDestination() {
        guard destinations.count >= 2 else { return }
        selectedDestinationIndex = (selectedDestinationIndex + 1) % destinations.count
    }

    /// Replaces the destination lists. If the previously selected list still
    /// exists (by id) it stays selected; otherwise the first list is.
    public func updateDestinations(_ lists: [ReminderList]) {
        let selectedID = selectedDestination?.id
        destinations = lists
        if let selectedID, let index = lists.firstIndex(where: { $0.id == selectedID }) {
            selectedDestinationIndex = index
        } else {
            selectedDestinationIndex = 0
        }
    }

    /// Clears per-presentation state. Destinations and the selected list
    /// intentionally survive so the choice is remembered across panel shows.
    public func reset() {
        phase = .idle
        text = ""
        presentationCount += 1
    }
}
