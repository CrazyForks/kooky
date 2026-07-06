import Foundation

// MARK: - Values + listing (nonisolated so tests reach them without the main actor)

/// One filesystem entry in the sidebar file tree.
struct FileNode: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    /// False for symlinks even when they point at a directory — the tree
    /// never expands through links, which is what keeps symlink cycles from
    /// being representable at all.
    let isDirectory: Bool
    let isSymlink: Bool

    /// Path-stable identity: a refresh keeps rows for surviving entries,
    /// while a rename is a new node (old row out, new row in).
    var id: String { url.path }
}

/// One visible row after flattening the expanded tree for the `LazyVStack`.
struct FileTreeRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case entry(FileNode)
        /// Non-interactive note under an expanded-but-unlistable directory.
        case placeholder(String)
    }

    let kind: Kind
    /// 0 = direct child of the root; drives the row's leading indent.
    let depth: Int
    /// Whether this row's directory is showing its children — baked into the
    /// row (rather than queried off the model) so expanding an *empty*
    /// directory still produces a row diff and the chevron animates.
    let isExpanded: Bool
    let id: String
}

enum FileTreeLister {
    /// Entries never shown. Other dotfiles stay visible — developers live in
    /// `.env` / `.gitignore` — but `.git` is plumbing and `.DS_Store` is
    /// Finder noise.
    static let hiddenNames: Set<String> = [".git", ".DS_Store"]

