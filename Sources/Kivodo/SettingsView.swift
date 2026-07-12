import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KeyboardShortcuts.Recorder("Capture shortcut:", name: .toggleCapture)
            // Combos registered globally by another app never reach the
            // recorder — no beep, no alert. Without this hint that reads as
            // "the setting is broken".
            Text("If a combo does nothing when you press it, another app is already using it globally (the ChatGPT app claims ⌥ Space, macOS claims ⌘ Space and ⌃ Space).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Reset to ⌥ Space") {
                    KeyboardShortcuts.reset(.toggleCapture)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
