import SwiftUI
import KeyboardShortcuts
import KivodoCore

struct SettingsView: View {
    let store: EventKitReminderStore

    @AppStorage(DestinationConfig.keys.id1) private var list1ID = ""
    @AppStorage(DestinationConfig.keys.id2) private var list2ID = ""
    @State private var lists: [ReminderList] = []
    @State private var loadFailed = false

    init(store: EventKitReminderStore) {
        self.store = store
    }

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

            Divider()

            Text("Destinations")
                .font(.headline)
            if loadFailed {
                Text("Kivodo needs Reminders access to show your lists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Open Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                Picker("List 1", selection: $list1ID) {
                    Text("None").tag("")
                    ForEach(lists) { Text($0.title).tag($0.id) }
                }
                Picker("List 2", selection: $list2ID) {
                    Text("None").tag("")
                    ForEach(lists) { Text($0.title).tag($0.id) }
                }
                Text("Pick two different lists to get a destination toggle in the capture panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
        .task {
            do { lists = try await store.availableLists() } catch { loadFailed = true }
        }
        .onChange(of: list1ID) { _, newValue in
            cacheTitle(for: newValue, key: DestinationConfig.keys.title1)
        }
        .onChange(of: list2ID) { _, newValue in
            cacheTitle(for: newValue, key: DestinationConfig.keys.title2)
        }
    }

    /// The chip needs a title without an EventKit round trip, so Settings
    /// caches the picked list's title next to its id.
    private func cacheTitle(for id: String, key: String) {
        let title = lists.first { $0.id == id }?.title
        UserDefaults.standard.set(title, forKey: key)
    }
}
