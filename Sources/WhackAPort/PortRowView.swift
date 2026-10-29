import SwiftUI
import WhackKit

struct PortRowView: View {
    @Environment(PortStore.self) private var store
    @Environment(Preferences.self) private var preferences
    let entry: PortEntry
    @State private var hovering = false

    private var killState: KillState? { store.killStates[entry.pid] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                ProcessIcon(entry: entry)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    titleLine
                    Text(verbatim: entry.displayCommand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(entry.commandLine)
                    if let directory = entry.details.workingDirectory, directory != "/" {
                        folderButton(directory)
                    }
                    Text(verbatim: metadata)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                actions
            }
            if let killState {
                KillStateBanner(entry: entry, state: killState)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { PortActionsMenu(entry: entry) }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: ":\(entry.port)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text(verbatim: entry.processName)
                .fontWeight(.medium)
                .lineLimit(1)
            if entry.proto == .udp {
                Badge(text: "UDP", color: .blue)
            }
            if entry.isExposed {
                Badge(text: "LAN", color: .orange)
                    .help("Listening on all interfaces: reachable from other devices on your network")
            }
        }
    }

    private func folderButton(_ directory: String) -> some View {
        let opener = FolderOpener.with(id: preferences.folderOpenerID)
        return Button {
            opener.open(directory)
        } label: {
            Label {
                Text(verbatim: (directory as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.head)
            } icon: {
                Image(systemName: "folder")
            }
        }
        .buttonStyle(.link)
        .font(.caption)
        .help("Open \(directory) in \(opener.name)")
    }

    private var metadata: String {
        var parts = ["PID \(entry.pid)", entry.user]
        if !entry.isExposed {
            parts.append(entry.hosts.joined(separator: ", "))
        }
        if let start = entry.details.startDate {
            parts.append("up \(Self.uptime(since: start))")
        }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button("Kill") { store.kill(entry, force: false) }
                .help("Ask it to quit (SIGTERM)")
            Button("Force") { store.kill(entry, force: true) }
                .tint(.red)
                .help("Kill immediately (SIGKILL)")
            Menu {
                PortActionsMenu(entry: entry)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(killState?.isWorking == true)
    }

    static func uptime(since start: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        default: return "\(seconds / 86_400)d \(seconds % 86_400 / 3600)h"
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
    }
}

private struct ProcessIcon: View {
    let entry: PortEntry

    var body: some View {
        if let path = entry.appBundlePath ?? entry.details.executablePath {
            Image(nsImage: IconCache.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "questionmark.app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .help("Owned by another user: details need admin rights")
        }
    }
}

/// Shared by the ⋯ button and the right-click menu.
struct PortActionsMenu: View {
    @Environment(PortStore.self) private var store
    @Environment(Preferences.self) private var preferences
    let entry: PortEntry

    var body: some View {
        let opener = FolderOpener.with(id: preferences.folderOpenerID)
        if let directory = entry.details.workingDirectory {
            Button("Open Working Directory in \(opener.name)") { opener.open(directory) }
            if opener != .finder {
                Button("Show Working Directory in Finder") { FolderOpener.finder.open(directory) }
            }
        }
        if let executable = entry.details.executablePath {
            Button("Reveal Executable in Finder") { SystemActions.reveal(entry.appBundlePath ?? executable) }
        }
        if entry.proto == .tcp {
            Button("Open http://localhost:\(String(entry.port))") { SystemActions.openInBrowser(port: entry.port) }
        }
        Divider()
        Button("Copy PID") { SystemActions.copy(String(entry.pid)) }
        Button("Copy Command") { SystemActions.copy(entry.commandLine) }
        if let directory = entry.details.workingDirectory {
            Button("Copy Working Directory") { SystemActions.copy(directory) }
        }
        Divider()
        Button("Kill as Administrator…") { store.killAsAdmin(entry, force: false) }
        Button("Hide “\(entry.processName)”") { store.hide(entry) }
    }
}

private struct KillStateBanner: View {
    @Environment(PortStore.self) private var store
    let entry: PortEntry
    let state: KillState

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .font(.caption)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var tint: Color {
        switch state {
        case .working: .secondary
        case .confirmForce, .stuck: .orange
        case .permissionDenied, .failed: .red
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .working(let force):
            ProgressView().controlSize(.mini)
            Text(force ? "Force killing…" : "Waiting for it to exit…")
        case .confirmForce:
            Text("Force kill? Unsaved work is lost.")
            Spacer()
            Button("Cancel") { store.dismissState(for: entry) }
            Button("Force Kill") { store.kill(entry, force: true, confirmed: true) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        case .stuck(let seconds):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(verbatim: "Still running after \(seconds)s")
            Spacer()
            Button("Force Kill") { store.kill(entry, force: true, confirmed: true) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            dismissButton
        case .permissionDenied:
            Image(systemName: "lock.fill").foregroundStyle(.red)
            Text(verbatim: "Permission denied (owned by \(entry.user))")
            Spacer()
            Button("Kill as Admin…") { store.killAsAdmin(entry, force: false) }
            dismissButton
        case .failed(let message):
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            Text(verbatim: message)
                .lineLimit(2)
            Spacer()
            dismissButton
        }
    }

    private var dismissButton: some View {
        Button {
            store.dismissState(for: entry)
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("Dismiss")
    }
}
