import Carbon.HIToolbox
import AppKit

/// Global ⌘⇧V hotkey via the classic Carbon Events API. Chosen over NSEvent global
/// monitors because RegisterEventHotKey doesn't require Accessibility permission
/// just to open the history panel.
final class HotKeyManager {
    // ponytail: hotkey is a fixed constant; add a preferences recorder UI if
    // per-user rebinding is ever needed.
    private static let keyCode: UInt32 = 9 // 'v'
    private static let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    private static let signature: OSType = 0x485A_5041 // 'HZPA'

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == HotKeyManager.signature else { return noErr }
            Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().onTrigger()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(Self.keyCode, Self.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    deinit { unregister() }
}
