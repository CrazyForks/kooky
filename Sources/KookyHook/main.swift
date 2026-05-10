import Darwin
import Foundation

// kooky-hook: invoked by an agent's hook system (Claude Code's `--settings`
// hooks, Codex equivalents, …) and the shell precmd hook (`env` mode) to
// ping the running kooky app over a unix socket.
//
// Exit codes:
//   0 — IPC succeeded, OR caller is outside kooky (no surface id) / args
//       malformed (programmer error). Both are "no retry needed."
//   1 — IPC failed (kooky not listening, socket gone, write error). Shell
//       callers use this to keep their dedup cache un-advanced so the next
//       prompt re-attempts. Without this distinction, a single transient
//       failure (kooky restarting, socket recreated) would freeze the env
//       cache permanently.
//
// Usage: kooky-hook <agent> <event>
//   <agent> ∈ claude | codex (or any AgentTemplate.id)
//   <event> ∈ running | attention | idle
// Usage: kooky-hook env <VIRTUAL_ENV> <CONDA_DEFAULT_ENV> <NVM_BIN> <NVM_DIR> <NODE_VERSION>
// Reads:  $KOOKY_SURFACE_ID       UUID of the originating session
// Reads:  any stdin               drained but ignored (Claude pipes JSON in)

let surface = ProcessInfo.processInfo.environment["KOOKY_SURFACE_ID"] ?? ""
guard !surface.isEmpty else { exit(0) }

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let socketPath = support.appendingPathComponent("kooky/socket").path

func arg(_ index: Int) -> String {
    CommandLine.arguments.indices.contains(index) ? CommandLine.arguments[index] : ""
}

let payloadObject: [String: String]
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "env" {
    payloadObject = [
        "kind": "env",
        "surface": surface,
        "VIRTUAL_ENV": arg(2),
        "CONDA_DEFAULT_ENV": arg(3),
        "NVM_BIN": arg(4),
        "NVM_DIR": arg(5),
        "KOOKY_NODE_VERSION": arg(6),
    ]
} else if CommandLine.arguments.count >= 3 {
    payloadObject = [
        "agent": CommandLine.arguments[1],
        "event": CommandLine.arguments[2],
        "surface": surface,
    ]
} else {
    exit(0)
}

guard var payload = try? JSONSerialization.data(withJSONObject: payloadObject) else { exit(0) }
payload.append(0x0A)

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(1) }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
guard pathBytes.count < sunPathSize else { exit(0) }
withUnsafeMutableBytes(of: &addr.sun_path) { dst in
    pathBytes.withUnsafeBufferPointer { src in
        dst.baseAddress?.copyMemory(from: src.baseAddress!, byteCount: src.count)
    }
}

let len = socklen_t(MemoryLayout<sockaddr_un>.size)
let connected = withUnsafePointer(to: &addr) { addrPtr in
    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, len)
    }
}
guard connected == 0 else { exit(1) }

let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
exit(written < 0 ? 1 : 0)
