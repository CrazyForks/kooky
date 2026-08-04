import XCTest
@testable import KookyKit

/// The invariant these all serve: a section's gate is true only when at least
/// one of its rows is. A gate that outlives its rows renders a heading with
/// nothing under it, which shipped once.
@MainActor
final class SessionInfoRulesTests: XCTestCase {
    private var store: WorkspaceStore!
    private var workspace: Workspace!
    private var session: Session!

    override func setUp() async throws {
        try await super.setUp()
        store = WorkspaceStore(persistence: InMemoryPersistence(), engineFactory: { TestEngine() })
        workspace = store.addWorkspace(workingDirectory: URL(fileURLWithPath: "/tmp/project"))
        session = store.addTab(in: workspace, template: .terminal)
    }

    // MARK: Terminal title

    /// Without a rename `Session.title` IS `terminalTitle`, so the row would
    /// repeat the identity line at the top of the page.
    func testTerminalTitleHiddenWhenItIsAlreadyTheSessionTitle() {
        session.terminalTitle = "vim README.md"
        XCTAssertEqual(session.title, "vim README.md", "precondition: title falls through")

        XCTAssertNil(SessionInfoRules.visibleTerminalTitle(session))
        XCTAssertFalse(
            SessionInfoRules.hasRuntimeInfo(session),
            "the gate must fall with its only row — this is the empty-heading bug"
        )
    }

    func testTerminalTitleShownOnceARenameHidesIt() {
        session.terminalTitle = "vim README.md"
        session.customTitle = "notes"

        XCTAssertEqual(SessionInfoRules.visibleTerminalTitle(session), "vim README.md")
        XCTAssertTrue(SessionInfoRules.hasRuntimeInfo(session))
    }

    func testBlankTerminalTitleIsNotARow() {
        session.terminalTitle = "   "
        session.customTitle = "notes"
        XCTAssertNil(SessionInfoRules.visibleTerminalTitle(session))
        XCTAssertFalse(SessionInfoRules.hasRuntimeInfo(session))
    }

    func testRuntimeSurvivesOnACompletedCommandAlone() {
        session.lastCompletedCommand = .init(text: "ls", exit: 0, duration: 0.1)
        XCTAssertTrue(SessionInfoRules.hasRuntimeInfo(session))
    }

    /// The red-dot pair is cleared on input; the inspector's gate must NOT
    /// read it, or the Runtime section vanishes on the first keystroke.
    func testRuntimeIgnoresTheClearedRedDotPair() {
        session.lastCompletedCommand = .init(text: "ls", exit: 0, duration: 0.1)
        session.lastCommandExit = nil
        session.lastCommandText = nil
        XCTAssertTrue(SessionInfoRules.hasRuntimeInfo(session))
    }

    // MARK: Repo root

    func testRepoRootHiddenWhenItIsTheCurrentDirectory() {
        session.currentDirectory = URL(fileURLWithPath: "/tmp/project")
        session.gitStatus = GitStatus(
            branch: nil, repoRoot: "/tmp/project", filesChanged: 0, insertions: 0, deletions: 0
        )

        XCTAssertNil(SessionInfoRules.visibleRepoRoot(session))
        XCTAssertFalse(
            SessionInfoRules.hasSourceInfo(session: session, worktreeParent: nil),
            "repo root alone, and it's the directory above — nothing left to show"
        )
    }

    /// Trailing slashes and `..` must not read as a different directory.
    func testRepoRootComparisonIsPathNormalised() {
        session.currentDirectory = URL(fileURLWithPath: "/tmp/project")
        session.gitStatus = GitStatus(
            branch: nil, repoRoot: "/tmp/sub/../project/", filesChanged: 0, insertions: 0, deletions: 0
        )
        XCTAssertNil(SessionInfoRules.visibleRepoRoot(session))
    }

    func testRepoRootShownFromASubdirectory() {
        session.currentDirectory = URL(fileURLWithPath: "/tmp/project/Sources")
        session.gitStatus = GitStatus(
            branch: "main", repoRoot: "/tmp/project", filesChanged: 0, insertions: 0, deletions: 0
        )

        XCTAssertEqual(SessionInfoRules.visibleRepoRoot(session), "/tmp/project")
        XCTAssertTrue(SessionInfoRules.hasSourceInfo(session: session, worktreeParent: nil))
    }

    func testSourceSurvivesOnBranchOrDiffOrWorktreeAlone() {
        session.gitStatus = GitStatus(
            branch: "main", repoRoot: nil, filesChanged: 0, insertions: 0, deletions: 0
        )
        XCTAssertTrue(SessionInfoRules.hasSourceInfo(session: session, worktreeParent: nil))

        session.gitStatus = GitStatus(
            branch: nil, repoRoot: nil, filesChanged: 2, insertions: 5, deletions: 1
        )
        XCTAssertTrue(SessionInfoRules.hasSourceInfo(session: session, worktreeParent: nil))

        session.gitStatus = .empty
        XCTAssertFalse(SessionInfoRules.hasSourceInfo(session: session, worktreeParent: nil))
        XCTAssertTrue(SessionInfoRules.hasSourceInfo(session: session, worktreeParent: workspace))
    }

    // MARK: Helpers

    func testNonEmptyTrimsAndRejectsWhitespace() {
        XCTAssertEqual(SessionInfoRules.nonEmpty("  main  "), "main")
        XCTAssertNil(SessionInfoRules.nonEmpty("  \n "))
        XCTAssertNil(SessionInfoRules.nonEmpty(nil))
    }

    func testAbbreviatedPathUsesTilde() {
        let home = NSHomeDirectory()
        XCTAssertEqual(SessionInfoRules.abbreviatedPath("\(home)/Github"), "~/Github")
        XCTAssertEqual(SessionInfoRules.abbreviatedPath("/tmp/project"), "/tmp/project")
    }
}
