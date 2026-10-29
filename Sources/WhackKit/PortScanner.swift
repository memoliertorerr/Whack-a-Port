import Foundation

public enum PortScanner {
    public struct LsofError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Lists every port a process is listening on. Blocking (~100ms); call off the main thread.
    public static func scan(includeUDP: Bool) throws -> [PortEntry] {
        var sockets = LsofParser.parse(try runLsof(["-iTCP", "-sTCP:LISTEN"]), proto: .tcp)
        if includeUDP {
            sockets += LsofParser.parse(try runLsof(["-iUDP"]), proto: .udp)
        }
        return LsofParser.group(sockets, details: ProcessInspector.details(for:))
    }

    private static func runLsof(_ selection: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -n/-P: no DNS or service-name lookups. +c 0: untruncated command names.
        process.arguments = ["-nP", "+c", "0"] + selection + ["-FpcuLn"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw LsofError(message: "Couldn't run lsof: \(error.localizedDescription)")
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(decoding: output, as: UTF8.self)
        // lsof exits 1 with no output when nothing matches; that's an empty result, not an error.
        let message = String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0, text.isEmpty, !message.isEmpty {
            throw LsofError(message: "lsof failed: \(message)")
        }
        return text
    }
}
