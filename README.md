# Whack-a-Port

Find what's listening on a port and kill it. Comes as a macOS menu bar app and a terminal command.

## Menu bar app

Click the hammer in the menu bar to see every listening port with:

- the process name and icon, its command line, PID, user, bound address and uptime
- a **LAN** badge when the port is reachable from other machines (not just localhost)
- the process's **working directory**: click it to open it in Finder, Terminal, VS Code, Zed, etc.
- **Kill** (SIGTERM) and **Force** (SIGKILL) buttons

If a normal kill doesn't work within the grace period (3s by default), the row beeps and shows **Force Kill**.
Processes owned by another user show **Kill as Admin…**, which asks for your password.

The `⋯` button (or a right-click on a row) has more actions: reveal the executable in Finder, open
`http://localhost:<port>`, copy the PID, command or directory, kill as administrator, or hide that process.

Type in the filter box to match on port, process name, command line or folder. Shortcuts while the popover is open:
⌘R refreshes, ⌘, opens settings, ⌘Q quits.

### Settings

| Setting | Default |
| --- | --- |
| Launch at login | off |
| Show port count in menu bar | on |
| Refresh every | 5 seconds |
| Include UDP ports | off |
| Hide macOS system processes (ControlCenter, rapportd, …) | on |
| Grace period for a normal kill before warning | 3s |
| Force kill automatically if a normal kill fails | off |
| Confirm before force killing | off |
| Open working directories in | Finder |
| Hidden processes | none (hide from a row's `⋯` menu) |

### Build and install

Requires macOS 14+ and Xcode (Swift 6).

```bash
scripts/build-app.sh --install
```

This builds `build/Whack-a-Port.app`, copies it to `/Applications` and launches it. Without `--install` it only builds.
The app is ad-hoc signed, which is fine for running it on your own Mac.

## Terminal command

`whack.sh` asks for a port (or takes it as an argument) and sends SIGTERM to whatever is listening on it. If the process
is still alive after 3 seconds, it beeps and offers `kill -9`.

```bash
./whack.sh 3000
```

To run it as `whackaport` from anywhere, symlink it onto your `PATH`:

```bash
ln -s "$PWD/whack.sh" ~/.local/bin/whackaport
```

## Development

```bash
swift build          # debug build
swift test           # unit tests plus end-to-end kill tests (needs python3)
```

Layout:

- `Sources/WhackKit/`: everything without UI. `PortScanner` runs `lsof`, `LsofParser` parses and groups its output,
  `ProcessInspector` reads path, working directory, argv and start time from the kernel (libproc/sysctl), and
  `ProcessKiller` sends signals and waits for the process to exit.
- `Sources/WhackAPort/`: the SwiftUI `MenuBarExtra` app. `PortStore` owns the list, the refresh loop and kill state;
  `Preferences` persists settings to UserDefaults.
- `Resources/Info.plist` and `scripts/build-app.sh` turn the SwiftPM binary into an `.app` bundle (`LSUIElement`, so
  there's no Dock icon).

Debug builds can render the popover to a PNG without clicking the menu bar, which is handy for checking layout:

```bash
WHACK_SNAPSHOT=out.png .build/debug/WhackAPort
WHACK_SNAPSHOT=out.png WHACK_SNAPSHOT_PAGE=settings .build/debug/WhackAPort
WHACK_SNAPSHOT=out.png WHACK_SNAPSHOT_DEMO=1 WHACK_SNAPSHOT_DARK=1 .build/debug/WhackAPort   # every banner, dark mode
```

### Limits

- Without root, `lsof` can only see your own processes, so ports held by root daemons don't appear in the list.
- The "system process" filter is a path heuristic (`/System`, `/usr/libexec`, `/usr/sbin`, …).
