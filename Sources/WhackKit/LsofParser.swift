import Foundation

/// Parses `lsof -F pcuLn` output: one field per line, the first character is the field tag.
///
///     p921            process id
///     cControlCenter  command
///     u501            uid
///     Lmemoli         login name
///     f10             file descriptor (ignored)
///     n*:7000         socket name
public enum LsofParser {
    public static func parse(_ output: String, proto: PortProtocol) -> [ListeningSocket] {
        var sockets: [ListeningSocket] = []
        var pid: Int32?
        var command = ""
        var user = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
                user = ""
            case "c":
                command = value
            case "u", "L":
                // L (login) follows u (uid) and wins when present.
                user = value
            case "n":
                guard let pid, let (host, port) = parseAddress(value) else { continue }
                sockets.append(ListeningSocket(pid: pid, command: command, user: user, proto: proto, host: host, port: port))
            default:
                break
            }
        }
        return sockets
    }

    /// "127.0.0.1:8080" → ("127.0.0.1", 8080), "[::1]:5432" → ("::1", 5432).
    /// Returns nil for connected sockets ("a->b") and unbound ports ("*:*").
    public static func parseAddress(_ name: String) -> (host: String, port: Int)? {
        guard !name.contains("->"), let colon = name.lastIndex(of: ":") else { return nil }
        guard let port = Int(name[name.index(after: colon)...]), port > 0 else { return nil }
        var host = String(name[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return (host, port)
    }

    /// Collapses the per-fd lines (IPv4 + IPv6 of the same port, etc.) into one entry per (proto, port, pid).
    public static func group(_ sockets: [ListeningSocket], details: (Int32) -> ProcessDetails) -> [PortEntry] {
        struct Key: Hashable { let proto: PortProtocol; let port: Int; let pid: Int32 }

        var order: [Key] = []
        var bySocket: [Key: (first: ListeningSocket, hosts: [String])] = [:]
        for socket in sockets {
            let key = Key(proto: socket.proto, port: socket.port, pid: socket.pid)
            if var existing = bySocket[key] {
                if !existing.hosts.contains(socket.host) { existing.hosts.append(socket.host) }
                bySocket[key] = existing
            } else {
                order.append(key)
                bySocket[key] = (socket, [socket.host])
            }
        }

        var detailCache: [Int32: ProcessDetails] = [:]
        let entries = order.map { key -> PortEntry in
            let (first, hosts) = bySocket[key]!
            let info = detailCache[key.pid] ?? details(key.pid)
            detailCache[key.pid] = info
            return PortEntry(port: key.port, proto: key.proto, pid: key.pid, processName: first.command,
                             user: first.user, hosts: hosts, details: info)
        }
        return entries.sorted { ($0.port, $0.proto.rawValue, $0.pid) < ($1.port, $1.proto.rawValue, $1.pid) }
    }
}
