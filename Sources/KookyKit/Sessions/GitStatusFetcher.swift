import Foundation

/// Snapshot of a working tree's git state for the pane footer.
/// `branch == nil` means "not in a repo" (or git unavailable / errored).
struct GitStatus: Equatable {
    var branch: String?
    var filesChanged: Int
    var insertions: Int
    var deletions: Int

    static let empty = GitStatus(branch: nil, filesChanged: 0, insertions: 0, deletions: 0)
}

/// Per-file slice of the same diff `GitStatus` aggregates — insertions /
/// deletions for one path. Both zero means no countable lines (binary
/// file — numstat prints `-` — or a mode-only change); shortstat still
/// counts such files in `filesChanged`.
struct GitFileDiff: Equatable {
    var insertions: Int
    var deletions: Int
}

/// Spawns `git` on a background queue to populate `Session.gitStatus`.
/// Refreshes are kicked from `WorkspaceStore` on (a) tab spawn, (b) cwd
/// change via OSC 7, and (c) command finished via OSC 133;D. No polling.
///
/// A monotonic per-session generation token drops stale results: if the user
/// `cd`s rapidly, several fetches may be in flight, but only the latest one's
/// result lands on the session.
@MainActor
final class GitStatusFetcher {
    private var generation: [UUID: Int] = [:]

    /// Schedules a fetch for `cwd`. `completion` fires on main with the
    /// freshest result; older in-flight results are silently dropped.
    func fetch(sessionId: UUID, cwd: URL, completion: @MainActor @escaping (GitStatus) -> Void) {
        fetchTokened(id: sessionId, cwd: cwd, work: Self.run, completion: completion)
    }

    /// Per-file companion to `fetch`: `git diff --numstat HEAD` is the same
    /// diff `--shortstat HEAD` summarizes, so the per-file numbers sum to
    /// exactly what the status bar shows. Keys are absolute standardized
    /// paths (repo-root-joined), matching the file tree's row ids.
    func fetchFileDiffs(id: UUID, cwd: URL, completion: @MainActor @escaping ([String: GitFileDiff]) -> Void) {
        fetchTokened(id: id, cwd: cwd, work: Self.runFileDiffs, completion: completion)
    }