    /// Shallow listing of one directory: `hiddenNames` filtered, directories
    /// first, Finder-style natural sort within each group. Throws on a
    /// missing/unreadable directory so callers can tell "empty" from
    /// "gone" — the model routes root failures to `rootError` and child
    /// failures to a placeholder row.
    static func children(of directory: URL) throws -> [FileNode] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        return urls.compactMap { url -> FileNode? in
            let name = url.lastPathComponent
            guard !hiddenNames.contains(name) else { return nil }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isSymlink = values?.isSymbolicLink == true
            return FileNode(
                url: url,
                name: name,
                isDirectory: values?.isDirectory == true && !isSymlink,
                isSymlink: isSymlink
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Flattens the expanded tree into the visible-row array. Recursing views
    /// inside a `LazyVStack` would defeat its laziness, so the tree shape is
    /// resolved here and the view renders a flat list.
    static func flatten(
        root: URL,
        childrenByDir: [String: [FileNode]],
        expandedDirs: Set<String>,
        failedDirs: Set<String>
    ) -> [FileTreeRow] {
        var rows: [FileTreeRow] = []
        // Children pushed in reverse so pop order matches display order.
        var stack: [(FileNode, Int)] =
            (childrenByDir[root.path] ?? []).reversed().map { ($0, 0) }
        while let (node, depth) = stack.popLast() {
            let path = node.url.path
            let isExpanded = node.isDirectory && expandedDirs.contains(path)
            rows.append(FileTreeRow(kind: .entry(node), depth: depth, isExpanded: isExpanded, id: node.id))
            guard isExpanded else { continue }
            if failedDirs.contains(path) {
                rows.append(FileTreeRow(
                    kind: .placeholder("no access"),
                    depth: depth + 1,
                    isExpanded: false,
                    id: path + "/__placeholder__"
                ))
                continue
            }
            for child in (childrenByDir[path] ?? []).reversed() {
                stack.append((child, depth + 1))
            }
        }
        return rows
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "ico", "bmp", "tiff",
    ]

    static func symbolName(for node: FileNode) -> String {
        if node.isDirectory { return "folder.fill" }
        if imageExtensions.contains(node.url.pathExtension.lowercased()) { return "photo" }
        return "doc.text"
    }
}

// MARK: - Model

/// Sidebar file-tree state for one window: lazy per-directory listings,
/// ephemeral expansion, and kqueue watchers on the visible directories.
/// Owned by `WorkspaceStore` (not view `@State`) because the watchers hold
/// fds that need explicit teardown and the sidebar unmounts whole while
/// hidden — `FileTreeView` pauses via `activate`/`deactivate`, and
/// `WorkspaceStore.terminate()` calls `cancel()` as the window-close
/// backstop.
@MainActor
@Observable
final class FileTreeModel {
    private(set) var rootURL: URL?
    private(set) var rows: [FileTreeRow] = []
    /// True when the root itself can't be listed (deleted / unreadable).
    /// Recovers on the next `activate`/`setRoot`, or via the root watcher
    /// if the directory reappears at the same path.
    private(set) var rootError = false
    var selectedId: String?

    /// Listing cache, keyed by directory path. Retained across collapse so
    /// `flatten` has data, but every directory is re-listed at the moment it
    /// becomes visible again — kqueue only reports future changes, so a
    /// cache that sat hidden may be stale.
    private var childrenByDir: [String: [FileNode]] = [:]
    private var expandedDirs: Set<String> = []
    /// Expansion recency — newest last. Decides which directories keep their
    /// watcher when the `maxWatchedDirectories` cap bites.
    private var expansionOrder: [String] = []
    /// Expanded directories whose last listing threw; rendered as one
    /// placeholder row. Re-listing is retried whenever the dir is expanded
    /// again or its parent refreshes.
    private var failedDirs: Set<String> = []
    private var watchers: [String: DirectoryWatcher] = [:]
    /// False while the tree isn't showing (workspaces mode / sidebar hidden)
    /// — no watchers run and refreshes are skipped; caches survive.
    private var isActive = false

    /// Root + 63 most recently expanded directories. Keeps the fd budget
    /// trivial next to the default 256 soft limit; over-cap directories
    /// still refresh whenever they're re-listed on expansion.
    static let maxWatchedDirectories = 64

    /// Number of live kqueue watchers — exposed for tests.
    var watchedDirectoryCount: Int { watchers.count }

    /// Entering files mode (or the sidebar remounting). Re-lists the visible
    /// subtree to catch changes made while paused, then arms watchers.
    func activate(root: URL?) {
        isActive = true
        if rootURL?.path != root?.path {
            resetState(to: root)
        }
        relistVisibleSubtree()
        pruneUnreachable()
        syncWatchers()
        rebuildRows()
    }

    /// Leaving files mode (toggle back / sidebar hidden). Drops every
    /// watcher; caches and expansion survive so re-entry is instant.
    func deactivate() {
        isActive = false
        for watcher in watchers.values { watcher.cancel() }
        watchers.removeAll()
    }

    /// Full teardown for `WorkspaceStore.terminate()`.
    func cancel() {
        deactivate()
        resetState(to: nil)
        rows = []
    }

    /// Active-workspace switch or cwd drift. Same path is a no-op; a new
    /// path clears expansion/caches/selection and re-lists.
    func setRoot(_ url: URL?) {
        guard rootURL?.path != url?.path else { return }
        resetState(to: url)
        guard isActive else { return }
        relistVisibleSubtree()
        syncWatchers()
        rebuildRows()
    }

    func toggleExpanded(_ node: FileNode) {
        guard node.isDirectory else { return }
        let path = node.url.path
        if expandedDirs.contains(path) {
            expandedDirs.remove(path)
            expansionOrder.removeAll { $0 == path }
        } else {
            expandedDirs.insert(path)
            expansionOrder.removeAll { $0 == path }
            expansionOrder.append(path)
            // List this directory and any previously-expanded descendants
            // that just became visible again — their caches may be stale.
            relistVisibleSubtree(from: path)
            pruneUnreachable()
        }
        syncWatchers()
        rebuildRows()
    }

    /// Watcher callback (also driven directly by tests): shallow re-list of
    /// one directory, prune state for entries that vanished, rebuild rows.
    func refresh(dirPath: String) {
        guard isActive, let rootPath = rootURL?.path else { return }
        guard dirPath == rootPath || childrenByDir[dirPath] != nil || expandedDirs.contains(dirPath)
        else { return }
        listDirectory(dirPath)
        pruneUnreachable()
        syncWatchers()
        rebuildRows()
    }

    // MARK: Internals

    private func resetState(to url: URL?) {
        rootURL = url
        rootError = false
        selectedId = nil
        childrenByDir.removeAll()
        expandedDirs.removeAll()
        expansionOrder.removeAll()
        failedDirs.removeAll()
    }

    /// Shallow listing of one directory into the cache. Root failures set
    /// `rootError`; child failures land in `failedDirs`.
    private func listDirectory(_ path: String) {
        do {
            childrenByDir[path] = try FileTreeLister.children(of: URL(fileURLWithPath: path))
            failedDirs.remove(path)
            if path == rootURL?.path { rootError = false }
        } catch {
            childrenByDir.removeValue(forKey: path)
            if path == rootURL?.path {
                rootError = true
            } else {
                failedDirs.insert(path)
            }
        }
    }

    /// Re-lists `from` (default: the root) plus every expanded directory
    /// visible beneath it, outermost first so each level's listing feeds the
    /// walk into the next.
    private func relistVisibleSubtree(from start: String? = nil) {
        guard let rootPath = rootURL?.path else { return }
        let startPath = start ?? rootPath
        listDirectory(startPath)
        var stack: [String] = [startPath]
        while let dir = stack.popLast() {
            for child in childrenByDir[dir] ?? [] where child.isDirectory {
                let path = child.url.path
                if expandedDirs.contains(path) {
                    listDirectory(path)
                    stack.append(path)
                }
            }
        }
    }

    /// Drops cache/expansion/failure state for directories no longer
    /// reachable from the root through the current cache — a deleted
    /// subtree must not keep stale rows (or, via `syncWatchers`, fds) alive.
    private func pruneUnreachable() {
        guard let rootPath = rootURL?.path else {
            childrenByDir.removeAll()
            expandedDirs.removeAll()
            expansionOrder.removeAll()
            failedDirs.removeAll()
            return
        }
        var reachable: Set<String> = [rootPath]
        var stack: [String] = [rootPath]
        while let dir = stack.popLast() {
            for child in childrenByDir[dir] ?? [] where child.isDirectory {
                if reachable.insert(child.url.path).inserted {
                    stack.append(child.url.path)
                }
            }
        }
        childrenByDir = childrenByDir.filter { reachable.contains($0.key) }
        expandedDirs = expandedDirs.filter { reachable.contains($0) }
        expansionOrder = expansionOrder.filter { expandedDirs.contains($0) }
        failedDirs = failedDirs.filter { reachable.contains($0) }
    }

    /// Aligns live watchers with what's on screen: the root, plus the most
    /// recently expanded visible directories under the cap. `start()` is
    /// idempotent and retries a failed attach, so re-syncing also heals a
    /// watcher whose directory briefly disappeared.
    private func syncWatchers() {
        guard isActive, let rootPath = rootURL?.path else {
            for watcher in watchers.values { watcher.cancel() }
            watchers.removeAll()
            return
        }
        var desired: Set<String> = [rootPath]
        if !rootError {
            let visible = visiblyExpandedDirs()
            desired.formUnion(
                expansionOrder.reversed()
                    .filter { visible.contains($0) }
                    .prefix(Self.maxWatchedDirectories - 1)
            )
        }
        for (path, watcher) in watchers where !desired.contains(path) {
            watcher.cancel()
            watchers.removeValue(forKey: path)
        }
        for path in desired {
            if let existing = watchers[path] {
                existing.start()
            } else {
                let watcher = DirectoryWatcher(directory: URL(fileURLWithPath: path)) { [weak self] in
                    self?.refresh(dirPath: path)
                }
                watcher.start()
                watchers[path] = watcher
            }
        }
    }

    /// Expanded directories actually rendered right now — the walk only
    /// descends through expanded parents, so an expanded dir hidden under a
    /// collapsed ancestor doesn't count (and doesn't deserve a watcher).
    private func visiblyExpandedDirs() -> Set<String> {
        guard let rootPath = rootURL?.path else { return [] }
        var result: Set<String> = []
        var stack: [String] = [rootPath]
        while let dir = stack.popLast() {
            for child in childrenByDir[dir] ?? [] where child.isDirectory {
                let path = child.url.path
                if expandedDirs.contains(path) {
                    result.insert(path)
                    stack.append(path)
                }
            }
        }
        return result
    }

    private func rebuildRows() {
        guard let root = rootURL, !rootError else {
            if !rows.isEmpty { rows = [] }
            if selectedId != nil { selectedId = nil }
            return
        }
        let newRows = FileTreeLister.flatten(
            root: root,
            childrenByDir: childrenByDir,
            expandedDirs: expandedDirs,
            failedDirs: failedDirs
        )
        // Skip the assign when nothing changed — `.DS_Store` churn fires the
        // watcher even though the entry is filtered, and an equal-array set
        // would re-render every visible row.
        if newRows != rows { rows = newRows }
        if let selected = selectedId, !newRows.contains(where: { $0.id == selected }) {
            selectedId = nil
        }
    }
}
