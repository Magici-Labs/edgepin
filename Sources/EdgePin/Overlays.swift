import AppKit
import EdgePinCore

/// A short message in the lower middle of the screen, like the volume display.
final class HUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hide: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        effect.addSubview(label)
        panel.contentView = effect
    }

    func show(_ text: String) {
        label.stringValue = text
        let size = label.fittingSize
        label.frame = NSRect(x: 24, y: 14, width: size.width, height: size.height)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w = size.width + 48, h = size.height + 28
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.minY + screen.frame.height * 0.18,
                              width: w, height: h), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hide?.cancel()
        let work = DispatchWorkItem { [panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }
}

/// A thin accent-coloured line along the inner side of each pinned window,
/// showing where its strip ends. By default it only shows while something
/// changes (pinning, resizing the strip, a window being trimmed) and fades
/// out a second later.
final class EdgeLines {
    enum Mode: String, CaseIterable {
        case changing, always, off

        var title: String {
            switch self {
            case .changing: return "When Changing"
            case .always: return "Always"
            case .off: return "Off"
            }
        }
    }

    private var windows: [NSWindow] = []
    private var strips: [(CGRect, Edge)] = []
    private var showing = false
    /// Bumped by every flash, so an older fade-out doesn't hide a newer flash.
    private var generation = 0
    private static let key = "edgeLine"

    var mode: Mode {
        get { UserDefaults.standard.string(forKey: Self.key).flatMap(Mode.init) ?? .changing }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.key); render() }
    }

    /// Moves the lines to where the strips are now, without showing them.
    /// Strips are each showing pin's strip and edge, in Accessibility coordinates.
    func update(_ strips: [(CGRect, Edge)]) {
        self.strips = strips
        render()
    }

    /// Shows the lines for a moment, then fades them out.
    func flash(_ strips: [(CGRect, Edge)]) {
        self.strips = strips
        guard mode == .changing else { render(); return }
        showing = true
        render()

        generation += 1
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, gen == self.generation else { return }
            let shown = self.windows.filter(\.isVisible)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                shown.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { [weak self] in
                // A flash that came in during the fade wins.
                guard let self, gen == self.generation else { return }
                self.showing = false
                self.render()
            })
        }
    }

    private func render() {
        let visible = mode == .always || (mode == .changing && showing)
        let lines = visible ? strips.map { Self.line($0.0, $0.1) } : []
        while windows.count < lines.count { windows.append(Self.makeWindow()) }
        for (i, window) in windows.enumerated() {
            if i < lines.count {
                window.alphaValue = 1
                window.setFrame(flipped(lines[i]), display: true)
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }
    }

    private static func line(_ s: CGRect, _ edge: Edge) -> CGRect {
        let w: CGFloat = 4
        switch edge {
        case .left: return CGRect(x: s.maxX - w / 2, y: s.minY, width: w, height: s.height)
        case .right: return CGRect(x: s.minX - w / 2, y: s.minY, width: w, height: s.height)
        case .top: return CGRect(x: s.minX, y: s.maxY - w / 2, width: s.width, height: w)
        case .bottom: return CGRect(x: s.minX, y: s.minY - w / 2, width: s.width, height: w)
        }
    }

    private static func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.hasShadow = false
        w.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85)
        w.ignoresMouseEvents = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return w
    }
}
