# Kivodo Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Git rules:** Per CLAUDE.md — run every commit message through `/humanizer`, never include AI attribution.

**Goal:** A menu bar app whose global hotkey (⌥ Space) opens a non-activating floating panel that saves typed todos to Apple Reminders.

**Architecture:** Swift Package with two targets — `KivodoCore` (library: view model + Reminders access, unit-testable) and `Kivodo` (executable: SwiftUI `MenuBarExtra`, `NSPanel`, Carbon hotkey). A Makefile assembles the `.app` bundle (Info.plist, ad-hoc codesign) since TCC permission prompts require a real bundle. This satisfies the design doc's "xcodebuild or ⌘R" — Xcode opens `Package.swift` directly.

**Tech Stack:** Swift 6 / SwiftUI, AppKit (`NSPanel`), Carbon (`RegisterEventHotKey` — permission-free), EventKit, Swift Testing (`import Testing`). Zero third-party dependencies. macOS 14+.

---

### Task 1: Package scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/KivodoCore/ReminderStore.swift`
- Create: `Sources/Kivodo/KivodoApp.swift`
- Create: `Tests/KivodoCoreTests/CaptureViewModelTests.swift`
- Create: `.gitignore`

**Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kivodo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KivodoCore"),
        .executableTarget(name: "Kivodo", dependencies: ["KivodoCore"]),
        .testTarget(name: "KivodoCoreTests", dependencies: ["KivodoCore"]),
    ]
)
```

**Step 2: Write `.gitignore`**

```
.build/
build/
.DS_Store
.swiftpm/
```

**Step 3: Write placeholder sources so the package builds**

`Sources/KivodoCore/ReminderStore.swift`:

```swift
public protocol ReminderStore: Sendable {
    /// Saves a reminder with the given title to the default list.
    /// Throws ReminderError.accessDenied or .noDefaultList.
    func save(title: String) async throws
}

public enum ReminderError: Error, Equatable {
    case accessDenied
    case noDefaultList
}
```

`Sources/Kivodo/KivodoApp.swift` (minimal for now, replaced in Task 5):

```swift
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
```

`Tests/KivodoCoreTests/CaptureViewModelTests.swift` (placeholder):

```swift
import Testing
@testable import KivodoCore

@Test func packageBuilds() {
    #expect(ReminderError.accessDenied == ReminderError.accessDenied)
}
```

**Step 4: Verify build and tests**

Run: `swift build && swift test`
Expected: `Build complete!` and `Test run with 1 test passed`.

**Step 5: Commit**

Humanize via `/humanizer` first. Suggested shape: `Scaffold Swift package with core and app targets`

---

### Task 2: CaptureViewModel (TDD)

The view model owns all capture logic: trims input, rejects empty text with a shake counter, maps store errors to UI phases, preserves text on failure.

**Files:**
- Create: `Sources/KivodoCore/CaptureViewModel.swift`
- Modify: `Tests/KivodoCoreTests/CaptureViewModelTests.swift` (replace placeholder)

**Step 1: Write the failing tests**

Replace `Tests/KivodoCoreTests/CaptureViewModelTests.swift` with:

```swift
import Testing
@testable import KivodoCore

@MainActor
final class MockReminderStore: ReminderStore, @unchecked Sendable {
    var savedTitles: [String] = []
    var errorToThrow: Error?

    nonisolated init() {}

    func save(title: String) async throws {
        if let errorToThrow { throw errorToThrow }
        savedTitles.append(title)
    }
}

