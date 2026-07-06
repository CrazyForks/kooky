import XCTest
@testable import KookyKit

/// Pure listing / flatten / icon logic — nonisolated, no store or MainActor.
final class FileTreeListerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kooky-filetree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func touch(_ relative: String) {
        FileManager.default.createFile(
            atPath: tempRoot.appendingPathComponent(relative).path,
            contents: Data()
        )
    }

    private func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent(relative, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    /// Fixture node for the pure flatten/symbol tests — no filesystem behind it.
    private func node(_ path: String, isDirectory: Bool = false) -> FileNode {
        FileNode(
            url: URL(fileURLWithPath: path),
            name: (path as NSString).lastPathComponent,
            isDirectory: isDirectory,
            isSymlink: false
        )
    }

    // MARK: children(of:)

    func testChildrenSortsDirectoriesFirstThenNaturally() throws {
        touch("file10.txt")
        touch("file2.txt")
        touch("alpha")
        try mkdir("zebra-dir")
        try mkdir("beta-dir")
        let names = try FileTreeLister.children(of: tempRoot).map(\.name)
        // Directories lead; `file2` before `file10` is the natural-sort
        // (localizedStandardCompare) guarantee.
        XCTAssertEqual(names, ["beta-dir", "zebra-dir", "alpha", "file2.txt", "file10.txt"])
    }

    func testChildrenShowsDotfilesButHidesGitAndDSStore() throws {
        touch(".env")
        touch(".DS_Store")
        touch("readme.md")
        try mkdir(".git")
        let names = try FileTreeLister.children(of: tempRoot).map(\.name)
        XCTAssertEqual(Set(names), [".env", "readme.md"])
    }

    func testChildrenThrowsOnMissingDirectory() {
        let missing = tempRoot.appendingPathComponent("nope", isDirectory: true)
        XCTAssertThrowsError(try FileTreeLister.children(of: missing))
    }

    func testSymlinkToDirectoryIsNotExpandable() throws {
        // Expanding through links is what would make cycles representable —
        // a symlink must come back as a non-directory leaf.
        try mkdir("real")
        let link = tempRoot.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: tempRoot.appendingPathComponent("real", isDirectory: true)
        )
        let nodes = try FileTreeLister.children(of: tempRoot)
        let linkNode = try XCTUnwrap(nodes.first { $0.name == "link" })
        XCTAssertTrue(linkNode.isSymlink)
        XCTAssertFalse(linkNode.isDirectory)
    }

    // MARK: flatten

    func testFlattenWalksExpandedDirsDepthFirst() {
        let rows = FileTreeLister.flatten(
            root: URL(fileURLWithPath: "/root"),
            childrenByDir: [
                "/root": [node("/root/src", isDirectory: true), node("/root/a.txt")],
                "/root/src": [node("/root/src/main.swift")],
            ],
            expandedDirs: ["/root/src"],
            failedDirs: []
        )
        XCTAssertEqual(rows.map(\.id), ["/root/src", "/root/src/main.swift", "/root/a.txt"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
        XCTAssertEqual(rows.map(\.isExpanded), [true, false, false])
    }

    func testFlattenSkipsCollapsedSubtrees() {
        let rows = FileTreeLister.flatten(
            root: URL(fileURLWithPath: "/root"),
            childrenByDir: [
                "/root": [node("/root/src", isDirectory: true), node("/root/a.txt")],
                "/root/src": [node("/root/src/main.swift")],
            ],
            expandedDirs: [],
            failedDirs: []
        )
        XCTAssertEqual(rows.map(\.id), ["/root/src", "/root/a.txt"])
        XCTAssertEqual(rows.map(\.isExpanded), [false, false])
    }

    func testFlattenEmitsPlaceholderForFailedDir() {
        let rows = FileTreeLister.flatten(
            root: URL(fileURLWithPath: "/root"),
            childrenByDir: ["/root": [node("/root/locked", isDirectory: true)]],
            expandedDirs: ["/root/locked"],
            failedDirs: ["/root/locked"]
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].depth, 1)
        guard case .placeholder = rows[1].kind else {
            return XCTFail("expected a placeholder row under the failed dir")
        }
    }

    // MARK: symbolName

    func testSymbolNames() {
        XCTAssertEqual(FileTreeLister.symbolName(for: node("/d", isDirectory: true)), "folder.fill")
        XCTAssertEqual(FileTreeLister.symbolName(for: node("/x/shot.PNG")), "photo")
        XCTAssertEqual(FileTreeLister.symbolName(for: node("/x/main.swift")), "doc.text")
    }
}

/// Model behaviour against a real temp directory tree. Fixtures are built
/// per-test (not in `setUp`) — the nonisolated setUp/tearDown overrides
/// can't touch this @MainActor class's state or call `FileTreeModel()`,
/// same reason `WorkspaceStoreTests` builds stores inside test methods.
@MainActor
final class FileTreeModelTests: XCTestCase {
    /// Fresh on-disk tree (`root/src/main.swift`, `root/readme.md`) + model.
    /// Teardown cancels the model's watchers and removes the tree.
    private func makeFixture() throws -> (root: URL, src: URL, model: FileTreeModel) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kooky-filetreemodel-\(UUID().uuidString)", isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src.appendingPathComponent("main.swift").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("readme.md").path, contents: Data())
        let model = FileTreeModel()
        addTeardownBlock {
            await model.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        return (root, src, model)
    }

    private func entryNode(id: String, in model: FileTreeModel) throws -> FileNode {
        let row = try XCTUnwrap(model.rows.first { $0.id == id })
        guard case .entry(let node) = row.kind else {
            struct NotAnEntry: Error {}
            XCTFail("row \(id) is not an entry")
            throw NotAnEntry()
        }
        return node
    }

