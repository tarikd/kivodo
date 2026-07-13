import SwiftUI
import KeyboardShortcuts
import KivodoCore

@main
struct KivodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var shortcutStatus = ShortcutStatus()

    var body: some Scene {
        MenuBarExtra("Kivodo", systemImage: "checkmark.circle") {
            // The hotkey is registered globally by KeyboardShortcuts, not a
            // menu key equivalent, so this row is a label + trailing shortcut
            // display rather than an actionable Button.
            LabeledContent("Capture", value: shortcutStatus.current?.description ?? "not set")
            Divider()
            SettingsMenuItem()
            Button("Quit Kivodo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView(store: appDelegate.reminderStore)
        }
    }
}

/// Tracks the current capture shortcut as observable state. The menu content
/// is cached by SwiftUI, and `getShortcut(for:)` alone gives it no
/// invalidation signal — the menu line would show a stale shortcut after
/// re-recording. The package posts a notification on every change (internal
/// API — the dependency is pinned to 2.4.x in Package.swift because of this).
/// The observer is intentionally app-lifetime; no removal needed.
@MainActor
@Observable
final class ShortcutStatus {
    private(set) var current = KeyboardShortcuts.getShortcut(for: .toggleCapture)

    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.current = KeyboardShortcuts.getShortcut(for: .toggleCapture)
            }
        }
    }
}

/// Menu item that opens the Settings scene and makes its window key.
private struct SettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            openSettings()
            // The menu is still dismissing at this point, and macOS hands
            // activation back to the previously active app as it closes —
            // activating now would be undone, leaving the settings window
            // visible but not key (the first click then goes to activation
            // instead of the shortcut recorder). Activate after the dismissal
            // settles and force the window key.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows
                    .first { $0.identifier?.rawValue.hasPrefix("com_apple_SwiftUI_Settings") == true }?
                    .makeKeyAndOrderFront(nil)
            }
        }
        .keyboardShortcut(",")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared with the Settings scene so its pickers reuse the same
    /// EventKit connection (and permission state) as the capture panel.
    let reminderStore = EventKitReminderStore()
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PanelController(
            viewModel: CaptureViewModel(store: reminderStore)
        )
        panelController = controller
        // KeyboardShortcuts invokes key-down handlers on the main thread.
        KeyboardShortcuts.onKeyDown(for: .toggleCapture) { controller.toggle() }
    }
}
