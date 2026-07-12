import EventKit

public final class EventKitReminderStore: ReminderStore, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func save(title: String) async throws {
        try await ensureAccess()
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw ReminderError.noDefaultList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
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
