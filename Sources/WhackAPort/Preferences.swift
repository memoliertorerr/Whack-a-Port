import Foundation
import Observation

/// User settings, persisted to UserDefaults on every change.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let showCountInMenuBar = "showCountInMenuBar"
        static let includeUDP = "includeUDP"
        static let hideSystemProcesses = "hideSystemProcesses"
        static let graceSeconds = "graceSeconds"
        static let autoForceKill = "autoForceKill"
        static let confirmForceKill = "confirmForceKill"
        static let folderOpenerID = "folderOpenerID"
        static let hiddenProcesses = "hiddenProcesses"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) } }
    var showCountInMenuBar: Bool { didSet { defaults.set(showCountInMenuBar, forKey: Key.showCountInMenuBar) } }
    var includeUDP: Bool { didSet { defaults.set(includeUDP, forKey: Key.includeUDP) } }
    var hideSystemProcesses: Bool { didSet { defaults.set(hideSystemProcesses, forKey: Key.hideSystemProcesses) } }
    /// How long a SIGTERM gets before we report that it failed.
    var graceSeconds: Int { didSet { defaults.set(graceSeconds, forKey: Key.graceSeconds) } }
    var autoForceKill: Bool { didSet { defaults.set(autoForceKill, forKey: Key.autoForceKill) } }
    var confirmForceKill: Bool { didSet { defaults.set(confirmForceKill, forKey: Key.confirmForceKill) } }
    var folderOpenerID: String { didSet { defaults.set(folderOpenerID, forKey: Key.folderOpenerID) } }
    /// Process names the user chose to hide from the list.
    var hiddenProcesses: [String] { didSet { defaults.set(hiddenProcesses, forKey: Key.hiddenProcesses) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.refreshInterval: 5.0,
            Key.showCountInMenuBar: true,
            Key.includeUDP: false,
            Key.hideSystemProcesses: true,
            Key.graceSeconds: 3,
            Key.autoForceKill: false,
            Key.confirmForceKill: false,
            Key.folderOpenerID: FolderOpener.finder.id,
            Key.hiddenProcesses: [String](),
        ])
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
        showCountInMenuBar = defaults.bool(forKey: Key.showCountInMenuBar)
        includeUDP = defaults.bool(forKey: Key.includeUDP)
        hideSystemProcesses = defaults.bool(forKey: Key.hideSystemProcesses)
        graceSeconds = defaults.integer(forKey: Key.graceSeconds)
        autoForceKill = defaults.bool(forKey: Key.autoForceKill)
        confirmForceKill = defaults.bool(forKey: Key.confirmForceKill)
        folderOpenerID = defaults.string(forKey: Key.folderOpenerID) ?? FolderOpener.finder.id
        hiddenProcesses = defaults.stringArray(forKey: Key.hiddenProcesses) ?? []
    }
}
