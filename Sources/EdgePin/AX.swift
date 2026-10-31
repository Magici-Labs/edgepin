import AppKit
import ApplicationServices

// Thin wrappers over the Accessibility API, which is how EdgePin reads and moves
// other apps' windows.
extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &v) == .success ? v : nil
    }

    private func element(_ attribute: String) -> AXUIElement? {
        guard let v = value(attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private func axValue(_ attribute: String) -> AXValue? {
        guard let v = value(attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }

    var title: String? { value(kAXTitleAttribute) as? String }
    var windows: [AXUIElement] { value(kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    var focusedWindow: AXUIElement? { element(kAXFocusedWindowAttribute) }
    /// The window a button, toolbar or other element belongs to.
    var window: AXUIElement? { element(kAXWindowAttribute) }
    var role: String? { value(kAXRoleAttribute) as? String }
    var mainWindow: AXUIElement? { element(kAXMainWindowAttribute) }
    var isMinimized: Bool { value(kAXMinimizedAttribute) as? Bool ?? false }
    var isFullScreen: Bool { value("AXFullScreen") as? Bool ?? false }

    /// Real document windows, not sheets, panels, popovers or tooltips.
    var isStandardWindow: Bool {
        value(kAXRoleAttribute) as? String == kAXWindowRole
            && value(kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
    }

    var frame: CGRect? {
        var p = CGPoint.zero, s = CGSize.zero
        guard let pv = axValue(kAXPositionAttribute), AXValueGetValue(pv, .cgPoint, &p),
              let sv = axValue(kAXSizeAttribute), AXValueGetValue(sv, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, v)
        }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, v)
        }
    }

    /// Size, position, then size again: macOS clips a resize at the screen edge,
    /// so the first one can come up short when the window hasn't moved yet.
    func setFrame(_ r: CGRect) {
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)
    }

    /// The window server's number for this window, to look it up in the on-screen
    /// window list. There is no public call for this; Rectangle, yabai and AltTab
    /// all use this one.
    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success ? id : nil
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// AXUIElement as a dictionary key. Two elements for the same window are
/// different objects, so they compare with CFEqual.
struct WindowRef: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (a: WindowRef, b: WindowRef) -> Bool { CFEqual(a.element, b.element) }
    func hash(into h: inout Hasher) { h.combine(CFHash(element)) }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    var axFrame: CGRect { flipped(frame) }
    var axVisibleFrame: CGRect { flipped(visibleFrame) }
}

/// AppKit puts the origin at the bottom-left of the main display with y growing
/// up; the Accessibility API puts it at the top-left with y growing down. The
/// conversion is its own inverse, so it goes both ways.
func flipped(_ r: CGRect) -> CGRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}
