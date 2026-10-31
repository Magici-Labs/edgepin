import Carbon

/// Global shortcuts through Carbon's RegisterEventHotKey, which still needs no
/// extra permission and works for apps with no Dock icon.
final class Hotkeys {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let refcon { Unmanaged<Hotkeys>.fromOpaque(refcon).takeUnretainedValue().actions[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func register(_ keyCode: Int, _ modifiers: Int, _ action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: OSType(0x4550_696E), id: id), // "EPin"
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log("shortcut \(keyCode) is taken by another app (\(status))")
            return
        }
        refs.append(ref)
        actions[id] = action
    }
}