@MainActor
struct CaptureViewModelTests {
    @Test func savesTrimmedTitleAndClearsText() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "  Buy milk  "
        await vm.submit()
        #expect(store.savedTitles == ["Buy milk"])
        #expect(vm.phase == .saved)
        #expect(vm.text.isEmpty)
    }

    @Test func emptyInputShakesWithoutSaving() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "   "
        await vm.submit()
        #expect(store.savedTitles.isEmpty)
        #expect(vm.shakeCount == 1)
        #expect(vm.phase == .idle)
    }

    @Test func accessDeniedShowsPermissionPhase() async {
        let store = MockReminderStore()
        store.errorToThrow = ReminderError.accessDenied
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        #expect(vm.phase == .needsPermission)
    }

    @Test func saveFailureKeepsTextAndReportsError() async {
        let store = MockReminderStore()
        store.errorToThrow = ReminderError.noDefaultList
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        #expect(vm.phase == .failed("No default Reminders list is configured."))
        #expect(vm.text == "Buy milk")
    }

    @Test func resetClearsStateForNextPresentation() async {
        let store = MockReminderStore()
        let vm = CaptureViewModel(store: store)
        vm.text = "Buy milk"
        await vm.submit()
        vm.reset()
        #expect(vm.phase == .idle)
        #expect(vm.text.isEmpty)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile error — `CaptureViewModel` not defined.

**Step 3: Write the implementation**

`Sources/KivodoCore/CaptureViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class CaptureViewModel {
    public enum Phase: Equatable {
        case idle
        case saving
        case saved
        case needsPermission
        case failed(String)
    }

    public var text = ""
    public private(set) var phase: Phase = .idle
    public private(set) var shakeCount = 0
    /// Changes every time the panel is shown; the view observes it to refocus the field.
    public private(set) var presentationCount = 0

    private let store: ReminderStore

    public init(store: ReminderStore) {
        self.store = store
    }

    public func submit() async {
        guard phase != .saving else { return }
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            shakeCount += 1
            return
        }
        phase = .saving
        do {
            try await store.save(title: title)
            phase = .saved
            text = ""
        } catch ReminderError.accessDenied {
            phase = .needsPermission
        } catch ReminderError.noDefaultList {
            phase = .failed("No default Reminders list is configured.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func reset() {
        phase = .idle
        text = ""
        presentationCount += 1
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: `Test run with 5 tests passed` (placeholder test was replaced).

**Step 5: Commit**

Humanize via `/humanizer`. Suggested shape: `Add capture view model with submit/reset logic`

---

### Task 3: EventKitReminderStore

Thin EventKit wrapper — no unit tests (it's all system API); verified manually in Task 7.

**Files:**
- Create: `Sources/KivodoCore/EventKitReminderStore.swift`

**Step 1: Write the implementation**

```swift
import EventKit

public final class EventKitReminderStore: ReminderStore, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func save(title: String) async throws {
        try await ensureAccess()
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw ReminderError.noDefaultList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
    }

    private func ensureAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToReminders()
            if !granted { throw ReminderError.accessDenied }
        default:
            throw ReminderError.accessDenied
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build && swift test`
Expected: build succeeds, 5 tests still pass.

**Step 3: Commit**

Humanize via `/humanizer`. Suggested shape: `Add EventKit-backed reminder store`

---

### Task 4: FloatingPanel + CaptureView (the UI)

**Files:**
- Create: `Sources/Kivodo/FloatingPanel.swift`
- Create: `Sources/Kivodo/CaptureView.swift`

**Step 1: Write `FloatingPanel.swift`**

```swift
import AppKit

/// A Spotlight-style panel: floats over everything, receives keystrokes
/// without activating the app (so the frontmost app keeps visual focus).
final class FloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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

    // Escape.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    // Click outside / anything else takes key status away.
    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}
```

**Step 2: Write `CaptureView.swift`**

```swift
import SwiftUI
import KivodoCore

struct CaptureView: View {
    @Bindable var viewModel: CaptureViewModel
    var onDismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if viewModel.phase == .needsPermission {
                permissionRow
            } else {
                inputRow
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 560, height: 64)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .modifier(Shake(animatableData: CGFloat(viewModel.shakeCount)))
        .onExitCommand { onDismiss() }
        .onChange(of: viewModel.presentationCount) {
            focused = true
        }
        .onAppear { focused = true }
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.phase == .saved
                  ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 20))
                .foregroundStyle(viewModel.phase == .saved ? .green : .secondary)
            TextField("Add a reminder…", text: $viewModel.text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
                .onSubmit { submit() }
            if case .failed(let message) = viewModel.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 160)
            }
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.circle")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            Text("Kivodo needs Reminders access")
                .font(.system(size: 16))
            Spacer()
            Button("Open Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
                NSWorkspace.shared.open(url)
                onDismiss()
            }
        }
    }

    private func submit() {
        Task {
            await viewModel.submit()
            if viewModel.phase == .saved {
                try? await Task.sleep(for: .milliseconds(350))
                onDismiss()
            }
        }
    }
}

