import AppKit
import ApplicationServices
import EdgePinCore

final class Pin {
    let window: AXUIElement
    let windowID: CGWindowID?
    let pid: pid_t
    var edge: Edge
    var displayID: CGDirectDisplayID
    var thickness: CGFloat
    /// False while the window is off screen: on another Space, minimized, hidden
    /// or in full screen. Its strip is free for other windows until it is back.
    var active = true
    /// Set while the user drags or resizes it, so it isn't snapped back mid-drag.
    var dragging = false
    /// Our own snap comes back as move and resize events; ignore those.
    var quietUntil = Date.distantPast

    init(window: AXUIElement, edge: Edge, displayID: CGDirectDisplayID, thickness: CGFloat) {
        self.window = window
        self.windowID = window.windowID
        self.pid = window.pid
        self.edge = edge
        self.displayID = displayID
        self.thickness = thickness
    }

    var name: String { Pinner.name(of: window) }
}

/// Keeps track of pinned windows and keeps every other window out of their strips.
///
/// It watches every app through the Accessibility API: new windows, moves and
/// resizes, closes. A window that ends up overlapping a strip is trimmed on the
/// side that overlaps. Nothing ever grows back on its own: unpinning or closing
/// a pinned window just stops the enforcing.
final class Pinner {
    private(set) var pins: [Pin] = []
    var onChange: () -> Void = {}
    var onMessage: (String) -> Void = { _ in }
    /// Something moved against a strip: a pin, a strip resize, a trimmed window.
    var onFlash: () -> Void = {}

