import SwiftUI
import WhackKit

@main
struct WhackAPortApp: App {
    @State private var preferences: Preferences
    @State private var store: PortStore

    init() {
        let preferences = Preferences()
        let store = PortStore(preferences: preferences)
        _preferences = State(initialValue: preferences)
        _store = State(initialValue: store)
        #if DEBUG
        Snapshot.runIfRequested(store: store, preferences: preferences)
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(store)
                .environment(preferences)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "hammer.fill")
                if preferences.showCountInMenuBar {
                    Text(verbatim: "\(store.menuBarCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContentView: View {
    enum Page { case ports, settings }

    @Environment(PortStore.self) private var store
    @State private var page: Page

    init(initialPage: Page = .ports) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        Group {
            switch page {
            case .ports: PortListView(openSettings: { page = .settings })
            case .settings: SettingsView(close: { page = .ports })
            }
        }
        .frame(width: 440, height: 540)
        // The popover is our only window, so it becoming key means the user just opened it.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.refresh()
        }
        .onChange(of: page) { store.refresh() }
    }
}
