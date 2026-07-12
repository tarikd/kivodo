import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture shortcut:", name: .toggleCapture)
        }
        .padding()
        .frame(width: 320)
    }
}
