import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` — the single place that reconciles the
/// "Launch at login" toggle with macOS's real login-item state. Registering
/// the main bundle launches the app hidden at login (it's an `LSUIElement`
/// menu bar app), which is what we want.
@MainActor
@Observable
final class LoginItem {
    /// Records that first-launch auto-registration has happened, so we only
    /// force it once per install rather than fighting the user's later choice.
    private static let configuredKey = "launchAtLoginConfigured"

    /// Reads live status on every access, so the toggle stays honest even if
    /// macOS drops the registration between Settings opens. The setter
    /// register/unregisters and swallows the throw — a failed call just leaves
    /// the recomputed getter reflecting the state macOS actually accepted.
    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Kivodo: login item \(newValue ? "register" : "unregister") failed: \(error)")
            }
        }
    }

    /// Login items are turned off in System Settings or blocked by policy;
    /// registration won't take effect until the user approves it there.
    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Opt-out default: on a fresh install (no saved preference), register as a
    /// login item and record that we've done so. Idempotent across launches.
    func registerOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.configuredKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.configuredKey)
        isEnabled = true
    }
}
