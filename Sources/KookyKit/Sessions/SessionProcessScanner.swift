import Darwin
import Foundation

/// One process running on a session's terminal.
struct SessionProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// Nesting under the session's shell — 0 is the shell itself.
    let depth: Int
    /// In the terminal's foreground process group: what a keystroke would
    /// reach, and what the user means by "what is this tab running". A
    /// pipeline puts several processes in one group, so this is a set, not a
    /// single pid.
    let isForeground: Bool
    /// TCP ports this process is LISTENING on, ascending. Listen-only on
    /// purpose: established connections and UDP binds (mDNS etc.) are noise,
    /// while "which port did my dev server take" is the question this
    /// answers.
    let ports: [UInt16]

    var id: pid_t { pid }
}

/// Lists the processes attached to a session's pty.
///
/// Membership is by CONTROLLING TERMINAL, the same rule `ps -t` uses — not by
/// walking down from kooky. kooky's own child is `/usr/bin/login`, the shell is
/// its child, and a tree walk would have to guess which branch belongs to which
/// tab; every process on the tty belongs to exactly one tab by construction.
enum SessionProcessScanner {
    /// Flattened kernel row, split out so the tree logic is testable without
    /// a live pty.
    struct Raw: Equatable {
        let pid: pid_t
        let ppid: pid_t
        let name: String
        let isForeground: Bool
        var ports: [UInt16] = []
    }

    /// The processes on `foregroundPid`'s terminal, depth-first from the shell.
    /// Empty when the pid is gone or has no controlling terminal.
    static func scan(foregroundPid: pid_t) -> [SessionProcess] {
        guard foregroundPid > 0, let tty = controllingTerminal(of: foregroundPid) else { return [] }
        var raw = processes(onTerminal: tty)
        for i in raw.indices {
            raw[i].ports = listeningPorts(of: raw[i].pid)
        }
        return tree(from: raw)
    }

    /// Depth-first order, children by pid, rooted at the session's shell.
    ///
    /// A root named `login` is replaced by its children: on macOS libghostty
    /// spawns the shell through `/usr/bin/login`, which is plumbing the user
    /// never started. Only a ROOT is stripped, so a `login` the user ran
    /// themselves — which sits under the shell — still shows up.
    static func tree(from raw: [Raw]) -> [SessionProcess] {
        let byPid = Dictionary(raw.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [pid_t: [Raw]] = [:]
        var roots: [Raw] = []
        for entry in raw {
            if byPid[entry.ppid] != nil {
                children[entry.ppid, default: []].append(entry)
            } else {
                roots.append(entry)
            }
        }

        var start = roots.sorted { $0.pid < $1.pid }
        while start.count == 1, start[0].name == "login" {
            start = (children[start[0].pid] ?? []).sorted { $0.pid < $1.pid }
        }

        var result: [SessionProcess] = []
        func visit(_ entry: Raw, depth: Int) {
            result.append(SessionProcess(
                pid: entry.pid,
                name: entry.name,
                depth: depth,
                isForeground: entry.isForeground,
                ports: entry.ports
            ))
            for child in (children[entry.pid] ?? []).sorted(by: { $0.pid < $1.pid }) {
                visit(child, depth: depth + 1)
            }
        }
        for root in start { visit(root, depth: 0) }
        return result
    }

    // MARK: - Kernel

    private static func controllingTerminal(of pid: pid_t) -> dev_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0, size > 0 else { return nil }
        let tty = proc.kp_eproc.e_tdev
        // NODEV — the process has no controlling terminal.
        return tty == -1 ? nil : tty
    }

    private static func processes(onTerminal tty: dev_t) -> [Raw] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(tty)]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        // The set can grow between sizing and fetching; ask for slack and trust
        // the size sysctl writes back rather than the one we requested.
        size += MemoryLayout<kinfo_proc>.stride * 8
        var list = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &list, &size, nil, 0) == 0 else { return [] }

        return list.prefix(size / MemoryLayout<kinfo_proc>.stride).map { entry in
            Raw(
                pid: entry.kp_proc.p_pid,
                ppid: entry.kp_eproc.e_ppid,
                name: processName(entry),
                // The tty's foreground process group — the textbook definition,
                // and it covers every process of a pipeline rather than the one
                // pid libghostty hands back.
                isForeground: entry.kp_eproc.e_pgid == entry.kp_eproc.e_tpgid
            )
        }
    }

    /// TCP ports `pid` is listening on, ascending — the same libproc walk
    /// `lsof -sTCP:LISTEN` performs, without the subprocess: list the fds,
    /// then fetch socket info for the SOCKET-type ones. Same-uid processes
    /// are readable without privileges; anything unreadable just reports no
    /// ports. v4 + v6 listeners on one port collapse via the Set.
    static func listeningPorts(of pid: pid_t) -> [UInt16] {
        let fdSize = MemoryLayout<proc_fdinfo>.stride
        let bytesNeeded = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }
        // The fd table can grow between sizing and fetching — same slack
        // pattern as `processes(onTerminal:)`.
        var fds = [proc_fdinfo](
            repeating: proc_fdinfo(),
            count: Int(bytesNeeded) / fdSize + 8
        )
        let bytesRead = fds.withUnsafeMutableBytes { buf in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buf.baseAddress, Int32(buf.count))
        }
        guard bytesRead > 0 else { return [] }

        var ports: Set<UInt16> = []
        for fd in fds.prefix(Int(bytesRead) / fdSize) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == SOCKINFO_TCP,
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
            else { continue }
            // `insi_lport` carries the 16-bit port in network byte order.
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport))
            if port > 0 { ports.insert(port) }
        }
        return ports.sorted()
    }

    /// `p_comm` is the kernel's accounting name — already the bare executable
    /// name (`zsh`, not the login shell's `-/bin/zsh` argv[0]), capped at
    /// `MAXCOMLEN`.
    private static func processName(_ entry: kinfo_proc) -> String {
        withUnsafePointer(to: entry.kp_proc.p_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                String(cString: $0)
            }
        }
    }
}
