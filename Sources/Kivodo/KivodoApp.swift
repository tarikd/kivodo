import SwiftUI
import KivodoCore

@main
struct KivodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Kivodo", systemImage: "checkmark.circle") {
            Text("Capture: ⌥ Space")
            Divider()
            Button("Quit Kivodo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private let hotKey = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PanelController(
            viewModel: CaptureViewModel(store: EventKitReminderStore())
        )
        panelController = controller
        hotKey.onHotKey = { controller.toggle() }
        hotKey.register()
    }
}
