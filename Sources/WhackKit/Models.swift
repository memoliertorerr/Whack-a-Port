import Foundation

public enum PortProtocol: String, Sendable, Hashable, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
}

/// One socket line out of lsof, before grouping.
public struct ListeningSocket: Sendable, Hashable {
    public let pid: Int32
    public let command: String
    public let user: String
    public let proto: PortProtocol
    public let host: String
    public let port: Int

    public init(pid: Int32, command: String, user: String, proto: PortProtocol, host: String, port: Int) {
        self.pid = pid
        self.command = command
        self.user = user
        self.proto = proto
        self.host = host
        self.port = port
    }
}

/// What we could learn about a process. Every field is optional because
/// processes owned by other users can't be inspected without root.
public struct ProcessDetails: Sendable, Hashable {
    public var executablePath: String?
    public var workingDirectory: String?
    public var arguments: [String]
    public var startDate: Date?

    public init(executablePath: String? = nil, workingDirectory: String? = nil, arguments: [String] = [], startDate: Date? = nil) {
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.arguments = arguments
        self.startDate = startDate
    }
}

/// A port a process is listening on: one row in the UI.
public struct PortEntry: Identifiable, Sendable, Hashable {
    public var id: String { "\(proto.rawValue)-\(port)-\(pid)" }

    public let port: Int
    public let proto: PortProtocol
    public let pid: Int32
    public let processName: String
    public let user: String
    /// Bound addresses, e.g. ["127.0.0.1", "::1"] or ["*"].
    public let hosts: [String]
    public let details: ProcessDetails

    public init(port: Int, proto: PortProtocol, pid: Int32, processName: String, user: String, hosts: [String], details: ProcessDetails) {
        self.port = port
        self.proto = proto
        self.pid = pid
        self.processName = processName
        self.user = user
        self.hosts = hosts
        self.details = details
    }

    /// True when reachable from other machines (bound to a wildcard or a non-loopback address).
    public var isExposed: Bool {
        hosts.contains { !Self.isLoopback($0) }
    }

    public static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }

    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]

    /// Processes that ship with macOS (ControlCenter's AirPlay receiver, rapportd, …).
    public var isSystemProcess: Bool {
        guard let path = details.executablePath else { return false }
        return Self.systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// The enclosing .app bundle, if the executable lives inside one.
    public var appBundlePath: String? {
        guard let path = details.executablePath, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    public var commandLine: String {
        details.arguments.isEmpty ? (details.executablePath ?? processName) : details.arguments.joined(separator: " ")
    }

    /// `commandLine` with argv[0] shortened to its file name: "node server.js" instead of "/opt/homebrew/bin/node server.js".
    public var displayCommand: String {
        guard let first = details.arguments.first else { return commandLine }
        return ([(first as NSString).lastPathComponent] + details.arguments.dropFirst()).joined(separator: " ")
    }
}
