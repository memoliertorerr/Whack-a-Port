import Foundation
import Testing
@testable import WhackKit

@Suite struct LsofParserTests {
    static let sample = """
    p921
    cControlCenter
    u501
    Lmemoli
    f10
    n*:7000
    f11
    n*:7000
    f12
    n*:5000
    p1639
    cCode Helper (Plugin)
    u501
    Lmemoli
    f37
    n127.0.0.1:49209
    f38
    n[::1]:49209
    p42
    cnode
    u501
    f3
    n*:*
    f4
    n127.0.0.1:5000->127.0.0.1:61000
    """

    @Test func parsesSocketsAndSkipsUnboundAndConnected() {
        let sockets = LsofParser.parse(Self.sample, proto: .tcp)
        #expect(sockets.count == 5)
        #expect(sockets.allSatisfy { $0.pid != 42 })
        #expect(sockets[0] == ListeningSocket(pid: 921, command: "ControlCenter", user: "memoli", proto: .tcp, host: "*", port: 7000))
        #expect(sockets.last?.host == "::1")
        #expect(sockets.last?.command == "Code Helper (Plugin)")
    }

    @Test func fallsBackToUidWithoutLogin() {
        let sockets = LsofParser.parse("p7\ncfoo\nu0\nf1\nn*:80\n", proto: .tcp)
        #expect(sockets.first?.user == "0")
    }

    @Test(arguments: [
        ("*:7000", "*", 7000),
        ("127.0.0.1:8080", "127.0.0.1", 8080),
        ("[::1]:5432", "::1", 5432),
        ("[fe80::1%lo0]:631", "fe80::1%lo0", 631),
    ])
    func parsesAddresses(name: String, host: String, port: Int) throws {
        let parsed = try #require(LsofParser.parseAddress(name))
        #expect(parsed.host == host)
        #expect(parsed.port == port)
    }

    @Test func rejectsNonListeningAddresses() {
        #expect(LsofParser.parseAddress("*:*") == nil)
        #expect(LsofParser.parseAddress("1.2.3.4:5->6.7.8.9:10") == nil)
        #expect(LsofParser.parseAddress("garbage") == nil)
    }

    @Test func groupsIPv4AndIPv6IntoOneEntrySortedByPort() {
        var lookups: [Int32] = []
        let entries = LsofParser.group(LsofParser.parse(Self.sample, proto: .tcp)) { pid in
            lookups.append(pid)
            return ProcessDetails()
        }
        #expect(entries.map(\.port) == [5000, 7000, 49209])
        #expect(entries.first { $0.port == 49209 }?.hosts == ["127.0.0.1", "::1"])
        #expect(entries.first { $0.port == 7000 }?.hosts == ["*"])
        #expect(lookups.sorted() == [921, 1639], "details are fetched once per process")
    }
}

@Suite struct PortEntryTests {
    func entry(hosts: [String], path: String? = nil) -> PortEntry {
        PortEntry(port: 1, proto: .tcp, pid: 1, processName: "x", user: "me", hosts: hosts,
                  details: ProcessDetails(executablePath: path))
    }

    @Test func exposure() {
        #expect(entry(hosts: ["127.0.0.1", "::1"]).isExposed == false)
        #expect(entry(hosts: ["*"]).isExposed)
        #expect(entry(hosts: ["127.0.0.1", "192.168.1.5"]).isExposed)
    }

    @Test func systemProcesses() {
        #expect(entry(hosts: [], path: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter").isSystemProcess)
        #expect(entry(hosts: [], path: "/usr/libexec/rapportd").isSystemProcess)
        #expect(entry(hosts: [], path: "/opt/homebrew/bin/node").isSystemProcess == false)
        #expect(entry(hosts: [], path: nil).isSystemProcess == false)
    }

    @Test func displayCommandShortensArgvZero() {
        let entry = PortEntry(port: 3000, proto: .tcp, pid: 1, processName: "node", user: "me", hosts: ["*"],
                              details: ProcessDetails(arguments: ["/opt/homebrew/bin/node", "server.js", "--port", "3000"]))
        #expect(entry.displayCommand == "node server.js --port 3000")
        #expect(entry.commandLine == "/opt/homebrew/bin/node server.js --port 3000")
    }

    @Test func appBundle() {
        let path = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
        #expect(entry(hosts: [], path: path).appBundlePath == "/Applications/Visual Studio Code.app")
        #expect(entry(hosts: [], path: "/opt/homebrew/bin/node").appBundlePath == nil)
    }
}

@Suite struct ProcessInspectorTests {
    @Test func parsesProcArgs() {
        var bytes = withUnsafeBytes(of: Int32(3)) { Array($0) }
        bytes += Array("/usr/bin/python3".utf8) + [0, 0, 0]
        bytes += Array("python3".utf8) + [0] + Array("-m".utf8) + [0] + Array("http.server".utf8) + [0]
        bytes += Array("PATH=/usr/bin".utf8) + [0]
        #expect(ProcessInspector.parseProcArgs(bytes) == ["python3", "-m", "http.server"])
    }

    @Test func inspectsOwnProcess() throws {
        let details = ProcessInspector.details(for: getpid())
        #expect(details.executablePath != nil)
        #expect(details.workingDirectory == FileManager.default.currentDirectoryPath)
        #expect(!details.arguments.isEmpty)
        #expect(try #require(details.startDate) < .now)
    }
}

/// Spins up real listeners with python3 and kills them through the same code paths the app uses.
@Suite(.serialized) struct EndToEndTests {
    func startListener(port: Int, ignoreSIGTERM: Bool) throws -> Process {
        let script = """
        import signal, socket, time
        \(ignoreSIGTERM ? "signal.signal(signal.SIGTERM, signal.SIG_IGN)" : "")
        s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", \(port))); s.listen(); time.sleep(60)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script]
        try process.run()
        return process
    }

    func waitForPort(_ port: Int) async throws -> PortEntry {
        for _ in 0..<50 {
            if let entry = try PortScanner.scan(includeUDP: false).first(where: { $0.port == port }) { return entry }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CancellationError()
    }

    @Test func scanFindsListenerAndSigtermKillsIt() async throws {
        let process = try startListener(port: 47_821, ignoreSIGTERM: false)
        let entry = try await waitForPort(47_821)
        #expect(entry.pid == process.processIdentifier)
        #expect(entry.hosts == ["127.0.0.1"])
        #expect(entry.details.arguments.contains("-c"))

        let outcome = await ProcessKiller.terminate(entry.pid, force: false, grace: .seconds(3))
        #expect(outcome == .exited)
        #expect(try PortScanner.scan(includeUDP: false).contains { $0.port == 47_821 } == false)
    }

    @Test func stubbornProcessReportsStillRunningThenForceKillWorks() async throws {
        let process = try startListener(port: 47_822, ignoreSIGTERM: true)
        defer { if process.isRunning { process.terminate() } }
        let entry = try await waitForPort(47_822)

        #expect(await ProcessKiller.terminate(entry.pid, force: false, grace: .seconds(1)) == .stillRunning)
        #expect(await ProcessKiller.terminate(entry.pid, force: true, grace: .seconds(1)) == .exited)
    }

    @Test func rootProcessIsPermissionDenied() async {
        // launchd (pid 1) belongs to root, so SIGTERM from a normal user must be refused.
        #expect(await ProcessKiller.terminate(1, force: false, grace: .seconds(1)) == .permissionDenied)
    }
}