    private var observers: [pid_t: AXObserver] = [:]
    private var known = Set<WindowRef>()
    /// Frames from before a ⌥-click zoom, to go back to on the next one.
    private var unzoomed: [WindowRef: CGRect] = [:]
    private var afterMouseUp: [WindowRef: () -> Void] = [:]
    private var mouseTimer: Timer?
    private var reflowDisplays = Set<CGDirectDisplayID>()
    private var reflowScheduled = false

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    func start() {
        let ws = NSWorkspace.shared
        let nc = ws.notificationCenter
        ws.runningApplications.forEach { watch($0) }

        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.watch(app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.forget(app.processIdentifier)
            }
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            // Some apps only become regular apps after launching, so try again here.
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.watch(app) }
            self?.refreshActiveSoon()
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshActiveSoon() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.screensChanged() }
    }

    // MARK: Pinning

    func pin(for window: AXUIElement) -> Pin? {
        pins.first { CFEqual($0.window, window) }
    }

    /// Pins a window to an edge, or unpins it when it is already pinned there.
    /// With no edge, it toggles: unpin if pinned, otherwise pin to the nearest edge.
    func toggle(_ window: AXUIElement, edge: Edge?) {
        if let pin = pin(for: window), edge == nil || edge == pin.edge {
            unpin(pin)
        } else {
            pin(window, to: edge)
        }
    }

    func pin(_ window: AXUIElement, to edge: Edge?) {
        guard window.isStandardWindow else { onMessage("Can't pin this window"); return }
        guard !window.isFullScreen else { onMessage("Leave full screen first"); return }
        guard let f = window.frame, let screen = Self.screen(containing: f) else { return }
        let v = screen.axVisibleFrame
        let e = edge ?? Layout.nearestEdge(of: f, in: v)

        pins.removeAll { CFEqual($0.window, window) || ($0.displayID == screen.displayID && $0.edge == e) }
        let pin = Pin(window: window, edge: e, displayID: screen.displayID,
                      thickness: Layout.initialThickness(of: f, edge: e, in: v))
        pins.append(pin)
        if let observer = observers[pin.pid] { watch(window: window, observer: observer) }
        log("pinned \(pin.name) \(e.rawValue) \(Int(pin.thickness))")
        onMessage("Pinned \(e.rawValue)")
        onFlash()
        reflow(screen.displayID)
    }

    func unpin(_ pin: Pin) {
        pins.removeAll { $0 === pin }
        log("unpinned \(pin.name)")
        onMessage("Unpinned")
        onChange()
    }

    func unpinAll() {
        pins.removeAll()
        onChange()
    }

    /// ⌥-click on the green button: fill what is left of the screen rather than
    /// all of it. Clicking again puts the window back where it was. Returns
    /// false to leave the click to macOS, on screens with nothing pinned.
    func zoom(_ window: AXUIElement) -> Bool {
        guard let f = window.frame, let screen = Self.screen(containing: f) else { return false }
        let layout = layout(for: screen)
        guard !layout.thickness.isEmpty else { return false }
        // A pinned window already has its size; zooming it would take over the screen.
        guard pin(for: window) == nil else { return true }
        let ref = WindowRef(window)
        if f.isClose(to: layout.free, within: 4), let old = unzoomed.removeValue(forKey: ref) {
            window.setFrame(layout.squeeze(old))
        } else {
            unzoomed[ref] = f
            window.setFrame(layout.free)
        }
        return true
    }

    /// Where a pin's strip is right now, for drawing its edge line.
    func strip(of pin: Pin) -> CGRect? {
        screen(pin.displayID).flatMap { layout(for: $0).strip(pin.edge) }
    }

    static func name(of window: AXUIElement) -> String {
        let app = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "Window"
        guard let title = window.title, !title.isEmpty, title != app else { return app }
        return "\(app) — \(title.count > 40 ? title.prefix(39) + "…" : title)"
    }

    // MARK: Watching apps

    private func watch(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }
        let appElement = AXUIElementCreateApplication(pid)
        guard AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon) == .success else {
            // Apps that are still starting up don't answer yet.
            if attempt < 5, !app.isTerminated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.watch(app, attempt: attempt + 1) }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        appElement.windows.forEach { watch(window: $0, observer: observer) }
    }

    private func watch(window: AXUIElement, observer: AXObserver) {
        guard known.insert(WindowRef(window)).inserted else { return }
        for n in [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXUIElementDestroyedNotification,
                  kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, window, n as CFString, refcon)
        }
    }

    private func forget(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        known = known.filter { $0.element.pid != pid }
        let before = pins.count
        pins.removeAll { $0.pid == pid }
        if pins.count != before { onChange() }
    }

    fileprivate func handle(_ note: String, _ element: AXUIElement) {
        switch note {
        case kAXWindowCreatedNotification:
            if let observer = observers[element.pid] { watch(window: element, observer: observer) }
            later(element) { [weak self] in self?.enforce(element) }
            // New windows often place themselves just after appearing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.enforce(element) }
        case kAXUIElementDestroyedNotification:
            known.remove(WindowRef(element))
            unzoomed.removeValue(forKey: WindowRef(element))
            if let pin = pin(for: element) {
                pins.removeAll { $0 === pin }
                log("closed \(pin.pid)")
                onChange()
            }
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            if let pin = pin(for: element) {
                pinMoved(pin)
            } else {
                later(element) { [weak self] in self?.enforce(element) }
            }
        default:
            refreshActiveSoon()
        }
    }

    // MARK: Keeping strips clear

    /// Runs once the mouse button is up, so a window being dragged or resized is
    /// left alone until the user lets go. Also coalesces bursts of events.
    private func later(_ window: AXUIElement, _ action: @escaping () -> Void) {
        afterMouseUp[WindowRef(window)] = action
        guard mouseTimer == nil else { return }
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self, NSEvent.pressedMouseButtons == 0 else { return }
            t.invalidate()
            self.mouseTimer = nil
            let actions = self.afterMouseUp
            self.afterMouseUp = [:]
            actions.values.forEach { $0() }
        }
    }

    private func pinMoved(_ pin: Pin) {
        guard Date() >= pin.quietUntil, pin.active, let f = pin.window.frame, let screen = screen(pin.displayID) else { return }
        let v = screen.axVisibleFrame
        if Layout.offset(of: f, from: pin.edge, in: v) <= 2 {
            // Still against its edge, so it is being resized from the inner side.
            // Make room as it goes rather than when the mouse comes up.
            let t = Layout.clampThickness(Layout.thickness(of: f, edge: pin.edge), edge: pin.edge, in: v)
            if abs(t - pin.thickness) > 0.5 {
                pin.thickness = t
                onFlash()
                reflow(pin.displayID)
            }
        }
        pin.dragging = NSEvent.pressedMouseButtons != 0
        later(pin.window) { [weak self] in self?.settle(pin) }
    }

    /// After the user lets go of a pinned window: dragged well away from its edge
    /// means unpin, anything else snaps it back into its strip.
    private func settle(_ pin: Pin) {
        pin.dragging = false
        guard pins.contains(where: { $0 === pin }), pin.active,
              let f = pin.window.frame, let screen = screen(pin.displayID) else { return }
        if Layout.offset(of: f, from: pin.edge, in: screen.axVisibleFrame) > 40 {
            unpin(pin)
            return
        }
        reflow(pin.displayID)
    }

    /// Re-snaps the pins on a display, then trims every window that overlaps a
    /// strip. Throttled, since it runs on every step of a live resize.
    private func reflow(_ display: CGDirectDisplayID) {
        reflowDisplays.insert(display)
        guard !reflowScheduled else { return }
        reflowScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self] in
            guard let self else { return }
            self.reflowScheduled = false
            let displays = self.reflowDisplays
            self.reflowDisplays = []
            for edge in Edge.allCases {
                for pin in self.pins where pin.edge == edge && displays.contains(pin.displayID) { self.snap(pin) }
            }
            // Only windows showing now: one on another Space shares the screen
            // but not the pinned window, so its strip doesn't apply there.
            let onScreen = Self.onScreenWindowIDs()
            for ref in self.known where ref.element.windowID.map(onScreen.contains) ?? true {
                self.enforce(ref.element)
            }
            self.onChange()
        }
    }

    private func snap(_ pin: Pin) {
        guard pin.active, !pin.dragging, let screen = screen(pin.displayID),
              let target = layout(for: screen).strip(pin.edge),
              let f = pin.window.frame, !f.isClose(to: target) else { return }
        pin.quietUntil = Date().addingTimeInterval(0.3)
        pin.window.setFrame(target)
        // An app with a minimum size may not shrink all the way. Keep what it
        // allowed and push it back against the edge.
        if let got = pin.window.frame, !got.isClose(to: target) {
            pin.thickness = Layout.thickness(of: got, edge: pin.edge)
            if let fixed = layout(for: screen).strip(pin.edge) { pin.window.setPosition(fixed.origin) }
        }
    }

    private func enforce(_ window: AXUIElement) {
        guard pin(for: window) == nil, var f = window.frame else { return }
        for screen in NSScreen.screens {
            let layout = layout(for: screen)
            guard layout.overlaps(f) else { continue }
            guard window.isStandardWindow, !window.isMinimized, !window.isFullScreen else { return }
            onFlash()
            window.setFrame(layout.squeeze(f))
            // Apps with a minimum size refuse to shrink past it; move those clear instead.
            if let got = window.frame, layout.overlaps(got) {
                window.setPosition(layout.squeeze(got, shiftOnly: true).origin)
            }
            f = window.frame ?? f
        }
    }

    // MARK: Pins coming and going from view

    private func refreshActiveSoon() {
        refreshActive()
        // Space switches and un-minimizing animate; look again once they finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshActive() }
    }

    private func refreshActive() {
        guard !pins.isEmpty else { return }
        let onScreen = Self.onScreenWindowIDs()
        var changed = false
        for pin in pins {
            let now = pin.windowID.map { onScreen.contains($0) } ?? !pin.window.isMinimized
            guard now != pin.active else { continue }
            pin.active = now
            changed = true
            if now { reflow(pin.displayID) }
        }
        if changed { onChange() }
    }

    private func screensChanged() {
        let ids = Set(NSScreen.screens.map(\.displayID))
        pins.removeAll { !ids.contains($0.displayID) }
        ids.forEach { reflow($0) }
        onChange()
    }

    // MARK: Screens

    private func screen(_ id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }

    private func layout(for screen: NSScreen) -> Layout {
        var thickness: [Edge: CGFloat] = [:]
        for pin in pins where pin.active && pin.displayID == screen.displayID { thickness[pin.edge] = pin.thickness }
        return Layout(visible: screen.axVisibleFrame, thickness: thickness)
    }

    static func screen(containing f: CGRect) -> NSScreen? {
        func area(_ s: NSScreen) -> CGFloat {
            let i = s.axFrame.intersection(f)
            return i.isNull ? 0 : i.width * i.height
        }
        return NSScreen.screens.max { area($0) < area($1) }
    }

    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }
}

private let axCallback: AXObserverCallback = { _, element, note, refcon in
    guard let refcon else { return }
    Unmanaged<Pinner>.fromOpaque(refcon).takeUnretainedValue().handle(note as String, element)
}
