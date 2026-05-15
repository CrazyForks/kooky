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
// Usage: kooky-hook env <VIRTUAL_ENV> <CONDA_DEFAULT_ENV> <NVM_BIN> <NVM_DIR> <NODE_VERSION> <https_proxy> <http_proxy> <all_proxy>
// Reads:  $KOOKY_SURFACE_ID       UUID of the originating session
// Reads:  stdin                   Claude pipes a JSON object — when `agent`
//                                 is `claude` and the JSON carries
//                                 `session_id`, we send a second payload
//                                 (`kind: conversationId`) so kooky can
//                                 persist the value and prepend
//                                 `--resume <id>` on next launch.

let surface = ProcessInfo.processInfo.environment["KOOKY_SURFACE_ID"] ?? ""
guard !surface.isEmpty else { exit(0) }

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let socketPath = support.appendingPathComponent("kooky/socket").path

func arg(_ index: Int) -> String {
    CommandLine.arguments.indices.contains(index) ? CommandLine.arguments[index] : ""
}

/// One-shot socket write. Returns true on success. Each invocation of
/// kooky-hook may emit 1–2 of these (event payload + optional Claude
/// conversation-id payload); HookServer accepts one payload per connection.
func sendPayload(_ object: [String: String]) -> Bool {
    guard var payload = try? JSONSerialization.data(withJSONObject: object) else { return false }
    payload.append(0x0A)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
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
    guard connected == 0 else { return false }

    let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    return written >= 0
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
        "https_proxy": arg(7),
        "http_proxy": arg(8),
        "all_proxy": arg(9),
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

let eventSent = sendPayload(payloadObject)

// Claude pipes a JSON object on stdin with every hook event (SessionStart,
// UserPromptSubmit, Stop, SessionEnd, …). The relevant field for us is
// `session_id` — its conversation identifier. We mirror it back to kooky
// as a separate payload so WorkspaceStore can persist it on Session and
// reuse it as `--resume <id>` on the next launch. Other agents either
// don't pipe stdin or don't expose a session id, so this branch is a
// silent no-op for them.
if payloadObject["agent"] == "claude", isatty(fileno(stdin)) == 0 {
    // Claude pipes the JSON; `readToEnd()` blocks until it closes stdin —
    // perfect when stdin is a pipe. But the `claude` wrapper script also
    // invokes us with `claude ended` from its "binary not installed"
    // branch (see ShellIntegration.swift `wrapperPreamble`), where stdin
    // is still the user's terminal. `readToEnd()` would block forever
    // waiting for EOF on the tty and strand the tab. `isatty == 0` says
    // stdin is a pipe / regular file → safe to drain to EOF.
    let stdinData = (try? FileHandle.standardInput.readToEnd()) ?? Data()
    if !stdinData.isEmpty,
       let parsed = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any],
       let sessionId = parsed["session_id"] as? String,
       !sessionId.isEmpty {
        _ = sendPayload([
            "kind": "conversationId",
            "surface": surface,
            "conversationId": sessionId,
        ])
    }
}

exit(eventSent ? 0 : 1)
