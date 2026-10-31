import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon, not in the app switcher.
app.setActivationPolicy(.accessory)
app.run()