    func testActivateListsOnlyTopLevel() throws {
        let (root, src, model) = try makeFixture()
        model.activate(root: root)
        // Lazy: `src`'s contents stay unlisted until it's expanded.
        XCTAssertEqual(model.rows.map(\.id), [src.path, root.appendingPathComponent("readme.md").path])
        XCTAssertEqual(model.rows.map(\.depth), [0, 0])
    }

    func testExpandAndCollapse() throws {
        let (root, src, model) = try makeFixture()
        model.activate(root: root)
        let srcNode = try entryNode(id: src.path, in: model)

        model.toggleExpanded(srcNode)
        XCTAssertEqual(model.rows.map(\.depth), [0, 1, 0])
        XCTAssertEqual(model.rows[1].id, src.appendingPathComponent("main.swift").path)
        XCTAssertTrue(model.rows[0].isExpanded)

        model.toggleExpanded(srcNode)
        XCTAssertEqual(model.rows.map(\.depth), [0, 0])
        XCTAssertFalse(model.rows[0].isExpanded)
    }

    func testRefreshPicksUpExternalCreateAndDelete() throws {
        let (root, _, model) = try makeFixture()
        model.activate(root: root)

        FileManager.default.createFile(atPath: root.appendingPathComponent("new.txt").path, contents: Data())
        model.refresh(dirPath: root.path)
        XCTAssertTrue(model.rows.contains { $0.id == root.appendingPathComponent("new.txt").path })

        try FileManager.default.removeItem(at: root.appendingPathComponent("readme.md"))
        model.refresh(dirPath: root.path)
        XCTAssertFalse(model.rows.contains { $0.id == root.appendingPathComponent("readme.md").path })
    }

    func testDeletedExpandedSubtreeIsPrunedAndSelectionCleared() throws {
        let (root, src, model) = try makeFixture()
        model.activate(root: root)
        let srcNode = try entryNode(id: src.path, in: model)
        model.toggleExpanded(srcNode)
        model.selectedId = src.appendingPathComponent("main.swift").path

        try FileManager.default.removeItem(at: src)
        model.refresh(dirPath: root.path)

        XCTAssertEqual(model.rows.map(\.id), [root.appendingPathComponent("readme.md").path])
        XCTAssertNil(model.selectedId, "selection pointing into the deleted subtree must clear")
        XCTAssertEqual(model.watchedDirectoryCount, 1, "the deleted dir's watcher must drop; only the root remains")
    }

    func testSetRootResetsExpansionAndSelection() throws {
        let (root, src, model) = try makeFixture()
        model.activate(root: root)
        let srcNode = try entryNode(id: src.path, in: model)
        model.toggleExpanded(srcNode)
        model.selectedId = src.path

        let otherRoot = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: otherRoot.appendingPathComponent("only.txt").path, contents: Data())

        model.setRoot(otherRoot)
        XCTAssertEqual(model.rows.map(\.id), [otherRoot.appendingPathComponent("only.txt").path])
        XCTAssertNil(model.selectedId)

        // Same-path setRoot is a no-op.
        model.setRoot(otherRoot)
        XCTAssertEqual(model.rows.map(\.id), [otherRoot.appendingPathComponent("only.txt").path])
    }

    func testRootDeletionSetsRootErrorAndRecoversOnActivate() throws {
        let (root, _, model) = try makeFixture()
        model.activate(root: root)
        XCTAssertFalse(model.rootError)

        try FileManager.default.removeItem(at: root)
        model.refresh(dirPath: root.path)
        XCTAssertTrue(model.rootError)
        XCTAssertTrue(model.rows.isEmpty)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("back.txt").path, contents: Data())
        model.activate(root: root)
        XCTAssertFalse(model.rootError)
        XCTAssertEqual(model.rows.map(\.id), [root.appendingPathComponent("back.txt").path])
    }

    func testDeactivateDropsWatchersButKeepsExpansion() throws {
        let (root, src, model) = try makeFixture()
        model.activate(root: root)
        let srcNode = try entryNode(id: src.path, in: model)
        model.toggleExpanded(srcNode)
        XCTAssertEqual(model.watchedDirectoryCount, 2, "root + expanded src")

        model.deactivate()
        XCTAssertEqual(model.watchedDirectoryCount, 0)

        // Re-entry restores the same expanded view and re-arms watchers.
        model.activate(root: root)
        XCTAssertTrue(model.rows.contains { $0.id == src.appendingPathComponent("main.swift").path })
        XCTAssertEqual(model.watchedDirectoryCount, 2)
    }

    func testCancelClearsEverything() throws {
        let (root, src, model) = try makeFixture()
        model.activate(root: root)
        let srcNode = try entryNode(id: src.path, in: model)
        model.toggleExpanded(srcNode)

        model.cancel()
        XCTAssertEqual(model.watchedDirectoryCount, 0)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.rootURL)
    }

    /// One live kqueue round-trip: an external write must surface in `rows`
    /// through DirectoryWatcher's debounce without a manual `refresh` call.
    func testWatcherPicksUpExternalWrite() throws {
        let (root, _, model) = try makeFixture()
        model.activate(root: root)
        let liveFile = root.appendingPathComponent("live.txt")
        FileManager.default.createFile(atPath: liveFile.path, contents: Data())

        // Watcher fires on .main after ~200ms; spin the run loop generously
        // (slow CI) and bail as soon as the row lands.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !model.rows.contains(where: { $0.id == liveFile.path }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(model.rows.contains { $0.id == liveFile.path })
    }
}
