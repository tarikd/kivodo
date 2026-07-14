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
    /// Fires after a Space swipe has re-keyed the still-visible panel, so the
    /// controller can re-assert first-responder focus in the SwiftUI field.
    var onSpaceChange: (() -> Void)?

    private var tabMonitor: Any?
    /// Fires on mouse-down anywhere outside the panel — the "click outside"
    /// dismissal. A global monitor (not resignKey) so switching Spaces or
    /// apps, which also drop key status, leaves the panel up; with
    /// .canJoinAllSpaces it follows the user to the new Space.
    private var clickOutMonitor: Any?
    /// Set for a brief window around a Space change. The OS resigns the
    /// panel's key status and posts activeSpaceDidChangeNotification in a
    /// non-deterministic order — sometimes resignKey fires *after* the
    /// notification, so re-keying only at notification time loses the race on
    /// every other swipe. This flag lets resignKey re-key too, but only when a
    /// Space change is what caused it (not a click-outside or app-switch).
    private var spaceChangeInFlight = false

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

        // A Space swipe drops key status but leaves the panel visible (it
        // follows via .canJoinAllSpaces). Re-key it so the field keeps
        // receiving keystrokes and Escape keeps working without a click. The
        // panel is created once and lives for the app's lifetime, so the
        // observer is never removed (matching ShortcutStatus in KivodoApp).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSpaceChange() }
        }
    }

    /// A Space change resigns the panel's key status but leaves it visible (it
    /// follows via .canJoinAllSpaces). The OS's resignKey and this notification
    /// arrive in a non-deterministic order, so re-key from both:
    ///   - here, in case the panel was already resigned (resign came first);
    ///   - in resignKey, guarded by the flag, for when resign comes later.
    /// The flag is what tells resignKey a Space change (not a click-outside)
    /// caused it. Cleared after a short window so a later unrelated resignKey
    /// doesn't wrongly re-key.
    private func handleSpaceChange() {
        guard isVisible else { return }
        spaceChangeInFlight = true
        reacquireKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.spaceChangeInFlight = false
        }
    }

    /// Restore key status if the panel is still up (never resurrect a dismissed
    /// panel). makeKey — not makeKeyAndOrderFront or NSApp.activate — keeps
    /// this a non-activating panel, so the frontmost app keeps its visual
    /// focus. onSpaceChange re-asserts the SwiftUI field's first responder.
    private func reacquireKey() {
        guard isVisible, !isKeyWindow else { return }
        makeKey()
        onSpaceChange?()
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
        // A Space swipe often resigns key *after* activeSpaceDidChange fired,
        // so the notification's re-key ran too early. Re-key here instead, once
        // the resignation has settled. Only when a Space change caused it —
        // click-outside and app-switch also resign, and those must not re-key.
        guard spaceChangeInFlight else { return }
        DispatchQueue.main.async { [weak self] in self?.reacquireKey() }
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
