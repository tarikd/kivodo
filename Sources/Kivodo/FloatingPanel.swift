import AppKit

/// A Spotlight-style panel: floats over everything, receives keystrokes
/// without activating the app (so the frontmost app keeps visual focus).
final class FloatingPanel: NSPanel {
    /// May fire more than once per dismissal, so handlers must be idempotent.
    var onDismiss: (() -> Void)?
    /// Plain Tab pressed while the panel is key (destination toggle). Handled
    /// with a local NSEvent monitor because the field editor consumes Tab
    /// before SwiftUI's onKeyPress ever sees it.
    var onTab: (() -> Void)?

    private var tabMonitor: Any?
    /// Fires on mouse-down anywhere outside the panel — the "click outside"
    /// dismissal. A global monitor (not resignKey) so switching Spaces or
    /// apps, which also drop key status, leaves the panel up; with
    /// .canJoinAllSpaces it follows the user to the new Space.
    private var clickOutMonitor: Any?

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

    // Key status is dropped on click-outside, app-switch, AND Space switch.
    // Only clean up the Tab monitor here; dismissal is driven by an explicit
    // click-outside monitor instead, so a Space swipe keeps the panel up.
    override func resignKey() {
        super.resignKey()
        if let tabMonitor {
            NSEvent.removeMonitor(tabMonitor)
            self.tabMonitor = nil
        }
    }

    // The click-outside monitor tracks visibility, not key status: a Space
    // switch resigns key but the panel stays visible (and follows via
    // .canJoinAllSpaces), so a click on the new Space must still dismiss it.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        installClickOutMonitor()
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        removeClickOutMonitor()
    }

    private func installClickOutMonitor() {
        guard clickOutMonitor == nil else { return }
        // Global monitor: fires only for mouse-downs outside this app's
        // windows. Clicks inside the panel are local events and don't reach
        // it, so interacting with the field or chip never dismisses.
        clickOutMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.onDismiss?()
        }
    }

    private func removeClickOutMonitor() {
        if let clickOutMonitor {
            NSEvent.removeMonitor(clickOutMonitor)
            self.clickOutMonitor = nil
        }
    }
}
