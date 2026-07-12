import SwiftUI
import KeyboardShortcuts
import KivodoCore

@main
struct KivodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Kivodo", systemImage: "checkmark.circle") {
            Text("Capture: \(KeyboardShortcuts.getShortcut(for: .toggleCapture)?.description ?? "not set")")
            Divider()
            SettingsMenuItem()
            Button("Quit Kivodo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
        }
    }
}

/// Menu item that opens the Settings scene. LSUIElement apps don't activate
/// on their own, so the app is activated first or the window would open
/// behind whatever is frontmost.
private struct SettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PanelController(
            viewModel: CaptureViewModel(store: EventKitReminderStore())
        )
        panelController = controller
        // KeyboardShortcuts invokes key-down handlers on the main thread.
        KeyboardShortcuts.onKeyDown(for: .toggleCapture) { controller.toggle() }
    }
}
