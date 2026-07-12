import Carbon.HIToolbox
import Foundation

@MainActor
final class HotKeyManager {
    var onHotKey: (() -> Void)?

    // nonisolated(unsafe) so the nonisolated deinit can clean up; safe because
    // the refs are only written on the main actor and deinit runs exclusively.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { manager.onHotKey?() }
                }
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )
        if handlerStatus != noErr {
            NSLog("Kivodo: hotkey handler installation failed (status %d)", handlerStatus)
        }
        let hotKeyID = EventHotKeyID(signature: 0x4B49564F /* 'KIVO' */, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus != noErr {
            NSLog("Kivodo: hotkey registration failed (status %d)", hotKeyStatus)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
