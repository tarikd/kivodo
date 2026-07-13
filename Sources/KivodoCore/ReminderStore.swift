/// A Reminders list the user can target.
public struct ReminderList: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public protocol ReminderStore: Sendable {
    /// Saves a reminder to the list with the given identifier, or the
    /// default list when nil. Throws ReminderError.accessDenied,
    /// .noDefaultList, or .listNotFound; may also rethrow underlying store errors.
    func save(title: String, to listID: String?) async throws

    /// All Reminders lists, for the Settings pickers. Requests access if needed.
    func availableLists() async throws -> [ReminderList]
}

public enum ReminderError: Error, Equatable {
    case accessDenied
    case noDefaultList
    case listNotFound
}
