import AppKit

/// An app that can open a folder: Finder, a terminal, or an editor.
struct FolderOpener: Identifiable, Hashable {
    let id: String // bundle identifier
    let name: String

    static let finder = FolderOpener(id: "com.apple.finder", name: "Finder")

    private static let candidates: [FolderOpener] = [
        finder,
        FolderOpener(id: "com.apple.Terminal", name: "Terminal"),
        FolderOpener(id: "com.googlecode.iterm2", name: "iTerm"),
        FolderOpener(id: "com.mitchellh.ghostty", name: "Ghostty"),
        FolderOpener(id: "dev.warp.Warp-Stable", name: "Warp"),
        FolderOpener(id: "com.microsoft.VSCode", name: "VS Code"),
        FolderOpener(id: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        FolderOpener(id: "dev.zed.Zed", name: "Zed"),
    ]

    @MainActor
    static var installed: [FolderOpener] {
        candidates.filter { $0 == finder || NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    @MainActor
    static func with(id: String) -> FolderOpener {
        installed.first { $0.id == id } ?? finder
    }

    @MainActor
    func open(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard self != .finder, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

@MainActor
enum SystemActions {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openInBrowser(port: Int) {
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(forFile path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}
