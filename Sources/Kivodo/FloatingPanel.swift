import AppKit

/// A Spotlight-style panel: floats over everything, receives keystrokes
/// without activating the app (so the frontmost app keeps visual focus).
final class FloatingPanel: NSPanel {
    /// May fire more than once per dismissal (Escape → orderOut → resignKey
    /// chain), so handlers must be idempotent.
    var onDismiss: (() -> Void)?
    /// Plain Tab pressed while the panel is key (destination toggle). Handled
    /// with a local NSEvent monitor because the field editor consumes Tab
    /// before SwiftUI's onKeyPress ever sees it.
    var onTab: (() -> Void)?

    private var tabMonitor: Any?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // NSPanel releases itself on close() by default, which would
        // over-release this ARC-owned window.
        isReleasedWhenClosed = false
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

    // The Tab monitor lives only while the panel is key, so background
    // Tab presses in other apps are untouched.
    override func becomeKey() {
        super.becomeKey()
        guard tabMonitor == nil else { return }
        tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self,
                  event.keyCode == 48, // Tab
                  // Ignore latched Caps Lock; it must not disqualify a plain Tab.
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                      .subtracting(.capsLock).isEmpty
            else { return event }
            self.onTab?()
            return nil
        }
    }

    // Escape.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    // Click outside / anything else takes key status away.
    override func resignKey() {
        super.resignKey()
        if let tabMonitor {
            NSEvent.removeMonitor(tabMonitor)
            self.tabMonitor = nil
        }
        onDismiss?()
    }
}
