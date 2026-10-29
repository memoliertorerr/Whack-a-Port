import SwiftUI
import WhackKit

struct PortListView: View {
    @Environment(PortStore.self) private var store
    let openSettings: () -> Void

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.orange)
                Text("Whack-a-Port")
                    .font(.headline)
                Spacer()
                Button(action: store.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh (⌘R)")
                .keyboardShortcut("r")
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
                .keyboardShortcut(",")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            TextField("Filter by port, process or folder", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Divider()

            let entries = store.visibleEntries
            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            PortRowView(entry: entry)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }

            Divider()
            footer
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(store.searchText.isEmpty ? "No listening ports" : "No matches", systemImage: "powerplug")
        } description: {
            if store.searchText.isEmpty {
                Text("Nothing is listening right now.")
            } else {
                Text(verbatim: "Nothing matches “\(store.searchText)”.")
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        @Bindable var store = store
        return HStack(spacing: 10) {
            if let error = store.scanError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
            } else {
                let count = store.visibleEntries.count
                Text(verbatim: count == 1 ? "1 port" : "\(count) ports")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.hiddenCount > 0 {
                Toggle(isOn: $store.showHidden) {
                    Text(verbatim: "Show \(store.hiddenCount) hidden")
                }
                .toggleStyle(.checkbox)
                .help("System processes and processes you hid")
            }
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .font(.caption)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
