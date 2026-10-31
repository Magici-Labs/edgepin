# EdgePin

Pin a window to an edge of the screen and it gets that strip to itself. Other
windows stay out of it: anything that overlaps gets trimmed on that side, and
resizing the pinned window pushes its neighbours along as you drag.

Unpin it, or close it, and the space is just empty desktop again. Nothing grows
back into it on its own.

```
./install.sh
```

builds `EdgePin.app`, copies it to `~/Applications` and starts it. A pin icon
shows up in the menu bar. The first time, macOS asks for Accessibility access,
which is how it moves other apps' windows: allow it in System Settings → Privacy
& Security → Accessibility, and it picks up from there without a restart.

## Using it

| Shortcut | |
|---|---|
| `⌃⌥ ←` `→` `↑` `↓` | pin the front window to that edge, or unpin it if it is already there |
| `⌃⌥ P` | pin to the nearest edge, or unpin |

The menu bar icon does the same for the window you were last in, lists what is
pinned, and has Unpin All, Edge Line and Start at Login.

Right-click (or ⌃-click) a window's green button for the same choices for that
window: Pin Left, Right, Top, Bottom, and Unpin.

The edge line marks where a strip ends. By default it shows only while
something changes (pinning, resizing the strip, a window being trimmed) and
fades out a second later. Edge Line in the menu switches it to Always or Off.

- One pinned window per edge per screen, so up to four. Left and right strips
  run the full height; top and bottom fit between them.
- Pinning snaps the window flush to the edge and full length. It keeps its
  width, unless it was nearly filling the screen, then it gets a third.
- Drag the inner side to resize the strip. Drag the window itself more than a
  little away from the edge to unpin it.
- Only windows that overlap a strip are touched. A window mostly inside one is
  moved out whole instead of trimmed to a sliver.
- Maximizing a window fills what is left of the screen. ⌥-clicking the green
  button goes there directly, and clicking again puts the window back. Other
  ways of maximizing (double-clicking the title bar, Window → Fill, other
  tools) let macOS fill the whole screen first, and the window is trimmed
  right after.
- A pinned window only holds its strip while it is showing. When it is
  minimized, hidden, on another Space or in full screen, other windows can use
  the space; when it comes back, they are trimmed again.

The app logs to `~/Library/Logs/edgepin.log`.

## Building

```
swift build          # debug build
swift test           # the layout tests
./make-app.sh        # EdgePin.app in this folder
```

macOS remembers the Accessibility permission per code signature, and an ad-hoc
signature changes on every build. `make-app.sh` signs with the first Apple
Development certificate in the keychain so the permission sticks; set
`SIGN_IDENTITY` to use another one.

## Notes and limits

- Windows are fixed up just after they move, since macOS has no way to stop a
  move before it happens, so a window dragged into a strip lands there and
  then gets trimmed when you let go.
- Pins don't survive restarting EdgePin or the pinned app.
- Some apps have a minimum width. Those are moved clear of the strip instead of
  trimmed, and may hang off the other side of the screen.
- Native full screen gets the whole screen, as it lives on its own Space.
- Not for the App Store: sandboxed apps can't move other apps' windows.

## License

MIT. See [LICENSE](LICENSE).
