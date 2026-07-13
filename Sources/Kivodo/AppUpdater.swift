#if !MAS_BUILD
import AppKit
import Sparkle

/// Thin wrapper over Sparkle's standard updater. `startingUpdater: true` begins
/// the automatic background check as soon as the controller is created.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Kivodo is an LSUIElement (no Dock icon), so the update window would open
    /// behind the frontmost app. Activate first so the dialog comes forward.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
#endif
