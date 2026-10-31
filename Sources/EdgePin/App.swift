import AppKit
import Carbon
import EdgePinCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let pinner = Pinner()
    private let hud = HUD()
    private let lines = EdgeLines()
    private var hotkeys: Hotkeys?
    private let greenButton = GreenButton()
    private var statusItem: NSStatusItem!
    /// The app the user was in before clicking the menu bar icon.
    private var lastApp: NSRunningApplication?
    private var menuTarget: AXUIElement?
    private var started = false

    private static let shortcuts: [(Edge, Int, Int)] = [
        (.left, kVK_LeftArrow, NSLeftArrowFunctionKey),
        (.right, kVK_RightArrow, NSRightArrowFunctionKey),
        (.top, kVK_UpArrow, NSUpArrowFunctionKey),
        (.bottom, kVK_DownArrow, NSDownArrowFunctionKey),
    ]
    private static let modifiers = controlKey | optionKey
    private static let menuModifiers: NSEvent.ModifierFlags = [.control, .option]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        pinner.onChange = { [weak self] in self?.pinsChanged() }
        pinner.onMessage = { [weak self] in self?.hud.show($0) }
        pinner.onFlash = { [weak self] in
            guard let self else { return }
            self.lines.flash(self.showingStrips())
        }

        lastApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != getpid() { self?.lastApp = app }
        }

        let hk = Hotkeys()
        for (edge, key, _) in Self.shortcuts {
            hk.register(key, Self.modifiers) { [weak self] in self?.pinFocused(edge) }
        }
        hk.register(kVK_ANSI_P, Self.modifiers) { [weak self] in self?.pinFocused(nil) }
        hotkeys = hk

        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            start()
        } else {
            // Granting access in System Settings takes effect without a restart.
            log("waiting for Accessibility access")
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard AXIsProcessTrusted() else { return }
                t.invalidate()
                self?.start()
            }
        }
    }

    private func start() {
        started = true
        pinner.start()
        greenButton.onZoom = { [weak self] in self?.pinner.zoom($0) ?? false }
        greenButton.onMenu = { [weak self] in self?.showWindowMenu($0, at: $1) }
        greenButton.start()
        log("started")
    }

    private func targetWindow() -> AXUIElement? {
        var app = NSWorkspace.shared.frontmostApplication
        if app?.processIdentifier == getpid() { app = lastApp }
        guard let app else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return element.focusedWindow ?? element.mainWindow
    }

    private func pinFocused(_ edge: Edge?) {
        guard started else { hud.show("EdgePin needs Accessibility access"); return }
        guard let window = targetWindow() else { hud.show("No window to pin"); return }
        pinner.toggle(window, edge: edge)
    }

    private func pinsChanged() {
        updateIcon()
        lines.update(showingStrips())
    }

    private func showingStrips() -> [(CGRect, Edge)] {
        pinner.pins.filter(\.active).compactMap { pin in pinner.strip(of: pin).map { ($0, pin.edge) } }
    }

    private func updateIcon() {
        let image = NSImage(systemSymbolName: pinner.pins.contains(where: \.active) ? "pin.fill" : "pin",
                            accessibilityDescription: "EdgePin")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard started else {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibility)))
            menu.addItem(.separator())
            menu.addItem(item("Quit EdgePin", #selector(quit), key: "q"))
            return
        }

        menuTarget = targetWindow()
        if let window = menuTarget {
            let name = Pinner.name(of: window)
            let current = pinner.pin(for: window)
            if current != nil {
                menu.addItem(item("Unpin \(name)", #selector(unpinTarget), key: "p", modifiers: Self.menuModifiers))
            }
            let sub = NSMenu()
            edgeItems(current: current?.edge).forEach { sub.addItem($0) }
            let pinItem = NSMenuItem(title: current == nil ? "Pin \(name)" : "Move \(name) to", action: nil, keyEquivalent: "")
            pinItem.submenu = sub
            menu.addItem(pinItem)
        } else {
            menu.addItem(NSMenuItem(title: "No window to pin", action: nil, keyEquivalent: ""))
        }

        if !pinner.pins.isEmpty {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Pinned", action: nil, keyEquivalent: ""))
            let screens = NSScreen.screens
            for pin in pinner.pins {
                var title = "\(pin.name) · \(pin.edge.title)"
                if screens.count > 1, let s = screens.first(where: { $0.displayID == pin.displayID }) {
                    title += " · \(s.localizedName)"
                }
                if !pin.active { title += " (not showing)" }
                let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                i.indentationLevel = 1
                let sub = NSMenu()
                let unpin = item("Unpin", #selector(unpinItem(_:)))
                unpin.representedObject = pin
                sub.addItem(unpin)
                i.submenu = sub
                menu.addItem(i)
            }
            menu.addItem(item("Unpin All", #selector(unpinAll)))
        }

        menu.addItem(.separator())
        let lineMenu = NSMenu()
        for mode in EdgeLines.Mode.allCases {
            let i = item(mode.title, #selector(setLineMode(_:)))
            i.representedObject = mode.rawValue
            i.state = lines.mode == mode ? .on : .off
            lineMenu.addItem(i)
        }
        let line = NSMenuItem(title: "Edge Line", action: nil, keyEquivalent: "")
        line.submenu = lineMenu
        menu.addItem(line)
        let login = item("Start at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit EdgePin", #selector(quit), key: "q"))
    }

    /// Left, Right, Top, Bottom, with their shortcuts, acting on menuTarget.
    private func edgeItems(current: Edge?, prefix: String = "") -> [NSMenuItem] {
        Self.shortcuts.map { edge, _, arrow in
            let i = item(prefix + edge.title, #selector(pinTarget(_:)),
                         key: String(Character(UnicodeScalar(UInt16(arrow))!)), modifiers: Self.menuModifiers)
            i.representedObject = edge.rawValue
            i.state = current == edge ? .on : .off
            return i
        }
    }

    /// The menu from right-clicking a window's green button.
    private func showWindowMenu(_ window: AXUIElement, at point: NSPoint) {
        menuTarget = window
        let current = pinner.pin(for: window)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: Pinner.name(of: window), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        edgeItems(current: current?.edge, prefix: "Pin ").forEach { menu.addItem($0) }
        if current != nil {
            menu.addItem(.separator())
            menu.addItem(item("Unpin", #selector(unpinTarget), key: "p", modifiers: Self.menuModifiers))
        }
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = modifiers
        i.target = self
        return i
    }

    @objc private func pinTarget(_ sender: NSMenuItem) {
        guard let window = menuTarget, let raw = sender.representedObject as? String, let edge = Edge(rawValue: raw) else { return }
        pinner.pin(window, to: edge)
    }

    @objc private func unpinTarget() {
        if let window = menuTarget, let pin = pinner.pin(for: window) { pinner.unpin(pin) }
    }

    @objc private func unpinItem(_ sender: NSMenuItem) {
        if let pin = sender.representedObject as? Pin { pinner.unpin(pin) }
    }

    @objc private func unpinAll() { pinner.unpinAll() }

    @objc private func setLineMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = EdgeLines.Mode(rawValue: raw) else { return }
        lines.mode = mode
        lines.flash(showingStrips())
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log("login item: \(error)")
            hud.show("Couldn't change the login item")
        }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
