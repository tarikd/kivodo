public protocol ReminderStore: Sendable {
    /// Saves a reminder with the given title to the default list.
    /// Throws ReminderError.accessDenied or .noDefaultList; may also rethrow underlying store errors.
    func save(title: String) async throws
}

public enum ReminderError: Error, Equatable {
    case accessDenied
    case noDefaultList
}
