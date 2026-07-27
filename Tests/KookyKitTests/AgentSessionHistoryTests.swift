import XCTest
@testable import KookyKit

final class AgentSessionScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kooky-session-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Fixture helpers

    @discardableResult
    private func writeFile(_ name: String, in dir: URL, lines: [String], mtime: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        }
        return url
    }

    private var claudeRoot: URL { tempDir.appendingPathComponent("projects") }
    private var codexRoot: URL { tempDir.appendingPathComponent("sessions") }

    private func claudeUserLine(text: String, cwd: String = "/tmp/proj") -> String {
        #"{"type":"user","cwd":"\#(cwd)","timestamp":"2026-07-01T00:00:00Z","message":{"role":"user","content":"\#(text)"}}"#
    }

    // MARK: Claude parsing

    func testClaudeRecordPrefersLatestCustomTitle() throws {
        let dir = claudeRoot.appendingPathComponent("-tmp-proj")
        let file = try writeFile("\(UUID().uuidString).jsonl", in: dir, lines: [
            #"{"type":"custom-title","customTitle":"old name","sessionId":"x"}"#,
            claudeUserLine(text: "the first prompt"),
            #"{"type":"custom-title","customTitle":"new name","sessionId":"x"}"#,
        ])
        let record = try XCTUnwrap(AgentSessionScanner.claudeRecord(file: file, mtime: Date()))
        XCTAssertEqual(record.title, "new name")
        XCTAssertEqual(record.cwd.path, "/tmp/proj")
        XCTAssertEqual(record.agentId, AgentTemplate.claudeCodeID)
        XCTAssertEqual(record.conversationId, file.deletingPathExtension().lastPathComponent)
    }

    func testClaudeRecordFallsBackToSummaryThenUserText() throws {
        let dir = claudeRoot.appendingPathComponent("-tmp-proj")
        let withSummary = try writeFile("\(UUID().uuidString).jsonl", in: dir, lines: [
            #"{"type":"summary","summary":"compact summary"}"#,
            claudeUserLine(text: "raw prompt"),
        ])
        XCTAssertEqual(AgentSessionScanner.claudeRecord(file: withSummary, mtime: Date())?.title, "compact summary")

        let userOnly = try writeFile("\(UUID().uuidString).jsonl", in: dir, lines: [
            claudeUserLine(text: "raw prompt"),
        ])
        XCTAssertEqual(AgentSessionScanner.claudeRecord(file: userOnly, mtime: Date())?.title, "raw prompt")
    }

    func testClaudeRecordSkipsInjectedBlocksForTitle() throws {
        let dir = claudeRoot.appendingPathComponent("-tmp-proj")
        // Slash-command expansion, hook caveat, and a content-blocks message —
        // the first REAL prompt (block form) must win.
        let file = try writeFile("\(UUID().uuidString).jsonl", in: dir, lines: [
            claudeUserLine(text: "<command-name>/clear</command-name>"),
            claudeUserLine(text: "Caveat: the messages below were generated"),
            #"{"type":"user","cwd":"/tmp/proj","message":{"role":"user","content":[{"type":"text","text":"real question"}]}}"#,
        ])
        XCTAssertEqual(AgentSessionScanner.claudeRecord(file: file, mtime: Date())?.title, "real question")
    }

    func testClaudeRecordDropsSidechainAndCwdlessFiles() throws {
        let dir = claudeRoot.appendingPathComponent("-tmp-proj")
        let sidechain = try writeFile("\(UUID().uuidString).jsonl", in: dir, lines: [
            #"{"type":"user","isSidechain":true,"cwd":"/tmp/proj","message":{"role":"user","content":"sub work"}}"#,
        ])
        XCTAssertNil(AgentSessionScanner.claudeRecord(file: sidechain, mtime: Date()))

        let cwdless = try writeFile("\(UUID().uuidString).jsonl", in: dir, lines: [
            #"{"type":"summary","summary":"no user line at all"}"#,
        ])
        XCTAssertNil(AgentSessionScanner.claudeRecord(file: cwdless, mtime: Date()))
    }

    func testClaudeTitleIsFlattenedAndBounded() throws {
        let dir = claudeRoot.appendingPathComponent("-tmp-proj")
        let long = String(repeating: "x", count: 500)
        let file = try writeFile("\(UUID().uuidString).jsonl", in: dir, lines: [
            claudeUserLine(text: "line one\\nline two \(long)"),
        ])
        let title = try XCTUnwrap(AgentSessionScanner.claudeRecord(file: file, mtime: Date())?.title)
        XCTAssertFalse(title.contains("\n"), "interior newlines must not survive into composed UI strings")
        XCTAssertLessThanOrEqual(title.count, 160)
    }

    // MARK: Codex parsing

    func testCodexRecordParsesMetaAndUserMessage() throws {
        let dir = codexRoot.appendingPathComponent("2026/07/01")
        let file = try writeFile("rollout-2026-07-01T00-00-00-abc.jsonl", in: dir, lines: [
            #"{"timestamp":"2026-07-01T00:00:00Z","type":"session_meta","payload":{"id":"thread-123","cwd":"/tmp/proj"}}"#,
            #"{"timestamp":"2026-07-01T00:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>injected</environment_context>"}]}}"#,
            #"{"timestamp":"2026-07-01T00:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"fix the flaky test"}}"#,
        ])
        let record = try XCTUnwrap(AgentSessionScanner.codexRecord(file: file, mtime: Date()))
        XCTAssertEqual(record.agentId, AgentTemplate.codex.id)
        XCTAssertEqual(record.conversationId, "thread-123")
        XCTAssertEqual(record.cwd.path, "/tmp/proj")
        XCTAssertEqual(record.title, "fix the flaky test")
    }

    func testCodexRecordWithoutUserMessageIsUntitledButResumable() throws {
        let dir = codexRoot.appendingPathComponent("2026/07/01")
        let file = try writeFile("rollout-x.jsonl", in: dir, lines: [
            #"{"type":"session_meta","payload":{"id":"thread-9","cwd":"/tmp/proj"}}"#,
        ])
        let record = try XCTUnwrap(AgentSessionScanner.codexRecord(file: file, mtime: Date()))
        XCTAssertEqual(record.title, "")
        XCTAssertEqual(record.conversationId, "thread-9")
    }

    func testCodexRecordWithoutMetaIsDropped() throws {
        let dir = codexRoot.appendingPathComponent("2026/07/01")
        let corrupt = try writeFile("rollout-bad.jsonl", in: dir, lines: [
            "not json at all {{{",
        ])
        XCTAssertNil(AgentSessionScanner.codexRecord(file: corrupt, mtime: Date()))
    }

    // MARK: Directory walking, sorting, capping

    func testScanMergesSortedByActivityAndIgnoresForeignFiles() throws {
        let projDir = claudeRoot.appendingPathComponent("-tmp-proj")
        try writeFile("\(UUID().uuidString).jsonl", in: projDir,
                      lines: [claudeUserLine(text: "older claude")],
                      mtime: Date(timeIntervalSinceNow: -300))
        // Non-UUID filename (a stray jsonl) must not become a record.
        try writeFile("notes.jsonl", in: projDir,
                      lines: [claudeUserLine(text: "not a session")])
        try writeFile("rollout-a.jsonl", in: codexRoot.appendingPathComponent("2026/07/01"), lines: [
            #"{"type":"session_meta","payload":{"id":"t1","cwd":"/tmp/proj"}}"#,
            #"{"type":"event_msg","payload":{"type":"user_message","message":"newer codex"}}"#,
        ], mtime: Date(timeIntervalSinceNow: -60))

        let records = AgentSessionScanner.scan(claudeProjectsRoot: claudeRoot, codexSessionsRoot: codexRoot)
        XCTAssertEqual(records.map(\.title), ["newer codex", "older claude"])
    }

    func testScanCapsPerAgentByRecency() throws {
        let dir = claudeRoot.appendingPathComponent("-tmp-proj")
        let base = Date(timeIntervalSinceNow: -100_000)
        for i in 0..<(AgentSessionScanner.perAgentCap + 5) {
            try writeFile("\(UUID().uuidString).jsonl", in: dir,
                          lines: [claudeUserLine(text: "session \(i)")],
                          mtime: base.addingTimeInterval(Double(i)))
        }
        let records = AgentSessionScanner.scan(claudeProjectsRoot: claudeRoot, codexSessionsRoot: codexRoot)
        XCTAssertEqual(records.count, AgentSessionScanner.perAgentCap)
        // The cap keeps the NEWEST files — the oldest five fall off.
        XCTAssertEqual(records.first?.title, "session \(AgentSessionScanner.perAgentCap + 4)")
        XCTAssertFalse(records.contains { $0.title == "session 0" })
    }

    func testScanSurvivesMissingRoots() {
        let records = AgentSessionScanner.scan(
            claudeProjectsRoot: tempDir.appendingPathComponent("nope"),
            codexSessionsRoot: tempDir.appendingPathComponent("also-nope")
        )
        XCTAssertEqual(records, [])
    }

    // MARK: Relative time label

    func testRelativeActivityLabelTiers() {
        let now = Date()
        XCTAssertEqual(relativeActivityLabel(now.addingTimeInterval(-5), now: now), "now")
        XCTAssertEqual(relativeActivityLabel(now.addingTimeInterval(-120), now: now), "2m")
        XCTAssertEqual(relativeActivityLabel(now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(relativeActivityLabel(now.addingTimeInterval(-3 * 86_400), now: now), "3d")
        // Past a week it's a date, not a count.
        let old = relativeActivityLabel(now.addingTimeInterval(-30 * 86_400), now: now)
        XCTAssertFalse(old.hasSuffix("d"))
        XCTAssertFalse(old.isEmpty)
    }
}

@MainActor
final class AgentSessionResumeTests: XCTestCase {
    private func makeStore(resumeSetting: Bool) -> WorkspaceStore {
        WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { resumeSetting }
        )
    }

    private func makeRecord(agentId: String, cwd: URL) -> AgentSessionRecord {
        AgentSessionRecord(
            agentId: agentId,
            conversationId: "11111111-2222-3333-4444-555555555555",
            title: "old conversation",
            cwd: cwd,
            lastActivity: Date()
        )
    }

    func testResumeAgentSessionForcesResumePastDisabledSetting() throws {
        // The `agents.resumeConversations` setting only governs automatic
        // relaunch-time resume — a History click is explicit and must work
        // with the setting OFF.
        let store = makeStore(resumeSetting: false)
        store.addWorkspace(workingDirectory: FileManager.default.temporaryDirectory)
        let cwd = FileManager.default.temporaryDirectory
        let record = makeRecord(agentId: AgentTemplate.claudeCodeID, cwd: cwd)

        let session = try XCTUnwrap(store.resumeAgentSession(record))
        XCTAssertEqual(session.agent.id, AgentTemplate.claudeCodeID)
        XCTAssertEqual(session.conversationId, record.conversationId)
        XCTAssertEqual(session.resumedConversationId, record.conversationId,
                       "forceResume must bypass the resumeProvider gate")
        XCTAssertEqual(session.currentDirectory.standardizedFileURL, cwd.standardizedFileURL)
        XCTAssertEqual(store.active?.activeSession?.id, session.id, "resumed tab becomes active")
    }

    func testResumeAgentSessionAvoidsSSHWorkspaces() throws {
        // An SSH workspace would wrap the launch in kooky-ssh and drop the
        // resume id — the tab must land in a local workspace instead.
        let store = makeStore(resumeSetting: true)
        store.addWorkspace(workingDirectory: FileManager.default.temporaryDirectory, sshRemoteHost: "user@box")
        XCTAssertNotNil(store.active?.sshRemoteHost)

        let record = makeRecord(agentId: AgentTemplate.claudeCodeID, cwd: FileManager.default.temporaryDirectory)
        let session = try XCTUnwrap(store.resumeAgentSession(record))
        XCTAssertNil(store.active?.sshRemoteHost, "resumed tab must land in a local workspace")
        XCTAssertEqual(store.active?.activeSession?.id, session.id)
        XCTAssertEqual(session.resumedConversationId, record.conversationId)
    }

    func testResumeAgentSessionCreatesLocalWorkspaceWhenAllAreSSH() throws {
        // Codex review P2: with every workspace SSH, the old guard made a
        // history click a silent no-op. It must open a local workspace at
        // the conversation's directory instead.
        let store = makeStore(resumeSetting: true)
        let seed = store.active!
        store.addWorkspace(workingDirectory: FileManager.default.temporaryDirectory, sshRemoteHost: "user@box")
        store.closeWorkspace(seed)
        XCTAssertTrue(store.workspaces.allSatisfy { $0.sshRemoteHost != nil })

        let cwd = FileManager.default.temporaryDirectory
        let record = makeRecord(agentId: AgentTemplate.claudeCodeID, cwd: cwd)
        let session = try XCTUnwrap(store.resumeAgentSession(record))
        let landed = try XCTUnwrap(store.active)
        XCTAssertNil(landed.sshRemoteHost)
        XCTAssertEqual(landed.workingDirectory.standardizedFileURL, cwd.standardizedFileURL)
        XCTAssertEqual(session.resumedConversationId, record.conversationId)
    }

    func testResumeAgentSessionRejectsUnknownAgent() {
        let store = makeStore(resumeSetting: true)
        store.addWorkspace(workingDirectory: FileManager.default.temporaryDirectory)
        let record = makeRecord(agentId: "no-such-agent", cwd: FileManager.default.temporaryDirectory)
        XCTAssertNil(store.resumeAgentSession(record))
    }

    func testResumedConversationIdMirrorsTheSSHDrop() {
        // makeSessionConfig drops the LOCAL resume id for an SSH spawn —
        // the recorded field must say nil too, or downstream consumers
        // (Codex usage monitor) would hunt for a rollout that was never
        // resumed locally.
        let store = makeStore(resumeSetting: true)
        store.addWorkspace(workingDirectory: FileManager.default.temporaryDirectory, sshRemoteHost: "user@box")
        let session = store.addTab(
            in: store.active!,
            template: .claudeCode,
            conversationId: "11111111-2222-3333-4444-555555555555"
        )
        XCTAssertNil(session.resumedConversationId)
        XCTAssertEqual(session.conversationId, "11111111-2222-3333-4444-555555555555",
                       "the persisted id survives — only the spawn-time resume is dropped")
    }

    func testAutomaticResumeStaysGatedBySetting() {
        // Pin the pre-existing contract: WITHOUT forceResume, a disabled
        // setting still suppresses the resume argument (the id persists).
        let store = makeStore(resumeSetting: false)
        store.addWorkspace(workingDirectory: FileManager.default.temporaryDirectory)
        let workspace = store.active!
        let session = store.addTab(
            in: workspace,
            template: .claudeCode,
            conversationId: "11111111-2222-3333-4444-555555555555"
        )
        XCTAssertEqual(session.conversationId, "11111111-2222-3333-4444-555555555555")
        XCTAssertNil(session.resumedConversationId)
    }

    func testRightSidebarContentPersistsAndRestores() throws {
        let persistence = InMemoryPersistence()
        let store = WorkspaceStore(persistence: persistence, engineFactory: { TestEngine() })
        store.addWorkspace(workingDirectory: FileManager.default.temporaryDirectory)
        store.setRightSidebarContent(.history)
        store.flushPersistence()
        XCTAssertEqual(persistence.saved?.rightSidebarContent, .history)

        let restored = WorkspaceStore(
            persistence: InMemoryPersistence(initial: persistence.saved),
            engineFactory: { TestEngine() }
        )
        XCTAssertEqual(restored.rightSidebarContent, .history)
    }
}
