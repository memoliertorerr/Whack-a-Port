#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: renders the popover to a PNG and exits, so the UI can be checked without clicking the menu bar.
///
///     WHACK_SNAPSHOT=out.png [WHACK_SNAPSHOT_PAGE=settings] [WHACK_SNAPSHOT_DEMO=1] [WHACK_SNAPSHOT_DARK=1] .build/debug/WhackAPort
@MainActor
enum Snapshot {
    static func runIfRequested(store: PortStore, preferences: Preferences) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["WHACK_SNAPSHOT"] else { return }

        _ = NSApplication.shared
        store.loadSynchronously()
        if environment["WHACK_SNAPSHOT_DEMO"] != nil {
            store.injectDemoStates()
        }
        let page: MenuContentView.Page = environment["WHACK_SNAPSHOT_PAGE"] == "settings" ? .settings : .ports
        let root = MenuContentView(initialPage: page)
            .environment(store)
            .environment(preferences)
            .background(Color(nsColor: .windowBackgroundColor))

        let view = NSHostingView(rootView: root)
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 540)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: environment["WHACK_SNAPSHOT_DARK"] != nil ? .darkAqua : .aqua)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: path))) != nil else { exit(1) }
        exit(0)
    }
}
#endif
