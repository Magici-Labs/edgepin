import AppKit
import ApplicationServices

/// Catches clicks on a window's green button and title bar before the app sees them.
///
/// ⌥-click on the green button, or a double-click on the title bar: left to
/// macOS, the window animates out to the whole screen and only then gets
/// trimmed out of the strip; caught here, it goes straight to the free area.
/// Right-click (or ⌃-click) on the green button, which macOS does nothing
/// with, opens the pin menu for that window.
final class GreenButton {
    /// Return true when the click was handled, false to pass it on to macOS.
    var onZoom: (AXUIElement) -> Bool = { _ in false }
    /// The window and where the click was, in AppKit screen coordinates.
    var onMenu: (AXUIElement, NSPoint) -> Void = { _, _ in }

    private var tap: CFMachPort?
    /// The button-up of a click we swallowed, so the app doesn't see half a click.
    private var swallowUp: CGEventType?

    func start() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log("couldn't watch clicks on the green button")
            return
        }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseUp, .rightMouseUp:
            guard swallowUp == type else { return false }
            swallowUp = nil
            return true
        case .rightMouseDown:
            return openMenu(event, up: .rightMouseUp)
        case .leftMouseDown where event.flags.contains(.maskControl):
            return openMenu(event, up: .leftMouseUp)
        case .leftMouseDown where event.flags.contains(.maskAlternate):
            guard let window = Self.window(atGreenButton: event.location), onZoom(window) else { return false }
            swallowUp = .leftMouseUp
            return true
        case .leftMouseDown where event.getIntegerValueField(.mouseEventClickState) == 2:
            // A title bar double-click zooms the same way as ⌥-click, unless the
            // user set it to minimize or do nothing.
            guard Self.doubleClickZooms, let window = Self.window(atTitleBar: event.location),
                  onZoom(window) else { return false }
            swallowUp = .leftMouseUp
            return true
        default:
            return false
        }
    }

    private func openMenu(_ event: CGEvent, up: CGEventType) -> Bool {
        guard let window = Self.window(atGreenButton: event.location) else { return false }
        swallowUp = up
        let p = flipped(CGRect(origin: event.location, size: .zero)).origin
        // The menu runs its own event loop; open it after this callback
        // returns, or the system disables the tap for being too slow.
        DispatchQueue.main.async { [weak self] in self?.onMenu(window, p) }
        return true
    }

    /// System Settings → Desktop & Dock → "Double-click a window's title bar to".
    /// Unset means the default, which zooms.
    private static var doubleClickZooms: Bool {
        let d = UserDefaults.standard
        if let action = d.string(forKey: "AppleActionOnDoubleClick") {
            return action != "Minimize" && action != "None"
        }
        return !d.bool(forKey: "AppleMiniaturizeOnDoubleClick")
    }

    /// The window whose title bar is at this point. Only plain title bars and
    /// toolbars count: apps that draw their own (Chrome, VS Code) report tabs
    /// and buttons there, and those are left to the app.
    private static func window(atTitleBar p: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              let element = hit else { return nil }
        let window: AXUIElement
        switch element.role {
        case kAXWindowRole:
            // The window itself answers for any spot with nothing on it, so make
            // sure the click is in the title bar strip and not the content.
            guard let f = element.frame, p.y - f.minY < 32 else { return nil }
            window = element
        case kAXToolbarRole:
            guard let w = element.window else { return nil }
            window = w
        default:
            return nil
        }
        return window.isStandardWindow ? window : nil
    }

    /// The window whose green button is at this point, if there is one. Event
    /// locations are already in the same top-left coordinates as AX.
    private static func window(atGreenButton p: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              let button = hit,
              let subrole = button.value(kAXSubroleAttribute) as? String,
              subrole == kAXFullScreenButtonSubrole || subrole == kAXZoomButtonSubrole,
              let w = button.value(kAXWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let swallow = Unmanaged<GreenButton>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    return swallow ? nil : Unmanaged.passUnretained(event)
}
