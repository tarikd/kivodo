import AppKit

/// A Spotlight-style panel: floats over everything, receives keystrokes
/// without activating the app (so the frontmost app keeps visual focus).
final class FloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    // Borderless windows refuse key status by default; the text field needs it.
    override var canBecomeKey: Bool { true }

    // Escape.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    // Click outside / anything else takes key status away.
    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}
