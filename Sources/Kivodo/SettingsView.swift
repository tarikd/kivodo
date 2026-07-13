import SwiftUI
import KeyboardShortcuts
import KivodoCore

struct SettingsView: View {
    let store: any ReminderStore

    @AppStorage(DestinationConfig.keys.id1) private var list1ID = ""
    @AppStorage(DestinationConfig.keys.id2) private var list2ID = ""
    @State private var lists: [ReminderList] = []
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            shortcutSection
            destinationsSection
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            do {
                lists = try await store.availableLists()
                // A rename keeps the id, so onChange never re-fires for it;
                // refresh the cached titles on every Settings open instead.
                cacheTitle(for: list1ID, key: DestinationConfig.keys.title1)
                cacheTitle(for: list2ID, key: DestinationConfig.keys.title2)
            } catch {
                loadFailed = true
            }
        }
        .onChange(of: list1ID) { _, newValue in
            cacheTitle(for: newValue, key: DestinationConfig.keys.title1)
        }
        .onChange(of: list2ID) { _, newValue in
            cacheTitle(for: newValue, key: DestinationConfig.keys.title2)
        }
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        SettingsSection(header: "Shortcut", caption: "If a combo does nothing when you press it, another app is already using it globally (the ChatGPT app claims ⌥ Space, macOS claims ⌘ Space and ⌃ Space).") {
            SettingsRow {
                Text("Capture shortcut")
                Spacer(minLength: 12)
                KeyboardShortcuts.Recorder(for: .toggleCapture)
                    .labelsHidden()
            }
            RowDivider()
            SettingsRow {
                Text("Reset to default")
                Spacer(minLength: 12)
                Button("⌥ Space") {
                    KeyboardShortcuts.reset(.toggleCapture)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13, weight: .medium))
            }
        }
    }

    // MARK: - Destinations

    private var destinationsSection: some View {
        SettingsSection(
            header: "Destinations",
            caption: loadFailed ? nil : "Pick two different lists to get a destination toggle in the capture panel."
        ) {
            if loadFailed {
                SettingsRow {
                    Text("Kivodo needs Reminders access to show your lists.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                }
                RowDivider()
                SettingsRow {
                    Spacer()
                    Button("Open Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                listPickerRow("List 1", selection: $list1ID)
                RowDivider()
                listPickerRow("List 2", selection: $list2ID)
            }
        }
    }

    private func listPickerRow(_ label: String, selection: Binding<String>) -> some View {
        SettingsRow {
            Text(label)
            Spacer(minLength: 12)
            Picker(label, selection: selection) {
                Text("None").tag("")
                ForEach(lists) { Text($0.title).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    /// The chip needs a title without an EventKit round trip, so Settings
    /// caches the picked list's title next to its id.
    private func cacheTitle(for id: String, key: String) {
        let title = lists.first { $0.id == id }?.title
        UserDefaults.standard.set(title, forKey: key)
    }
}

// MARK: - Grouped card building blocks

/// An uppercase section caption, an inset card holding the rows, and an
/// optional left-aligned caption below — the macOS System Settings look the
/// generic .formStyle(.grouped) doesn't reproduce (Title Case headers,
/// centered captions).
private struct SettingsSection<Content: View>: View {
    let header: String
    let caption: String?
    @ViewBuilder let content: Content

    init(header: String, caption: String?, @ViewBuilder content: () -> Content) {
        self.header = header
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.cardBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One row inside a card: a leading-to-trailing HStack with the standard
/// 13pt/16pt padding from the mockup.
private struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .font(.system(size: 14))
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
    }
}

/// A hairline row separator inset from the leading edge, matching the card's
/// `margin-left:16px` divider in the mockup.
private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.cardBorder)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}

private extension Color {
    /// One step off the window background (mockup card `#28282c` on `#1e1e22`).
    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 1, alpha: 0.55)
    })
    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.1)
    })
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
