import AppKit
import Observation
import WhackKit

enum KillState: Equatable {
    case working(force: Bool)
    case confirmForce
    /// SIGTERM was delivered but the process outlived the grace period.
    case stuck(afterSeconds: Int)
    case permissionDenied
    case failed(String)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

/// Owns the port list, the periodic rescan and every kill in flight.
@MainActor
@Observable
final class PortStore {
    private(set) var entries: [PortEntry] = []
    private(set) var scanError: String?
    private(set) var isScanning = false
    /// Keyed by PID: one process can hold several ports, and killing it frees all of them.
    private(set) var killStates: [Int32: KillState] = [:]
    var searchText = ""
    var showHidden = false

    let preferences: Preferences
    @ObservationIgnored private var rescanQueued = false
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?

    init(preferences: Preferences) {
        self.preferences = preferences
        refresh()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.preferences.refreshInterval ?? 5))
                self?.refresh()
            }
        }
    }

    // MARK: Filtering

    func isHidden(_ entry: PortEntry) -> Bool {
        (preferences.hideSystemProcesses && entry.isSystemProcess) || preferences.hiddenProcesses.contains(entry.processName)
    }

    var hiddenCount: Int { entries.filter(isHidden).count }

    var menuBarCount: Int { entries.count - hiddenCount }

    var visibleEntries: [PortEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            guard showHidden || !isHidden(entry) else { return false }
            guard !query.isEmpty else { return true }
            return String(entry.port).contains(query)
                || entry.processName.lowercased().contains(query)
                || entry.commandLine.lowercased().contains(query)
                || (entry.details.workingDirectory?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: Scanning

    func refresh() {
        guard !isScanning else {
            rescanQueued = true
            return
        }
        isScanning = true
        let includeUDP = preferences.includeUDP
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PortScanner.scan(includeUDP: includeUDP) }
            }.value
            apply(result)
            isScanning = false
            if rescanQueued {
                rescanQueued = false
                refresh()
            }
        }
    }

    private func apply(_ result: Result<[PortEntry], any Error>) {
        switch result {
        case .success(let scanned):
            entries = scanned
            scanError = nil
            let livePIDs = Set(scanned.map(\.pid))
            killStates = killStates.filter { livePIDs.contains($0.key) || $0.value.isWorking }
        case .failure(let error):
            scanError = error.localizedDescription
        }
    }

    // MARK: Killing

    func kill(_ entry: PortEntry, force: Bool, confirmed: Bool = false) {
        if force, preferences.confirmForceKill, !confirmed {
            killStates[entry.pid] = .confirmForce
            return
        }
        run(entry.pid, force: force, asAdmin: false)
    }

    func killAsAdmin(_ entry: PortEntry, force: Bool) {
        run(entry.pid, force: force, asAdmin: true)
    }

    func dismissState(for entry: PortEntry) {
        killStates[entry.pid] = nil
    }

    func hide(_ entry: PortEntry) {
        guard !preferences.hiddenProcesses.contains(entry.processName) else { return }
        preferences.hiddenProcesses.append(entry.processName)
    }

    private func run(_ pid: Int32, force: Bool, asAdmin: Bool) {
        if killStates[pid]?.isWorking == true { return }
        killStates[pid] = .working(force: force)
        let graceSeconds = preferences.graceSeconds
        Task {
            let outcome = asAdmin
                ? await ProcessKiller.terminateAsAdmin(pid, force: force, grace: .seconds(graceSeconds))
                : await ProcessKiller.terminate(pid, force: force, grace: .seconds(graceSeconds))
            handle(outcome, pid: pid, force: force, asAdmin: asAdmin, graceSeconds: graceSeconds)
        }
    }

    private func handle(_ outcome: KillOutcome, pid: Int32, force: Bool, asAdmin: Bool, graceSeconds: Int) {
        switch outcome {
        case .exited:
            killStates[pid] = nil
            entries.removeAll { $0.pid == pid }
            refresh()
        case .stillRunning where force:
            killStates[pid] = .failed("Still running even after SIGKILL")
            NSSound.beep()
        case .stillRunning where preferences.autoForceKill:
            killStates[pid] = nil
            run(pid, force: true, asAdmin: asAdmin)
        case .stillRunning:
            killStates[pid] = .stuck(afterSeconds: graceSeconds)
            NSSound.beep()
        case .permissionDenied:
            killStates[pid] = .permissionDenied
            NSSound.beep()
        case .failed(let message):
            killStates[pid] = .failed(message)
            NSSound.beep()
        }
    }

    #if DEBUG
    /// Used by `Snapshot` to render without waiting on the async scan.
    func loadSynchronously() {
        apply(Result { try PortScanner.scan(includeUDP: preferences.includeUDP) })
    }

    /// Used by `Snapshot` to preview every banner style at once.
    func injectDemoStates() {
        let states: [KillState] = [.stuck(afterSeconds: preferences.graceSeconds), .permissionDenied, .working(force: false), .confirmForce]
        for (entry, state) in zip(visibleEntries, states) {
            killStates[entry.pid] = state
        }
    }
    #endif
}
