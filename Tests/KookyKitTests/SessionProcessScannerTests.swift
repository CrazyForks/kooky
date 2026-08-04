import XCTest
@testable import KookyKit

final class SessionProcessScannerTests: XCTestCase {
    private func raw(_ pid: pid_t, _ ppid: pid_t, _ name: String, fg: Bool = false) -> SessionProcessScanner.Raw {
        SessionProcessScanner.Raw(pid: pid, ppid: ppid, name: name, isForeground: fg)
    }

    /// libghostty spawns the shell through `/usr/bin/login` on macOS, so the
    /// tty's root is plumbing the user never started.
    func testStripsTheLoginRootAndRootsAtTheShell() {
        let tree = SessionProcessScanner.tree(from: [
            raw(100, 1, "login"),
            raw(101, 100, "zsh"),
            raw(102, 101, "claude", fg: true),
        ])

        XCTAssertEqual(tree.map(\.name), ["zsh", "claude"])
        XCTAssertEqual(tree.map(\.depth), [0, 1])
        XCTAssertEqual(tree.map(\.pid), [101, 102])
    }

    /// Only a ROOT login is plumbing. One the user ran themselves sits under
    /// the shell and has to survive.
    func testKeepsALoginTheUserRanThemselves() {
        let tree = SessionProcessScanner.tree(from: [
            raw(100, 1, "login"),
            raw(101, 100, "zsh"),
            raw(102, 101, "login", fg: true),
        ])

        XCTAssertEqual(tree.map(\.name), ["zsh", "login"])
        XCTAssertEqual(tree.map(\.depth), [0, 1])
    }

    /// `command = $SHELL` skips `login` entirely — the shell is the root.
    func testHandlesAShellRootedTerminal() {
        let tree = SessionProcessScanner.tree(from: [
            raw(101, 1, "fish", fg: true),
            raw(102, 101, "git"),
        ])

        XCTAssertEqual(tree.map(\.name), ["fish", "git"])
        XCTAssertEqual(tree.map(\.depth), [0, 1])
    }

    func testOrdersSiblingsByPidAndNestsDepthFirst() {
        let tree = SessionProcessScanner.tree(from: [
            raw(101, 1, "zsh"),
            raw(120, 101, "node"),
            raw(110, 101, "claude"),
            raw(111, 110, "rg"),
        ])

        XCTAssertEqual(tree.map(\.name), ["zsh", "claude", "rg", "node"])
        XCTAssertEqual(tree.map(\.depth), [0, 1, 2, 1])
    }

    /// A pipeline puts several processes in one foreground group; the flag is
    /// carried per process rather than derived from a single pid.
    func testCarriesForegroundAcrossAWholePipeline() {
        let tree = SessionProcessScanner.tree(from: [
            raw(101, 1, "zsh"),
            raw(110, 101, "rg", fg: true),
            raw(111, 101, "less", fg: true),
        ])

        XCTAssertEqual(tree.filter(\.isForeground).map(\.name), ["rg", "less"])
        XCTAssertFalse(tree[0].isForeground)
    }

    func testEmptyInputAndDeadPidYieldNothing() {
        XCTAssertTrue(SessionProcessScanner.tree(from: []).isEmpty)
        XCTAssertTrue(SessionProcessScanner.scan(foregroundPid: 0).isEmpty)
        XCTAssertTrue(SessionProcessScanner.scan(foregroundPid: -1).isEmpty)
    }

    /// End-to-end against the kernel: when the test runner has a controlling
    /// terminal, its own tty must list this process. Skipped under a runner
    /// with no tty (CI), where the scan correctly returns nothing.
    func testScansTheRunnersOwnTerminal() throws {
        let tree = SessionProcessScanner.scan(foregroundPid: getpid())
        try XCTSkipIf(tree.isEmpty, "test runner has no controlling terminal")

        XCTAssertTrue(
            tree.contains { $0.pid == getpid() },
            "the scanning process is on its own tty: \(tree.map { "\($0.name)(\($0.pid))" })"
        )
        XCTAssertEqual(tree.first?.depth, 0)
        XCTAssertFalse(tree.contains { $0.name.isEmpty }, "p_comm must resolve to a real name")
    }

    func testTreeCarriesPortsThrough() {
        var listener = raw(101, 1, "node", fg: true)
        listener.ports = [3000, 5173]
        let tree = SessionProcessScanner.tree(from: [listener, raw(102, 101, "esbuild")])

        XCTAssertEqual(tree.map(\.ports), [[3000, 5173], []])
    }

    /// End-to-end against the kernel: bind a real TCP listener on a
    /// system-assigned port, then the scan of our own pid must report it.
    func testListeningPortsFindsARealListener() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try XCTSkipIf(fd < 0, "cannot create a socket in this environment")
        var fdOpen = true
        defer { if fdOpen { close(fd) } }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try XCTSkipIf(bound != 0, "cannot bind in this environment")
        XCTAssertEqual(listen(fd, 1), 0)

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        let port = UInt16(bigEndian: assigned.sin_port)
        XCTAssertGreaterThan(port, 0)

        XCTAssertTrue(
            SessionProcessScanner.listeningPorts(of: getpid()).contains(port),
            "our own LISTEN socket on :\(port) must be reported"
        )
        // An outbound/closed socket must NOT appear: close the listener and
        // confirm it drops out.
        close(fd)
        fdOpen = false
        XCTAssertFalse(SessionProcessScanner.listeningPorts(of: getpid()).contains(port))
    }
}
