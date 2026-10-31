import AppKit
import ApplicationServices
import Carbon

/// Catches macOS's Window → Fill (fn-⌃F) and Return to Previous Size (fn-⌃R)
/// before the app sees them, so on a screen with a pin the window fills the
/// free area directly instead of the whole screen first.
///
/// A tap of its own, apart from the click one: if macOS refuses to let EdgePin
/// see keystrokes, the green button still works.
final class FillKeys {
    var onFill: (AXUIElement) -> Bool = { _ in false }
    var onRestore: (AXUIElement) -> Bool = { _ in false }

    private var tap: CFMachPort?
    private var handledLast = false

    func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: keyCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log("couldn't watch for the Fill shortcut")
            return
        }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        // Exactly fn and ⌃: this runs on every keystroke, so bail out early.
        let flags = event.flags.intersection([.maskSecondaryFn, .maskControl, .maskAlternate, .maskCommand, .maskShift])
        guard type == .keyDown, flags == [.maskSecondaryFn, .maskControl] else { return false }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard key == kVK_ANSI_F || key == kVK_ANSI_R else { return false }
        // Holding the keys down repeats; act once, and keep the repeats from the
        // app only when the first press was ours.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return handledLast }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AXUIElementCreateApplication(app.processIdentifier).focusedWindow else { return false }
        handledLast = key == kVK_ANSI_F ? onFill(window) : onRestore(window)
        return handledLast
    }
}

private let keyCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let swallow = Unmanaged<FillKeys>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    return swallow ? nil : Unmanaged.passUnretained(event)
}
