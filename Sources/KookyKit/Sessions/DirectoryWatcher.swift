import Darwin
import Foundation

/// kqueue watcher on a single directory. Fires `onChange` (debounced ~200ms)
/// when entries are created, deleted, or renamed inside it — a directory's
/// vnode gets a `.write` event whenever its entry list mutates — and when the
/// directory itself is deleted or renamed. The generic sibling of
/// `GitWatcher`, which is hardwired to `.git/HEAD` + `.git/index`; the
/// sidebar file tree keeps one of these per visible (root or expanded)
/// directory.
@MainActor
final class DirectoryWatcher {
    let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var pendingRefresh: DispatchWorkItem?
    /// Set by `cancel()` so the deferred re-attach (below) can't resurrect a
    /// watcher the owner already dropped — that fd would leak with nobody
    /// left to close it. GitWatcher gets the same guard from its
    /// `watchedCwd` nil-check.
    private var isCancelled = false
    private let onChange: () -> Void

    init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }
    // No deinit cleanup — `@MainActor` deinits run nonisolated in Swift 6, and
    // the project convention (see GitWatcher) is to require explicit teardown.
    // Callers MUST invoke `cancel()` before dropping the watcher, or kqueue
    // fds leak.

    /// Idempotent for a live watcher; the rebuild path (after the directory
    /// was atomically replaced) falls through because `source` is nil there.
    func start() {
        guard source == nil else { return }
        isCancelled = false
        attach()
    }

    func cancel() {
        isCancelled = true
        source?.cancel()
        source = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    private func attach() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let data = src.data
            self.scheduleRefresh()
            // `.delete`/`.rename` mean our fd's vnode is going away (rm -r,
            // mv, or an atomic directory swap). Drop the source and try to
            // re-attach to whatever now sits at the same path — if nothing
            // does, the debounced `onChange` we just scheduled lets the model
            // discover the loss through a failed re-list.
            if data.contains(.delete) || data.contains(.rename) {
                self.source?.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self, !self.isCancelled, self.source == nil else { return }
                    self.attach()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleRefresh() {
        // Bulk operations (git checkout, npm install, rm -r) touch a
        // directory many times in quick succession; coalesce into one
        // re-list.
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
