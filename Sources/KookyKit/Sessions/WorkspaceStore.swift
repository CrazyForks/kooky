import Foundation

@MainActor
@Observable
final class WorkspaceStore {
    private(set) var workspaces: [Workspace] = []
    private(set) var activeWorkspaceId: UUID?

    /// Factory for the terminal engine backing each new tab. Tests inject a
    /// no-op engine to avoid pulling in libghostty / spawning a PTY.
    private let engineFactory: @MainActor () -> any TerminalEngine

    var active: Workspace? {
        workspaces.first { $0.id == activeWorkspaceId }
    }

    init(engineFactory: @escaping @MainActor () -> any TerminalEngine = { LibghosttyEngine() }) {
        self.engineFactory = engineFactory
        addWorkspace()
    }

    @discardableResult
    func addWorkspace(workingDirectory: URL? = nil, title: String? = nil) -> Workspace {
        // Default: inherit active workspace's current cwd (which itself tracks
        // the active tab's OSC 7 reports). Falls back to $HOME on first launch.
        let dir = workingDirectory
            ?? active?.workingDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let resolvedTitle = title ?? Self.defaultTitle(for: dir)
        let ws = Workspace(title: resolvedTitle, workingDirectory: dir)
        workspaces.append(ws)
        activeWorkspaceId = ws.id
        addTab(in: ws)
        return ws
    }

    func closeWorkspace(_ workspace: Workspace) {
        for tab in workspace.tabs { tab.engine.terminate() }
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces.remove(at: idx)
        guard !workspaces.isEmpty else {
            activeWorkspaceId = nil
            return
        }
        if activeWorkspaceId == workspace.id {
            let nextIdx = min(idx, workspaces.count - 1)
            activeWorkspaceId = workspaces[nextIdx].id
        }
    }

    func activateWorkspace(_ workspace: Workspace) {
        activeWorkspaceId = workspace.id
    }

    @discardableResult
    func addTab(in workspace: Workspace, template: AgentTemplate = .terminal) -> Session {
        let engine = engineFactory()
        var config = template.makeSessionConfig()
        config.workingDirectory = workspace.workingDirectory.path
        engine.start(config: config)
        let session = Session(engine: engine, currentDirectory: workspace.workingDirectory, agent: template)
        workspace.tabs.append(session)
        workspace.activeTabId = session.id
        // OSC 7 fires per chpwd. Guard against no-op writes so SwiftUI doesn't
        // churn observers when the path didn't actually change.
        engine.onPwdChange = { [weak session, weak workspace] pwd in
            guard let session else { return }
            let url = URL(fileURLWithPath: pwd)
            if session.currentDirectory.path != pwd {
                session.currentDirectory = url
            }
            if let workspace, workspace.activeTabId == session.id, workspace.workingDirectory.path != pwd {
                workspace.workingDirectory = url
            }
        }
        return session
    }

    func closeTab(_ session: Session, in workspace: Workspace) {
        session.engine.terminate()
        guard let idx = workspace.tabs.firstIndex(where: { $0.id == session.id }) else { return }
        workspace.tabs.remove(at: idx)
        if workspace.tabs.isEmpty {
            closeWorkspace(workspace)
            return
        }
        if workspace.activeTabId == session.id {
            let nextIdx = min(idx, workspace.tabs.count - 1)
            workspace.activeTabId = workspace.tabs[nextIdx].id
        }
    }

    func activateTab(_ session: Session, in workspace: Workspace) {
        workspace.activeTabId = session.id
        // Surface the activated tab's cwd to the workspace (and sidebar path).
        if workspace.workingDirectory != session.currentDirectory {
            workspace.workingDirectory = session.currentDirectory
        }
    }

    /// Last path component; "Home" when the dir is `$HOME` (reads nicer than "corey").
    private static func defaultTitle(for url: URL) -> String {
        if url.standardizedFileURL.path == NSHomeDirectory() { return "Home" }
        return url.lastPathComponent
    }
}
