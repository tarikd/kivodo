import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggles the capture panel. Default matches the original hardcoded hotkey.
    static let toggleCapture = Self("toggleCapture", default: .init(.space, modifiers: [.option]))
}
