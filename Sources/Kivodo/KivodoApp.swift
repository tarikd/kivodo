import SwiftUI

@main
struct KivodoApp: App {
    var body: some Scene {
        MenuBarExtra("Kivodo", systemImage: "checkmark.circle") {
            Button("Quit Kivodo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
