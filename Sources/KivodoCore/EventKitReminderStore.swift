import EventKit

/// `@unchecked Sendable` is safe here: EKEventStore is documented as
/// thread-safe, and the only stored property (`store`) is immutable.
public final class EventKitReminderStore: ReminderStore, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func save(title: String, to listID: String?) async throws {
        try await ensureAccess()
        let calendar: EKCalendar
        if let listID {
            guard let found = store.calendar(withIdentifier: listID),
                  found.allowsContentModifications else {
                throw ReminderError.listNotFound
            }
            calendar = found
        } else {
            guard let defaultCalendar = store.defaultCalendarForNewReminders() else {
                throw ReminderError.noDefaultList
            }
            calendar = defaultCalendar
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
    }

    public func availableLists() async throws -> [ReminderList] {
        try await ensureAccess()
        return store.calendars(for: .reminder).map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title)
        }
    }

    private func ensureAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToReminders()
            if !granted { throw ReminderError.accessDenied }
        default:
            throw ReminderError.accessDenied
        }
    }
}