    /// Shared dispatch shape for both fetches: bump the caller's generation
    /// token, run `work` on a utility queue, drop the result on main unless
    /// a newer fetch superseded it. One `generation` dict serves both —
    /// callers key by session id vs a store-stable UUID, so the keyspaces
    /// can't collide.
    private func fetchTokened<T: Sendable>(
        id: UUID,
        cwd: URL,
        work: @escaping @Sendable (String) -> T,
        completion: @MainActor @escaping (T) -> Void
    ) {
        let token = (generation[id] ?? 0) + 1
        generation[id] = token
        let path = cwd.path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = work(path)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generation[id] == token else { return }
                completion(result)
            }
        }
    }

    nonisolated private static func runFileDiffs(cwd: String) -> [String: GitFileDiff] {
        // numstat paths are repo-root-relative regardless of cwd; resolve the
        // root so keys can be absolute. Failure (not a repo / no commits yet)
        // mirrors the shortstat path: empty result, badges hide.
        guard let top = runGit(["-C", cwd, "--no-optional-locks", "rev-parse", "--show-toplevel"]),
              let raw = runGit(["-C", cwd, "--no-optional-locks", "diff", "--numstat", "-z", "HEAD"])
        else { return [:] }
        var result: [String: GitFileDiff] = [:]
        for entry in parseNumstat(raw) {
            let abs = URL(fileURLWithPath: top).appendingPathComponent(entry.path).standardizedFileURL.path
            result[abs] = GitFileDiff(insertions: entry.insertions, deletions: entry.deletions)
        }
        return result
    }

    /// Parses `git diff --numstat -z` output. Records are NUL-separated:
    /// `ins\tdel\tpath` for normal entries; a rename emits `ins\tdel\t`
    /// followed by TWO extra NUL fields (pre-path, post-path) — we keep the
    /// post-path (the name on disk now). Binary files print `-` for both
    /// counts → (0, 0).
    nonisolated static func parseNumstat(_ raw: String) -> [(path: String, insertions: Int, deletions: Int)] {
        var entries: [(String, Int, Int)] = []
        let fields = raw.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < fields.count {
            let record = fields[i]
            i += 1
            let parts = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let ins = Int(parts[0]) ?? 0
            let del = Int(parts[1]) ?? 0
            var path = String(parts[2])
            if path.isEmpty {
                // Rename record: consume the pre/post fields, keep post.
                guard i + 1 < fields.count else { continue }
                path = fields[i + 1]
                i += 2
            }
            guard !path.isEmpty else { continue }
            entries.append((path, ins, del))
        }
        return entries
    }

    nonisolated private static func run(cwd: String) -> GitStatus {
        // `--abbrev-ref HEAD` returns the branch name, or "HEAD" when detached.
        // Failure here usually means cwd isn't inside a repo — fall through to
        // empty so the footer hides cleanly.
        guard let head = runGit(["-C", cwd, "--no-optional-locks", "rev-parse", "--abbrev-ref", "HEAD"]) else {
            return .empty
        }
        let branch: String
        if head == "HEAD" {
            branch = runGit(["-C", cwd, "--no-optional-locks", "rev-parse", "--short", "HEAD"]) ?? "HEAD"
        } else {
            branch = head
        }
        let stat = runGit(["-C", cwd, "--no-optional-locks", "diff", "--shortstat", "HEAD"]) ?? ""
        let (files, ins, del) = parseShortstat(stat)
        return GitStatus(branch: branch, filesChanged: files, insertions: ins, deletions: del)
    }

    /// Accumulates a pipe's contents on a background thread. `@unchecked
    /// Sendable` is sound because `data` is written only by the reader
    /// thread before `done.signal()`, and read only after `done.wait()` —
    /// the semaphore provides the happens-before edge.
    private final class PipeDrain: @unchecked Sendable {
        var data = Data()
        let done = DispatchSemaphore(value: 0)
    }

    /// Runs `git <args>` with a 1-second timeout; returns trimmed stdout on
    /// exit 0, nil otherwise. Uses `/usr/bin/env` so the spawned subprocess
    /// resolves git via PATH (covers Apple's /usr/bin/git stub + Homebrew).
    ///
    /// stdout is drained CONCURRENTLY with the exit wait — reading only
    /// after termination deadlocks once output exceeds the ~64KB pipe
    /// buffer (git blocks writing, never exits, the timeout kills it and
    /// the caller sees nil). Small outputs (branch, shortstat) never hit
    /// it; `--numstat` on a large changeset (~2k files) and `for-each-ref`
    /// on branch-heavy repos do. stderr goes to the null device — it was
    /// never read, so a chatty-stderr git had the same latent deadlock.
    nonisolated static func runGit(_ args: [String], timeout: TimeInterval = 1.0) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git"] + args
        task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }

        do {
            try task.run()
        } catch {
            return nil
        }

        let drain = PipeDrain()
        DispatchQueue.global(qos: .utility).async {
            drain.data = stdout.fileHandleForReading.readDataToEndOfFile()
            drain.done.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            _ = exited.wait(timeout: .now() + 0.1)
            // The terminate closes the pipe; the drain thread unblocks and
            // finishes on its own — nothing waits on it.
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        // Exit closes git's end of the pipe, so EOF is imminent; the extra
        // timeout is pure paranoia against a leaked write end.
        guard drain.done.wait(timeout: .now() + timeout) == .success else { return nil }
        return String(data: drain.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `git diff --shortstat` lines like
    /// ` 3 files changed, 47 insertions(+), 12 deletions(-)`.
    /// Returns `(0, 0, 0)` for empty / unparseable input — all fields drop.
    nonisolated static func parseShortstat(_ s: String) -> (files: Int, insertions: Int, deletions: Int) {
        var files = 0
        var ins = 0
        var del = 0
        for token in s.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let n = Int(parts[0]) else { continue }
            let label = parts[1]
            if label.hasPrefix("file") {
                files = n
            } else if label.hasPrefix("insertion") {
                ins = n
            } else if label.hasPrefix("deletion") {
                del = n
            }
        }
        return (files, ins, del)
    }
}

enum GitBranchInventory {
    static func localBranches(cwd: URL) -> [String] {
        let output = GitStatusFetcher.runGit([
            "-C", cwd.path,
            "--no-optional-locks",
            "for-each-ref",
            "--sort=-committerdate",
            "--format=%(refname:short)",
            "refs/heads",
        ]) ?? ""
        return parseBranches(output)
    }

    static func shellSwitchCommand(branch: String) -> String {
        "git switch \(KookyShellIntegration.quote(branch))\r"
    }

    static func parseBranches(_ output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
