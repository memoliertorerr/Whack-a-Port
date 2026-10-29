import Darwin
import Foundation

public enum KillOutcome: Sendable, Equatable {
    /// The process is gone.
    case exited
    /// The signal was delivered but the process is still alive after the grace period.
    case stillRunning
    /// Owned by another user (usually root).
    case permissionDenied
    case failed(String)
}

public enum ProcessKiller {
    public static func isAlive(_ pid: pid_t) -> Bool {
        let exists = Darwin.kill(pid, 0) == 0 || errno == EPERM
        return exists && !ProcessInspector.isZombie(pid)
    }

    /// Sends SIGTERM (or SIGKILL when `force`) and waits up to `grace` for the process to exit.
    public static func terminate(_ pid: pid_t, force: Bool, grace: Duration) async -> KillOutcome {
        if Darwin.kill(pid, force ? SIGKILL : SIGTERM) != 0 {
            switch errno {
            case ESRCH: return .exited
            case EPERM: return .permissionDenied
            default: return .failed(String(cString: strerror(errno)))
            }
        }
        return await waitForExit(pid, timeout: force ? .seconds(1) : grace)
    }

    /// Same as `terminate`, but runs `kill` through an admin password prompt.
    public static func terminateAsAdmin(_ pid: pid_t, force: Bool, grace: Duration) async -> KillOutcome {
        let signal = force ? "KILL" : "TERM"
        let script = "do shell script \"/bin/kill -\(signal) \(pid)\" with administrator privileges"
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
        guard status == 0 else {
            return isAlive(pid) ? .failed("Admin kill was cancelled or failed") : .exited
        }
        return await waitForExit(pid, timeout: force ? .seconds(1) : grace)
    }

    private static func waitForExit(_ pid: pid_t, timeout: Duration) async -> KillOutcome {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !isAlive(pid) { return .exited }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return isAlive(pid) ? .stillRunning : .exited
    }
}