/// Frosted-glass background matching Spotlight/ChatGPT.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Login-window-style horizontal shake, driven by incrementing shakeCount.
struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakesPerUnit),
            y: 0
        ))
    }
}
```

Note: the shake needs the change animated. In `CaptureViewModel.submit()` the increment is plain; the view animates it because `Shake.animatableData` interpolates when wrapped in `withAnimation` — add `.animation(.default, value: viewModel.shakeCount)` to the `Group` if the shake doesn't animate during manual testing.

**Step 3: Verify it compiles**

Run: `swift build`
Expected: `Build complete!`

**Step 4: Commit**

Humanize via `/humanizer`. Suggested shape: `Add floating panel and capture view`

---

### Task 5: HotKeyManager, PanelController, app wiring

**Files:**
- Create: `Sources/Kivodo/HotKeyManager.swift`
- Create: `Sources/Kivodo/PanelController.swift`
- Modify: `Sources/Kivodo/KivodoApp.swift` (replace placeholder)

**Step 1: Write `HotKeyManager.swift`**

Carbon `RegisterEventHotKey` is the one global-hotkey API that needs no
Accessibility/Input Monitoring permission. `kVK_Space` = 49, `optionKey` = 2048.

```swift
import Carbon.HIToolbox

final class HotKeyManager {
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onHotKey?() }
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: 0x4B49564F /* 'KIVO' */, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
```

**Step 2: Write `PanelController.swift`**

```swift
import AppKit
import SwiftUI
import KivodoCore

@MainActor
final class PanelController {
    private let viewModel: CaptureViewModel
    private var panel: FloatingPanel?

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        viewModel.reset()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 64))
        panel.onDismiss = { [weak self] in self?.close() }
        let view = CaptureView(viewModel: viewModel) { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        return panel
    }

    /// Spotlight position: centered, a third of the way down the screen
    /// that currently contains the mouse pointer.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - frame.height / 3 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
```

**Step 3: Replace `KivodoApp.swift`**

```swift
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
```

**Step 4: Verify build and tests**

Run: `swift build && swift test`
Expected: build succeeds, 5 tests pass.

**Step 5: Commit**

Humanize via `/humanizer`. Suggested shape: `Wire up hotkey, panel controller, and menu bar app`

---

### Task 6: App bundle (Info.plist + Makefile)

TCC (the Reminders permission prompt) requires a signed `.app` bundle with a
usage description — a bare `swift run` binary won't get the prompt.

**Files:**
- Create: `Support/Info.plist`
- Create: `Makefile`

**Step 1: Write `Support/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.tarik.kivodo</string>
    <key>CFBundleName</key>
    <string>Kivodo</string>
    <key>CFBundleExecutable</key>
    <string>Kivodo</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Kivodo saves your todos to Apple Reminders.</string>
</dict>
</plist>
```

**Step 2: Write `Makefile`**

```makefile
APP = build/Kivodo.app
BIN = $(shell swift build -c release --show-bin-path)/Kivodo

.PHONY: app run test clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/Kivodo
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf build .build
```

Note: ad-hoc signing (`--sign -`) changes the code hash on every rebuild, so
macOS may re-ask for Reminders permission after rebuilds. Fine for
development; a stable "Apple Development" certificate fixes it if it gets
annoying.

**Step 3: Build and launch**

Run: `make run`
Expected: `Kivodo.app` appears in `build/`, launches with a checkmark icon in the menu bar, no Dock icon.

**Step 4: Commit**

Humanize via `/humanizer`. Suggested shape: `Add app bundle packaging via Makefile`

---

### Task 7: Manual verification (checklist from design doc)

No code — walk the checklist with the app running (`make run`):

- [ ] ⌥ Space opens the panel over a normal app; that app's window stays visually focused (title bar not dimmed)
- [ ] Typing goes into the panel; Enter triggers the Reminders permission prompt on first use
- [ ] After granting: reminder appears in Reminders.app default list; checkmark flashes; panel closes
- [ ] Keystrokes go back to the original app after dismissal
- [ ] Escape dismisses and discards text
- [ ] Click outside dismisses
- [ ] ⌥ Space toggles (second press closes)
- [ ] Works over a full-screen app and on a second Space
- [ ] Empty Enter: shake, no reminder created, panel stays open
- [ ] Deny permission (System Settings → Privacy → Reminders, toggle off), retry: panel shows "Open Settings" row and the button lands on the right pane
- [ ] Re-grant permission in System Settings, then retry WITHOUT relaunching Kivodo: save succeeds (guards against a stale pre-grant EKEventStore returning no default list; if this fails, create the store lazily in save or call reset() on status change)
- [ ] First-run permission dialog: panel stays visible behind the system prompt during the save (dismissal is suppressed while saving); after granting, confirmation shows and reminder is created

Fix anything that fails (small fixes inline; anything structural goes back
through the plan). Then commit fixes (humanized messages) and update the
design doc if behavior changed.
