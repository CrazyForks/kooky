import SwiftUI

/// Active-tab details for the right sidebar. The view reads the store's
/// active workspace, pane, and session directly so switching any of them
/// replaces the page immediately without a second selection model.
struct SessionInfoView: View {
    let store: WorkspaceStore

    /// Polled, not observed — see `processPolling`. Owned here rather than in
    /// `ProcessesSection` because that section renders nothing until the first
    /// scan lands, and a view whose first frame is empty cannot be trusted to
    /// receive the appearance callback that would start the scan.
    @State private var processes: [SessionProcess] = []

    /// Slow enough to be free, fast enough that a command you just started
    /// shows up before you go looking for it.
    private static let processPollInterval = Duration.seconds(2)

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: "session info", count: 0)
            if let workspace = store.active,
               let session = workspace.activeSession {
                // The identity row is pinned above the scroll area, not inside
                // it: an inspector must keep saying whose data this is while
                // the fields scroll.
                identityRow(session)
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                fields(session: session, workspace: workspace)
            } else {
                PanelEmptyState(symbol: "info.circle", message: "no active session")
                Spacer(minLength: 0)
            }
        }
    }

    /// Deliberately the same shape as an `AgentOverviewRow`: icon, title, then
    /// one muted line carrying the agent and its state. Landing here from the
    /// agents list should read as that row expanded, not as another component.
    private func identityRow(_ session: Session) -> some View {
        let state = AgentMonitor.state(of: session)
        // The agents row's shared word color, so an idle tab reads the same
        // weight here as it does there; the dot takes the word's color so the
        // pair reads as one mark.
        let accent = agentStateWordColor(state)
        return HStack(spacing: 10) {
            AgentIconView(
                asset: session.displayAgent.iconAsset,
                fallbackSymbol: session.displayAgent.symbol,
                size: 16
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.title)
                    .font(SessionInfo.titleFont)
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(verbatim: session.displayAgent.title)
                        .font(SessionInfo.labelFont)
                        .foregroundStyle(SessionInfo.labelText)
                        .lineLimit(1)
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                    Text(state.label)
                        .font(SessionInfo.stateFont)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SessionInfo.gutter)
        .padding(.vertical, Theme.sidebarRowVerticalPadding)
        .help(session.title)
    }

    private func fields(session: Session, workspace: Workspace) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SessionInfoSection(title: "Context", store: store) {
                    InlineField(label: "Workspace", value: workspace.title)
                    BlockField(label: "Directory", value: abbreviatedPath(session.currentDirectory.path))
                    if let remote = session.effectiveRemoteHost {
                        InlineField(label: "Remote", value: remote)
                    }
                }

                if hasSourceInfo(session: session, workspace: workspace) {
                    SessionInfoSection(title: "Source", store: store) {
                        if let branch = session.gitStatus.branch {
                            InlineField(label: "Git branch", value: branch)
                        }
                        if let repoRoot = visibleRepoRoot(session) {
                            BlockField(label: "Git repo", value: abbreviatedPath(repoRoot))
                        }
                        if session.gitStatus.filesChanged > 0 {
                            GitDiffField(status: session.gitStatus)
                        }
                        // A worktree's branch and path already show above; what
                        // nothing else on this page says is that it IS one, and
                        // which workspace it was cut from.
                        if let parent = worktreeParent(of: workspace) {
                            InlineField(label: "Worktree of", value: parent.title)
                        }
                    }
                }

                if !session.environment.isEmpty {
                    SessionInfoSection(title: "Environment", store: store) {
                        if let python = session.environment.pythonVenv {
                            InlineField(label: "Python venv", value: python)
                        }
                        if let node = session.environment.nodeVersion {
                            InlineField(label: "Node version", value: node)
                        }
                        if let proxy = session.environment.proxy {
                            InlineField(label: "Proxy", value: proxy.summary)
                        }
                    }
                }

                if !processes.isEmpty {
                    SessionInfoSection(title: SessionInfo.processesTitle, store: store) {
                        ForEach(processes) { ProcessRow(process: $0) }
                    }
                }

                if hasRuntimeInfo(session) {
                    SessionInfoSection(title: "Runtime", store: store) {
                        if let completed = session.lastCompletedCommand {
                            LastCommandField(completed: completed)
                        }
                        if let title = visibleTerminalTitle(session) {
                            BlockField(label: "Terminal title", value: title)
                        }
                    }
                }

                // No Identifiers section: `session.id` is only ever
                // `KOOKY_SURFACE_ID` for hook routing — nothing in kooky
                // accepts one, nothing logs one, and the shell already exposes
                // it. `conversationId`'s one real use (reaching the transcript
                // file, or resuming outside kooky) wants an action, not a UUID
                // to hand-select.
            }
            .padding(.bottom, Theme.space5)
        }
        // Anchored on the scroll view, which always has content: this is the
        // one thing on the page that no observation can drive
        // (`engine.foregroundPid` reads libghostty through a
        // non-`@Observable` engine and no kernel signal reaches SwiftUI), so
        // if this task fails to start there is no second chance. `id:` restarts
        // it on a tab switch; unmounting the page cancels it, so nothing polls
        // while another panel page is up.
        .task(id: session.id) {
            while !Task.isCancelled {
                // Skip the walk while the section is collapsed — the rows
                // aren't rendered, and the stale snapshot keeps the section
                // mounted. Re-checked per tick, so expanding recovers within
                // one poll interval.
                if !store.collapsedInfoSections.contains(SessionInfo.processesTitle) {
                    // Off the main thread: the port walk costs one socket-info
                    // call per socket fd, which on a connection-heavy child
                    // (an agent with MCP servers, a loaded dev server)
                    // reaches milliseconds — a poll must never cost a frame.
                    let pid = session.engine.foregroundPid ?? 0
                    let scanned = await Task.detached {
                        SessionProcessScanner.scan(foregroundPid: pid)
                    }.value
                    // A detached task doesn't inherit cancellation: a tab
                    // switch mid-scan restarts this loop for the NEW session,
                    // and the old scan would land afterwards, overwriting the
                    // new tab's rows with the old tab's until the next tick.
                    if !Task.isCancelled, scanned != processes { processes = scanned }
                }
                try? await Task.sleep(for: Self.processPollInterval)
            }
        }
    }

    private func hasSourceInfo(session: Session, workspace: Workspace) -> Bool {
        SessionInfoRules.hasSourceInfo(session: session, worktreeParent: worktreeParent(of: workspace))
    }

    private func hasRuntimeInfo(_ session: Session) -> Bool {
        SessionInfoRules.hasRuntimeInfo(session)
    }

    private func visibleRepoRoot(_ session: Session) -> String? {
        SessionInfoRules.visibleRepoRoot(session)
    }

    private func visibleTerminalTitle(_ session: Session) -> String? {
        SessionInfoRules.visibleTerminalTitle(session)
    }

    private func worktreeParent(of workspace: Workspace) -> Workspace? {
        guard let parentId = workspace.worktreeParentId else { return nil }
        return store.workspaces.first { $0.id == parentId }
    }

    private func abbreviatedPath(_ path: String) -> String {
        SessionInfoRules.abbreviatedPath(path)
    }
}

// MARK: - Row visibility

/// Which rows a session actually has something to say in.
///
/// A section's gate MUST be the OR of exactly the predicates its rows use.
/// They were written twice once, drifted, and shipped a `Runtime` heading with
/// nothing under it: the row hid a terminal title identical to the one the
/// identity row already showed, while the gate only checked that a title
/// existed. Deriving each row's visibility once, here, is what makes the two
/// impossible to disagree — and puts them somewhere a test can reach.
@MainActor
enum SessionInfoRules {
    static func hasSourceInfo(session: Session, worktreeParent: Workspace?) -> Bool {
        session.gitStatus.branch != nil
            || visibleRepoRoot(session) != nil
            || session.gitStatus.filesChanged > 0
            || worktreeParent != nil
    }

    static func hasRuntimeInfo(_ session: Session) -> Bool {
        session.lastCompletedCommand != nil || visibleTerminalTitle(session) != nil
    }

    /// Suppressed when it's the directory shown above — a tab sitting at the
    /// repo root would otherwise print the same path twice.
    static func visibleRepoRoot(_ session: Session) -> String? {
        guard let repoRoot = session.gitStatus.repoRoot,
              !isSameDirectory(repoRoot, session.currentDirectory.path)
        else { return nil }
        return repoRoot
    }

    /// Suppressed when it's what the identity row already shows: `Session.title`
    /// falls through to `terminalTitle`, so without a rename this would repeat
    /// the top of the page word for word.
    static func visibleTerminalTitle(_ session: Session) -> String? {
        guard let title = nonEmpty(session.terminalTitle), title != session.title else { return nil }
        return title
    }

    static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// "Blank means absent" is `normalizedTitle`'s one rule — this is just
    /// its optional-taking spelling, not a second implementation.
    static func nonEmpty(_ value: String?) -> String? {
        value.flatMap(normalizedTitle)
    }

    private static func isSameDirectory(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path
            == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }
}

// MARK: - Section

/// Disclosure header + rows. The header is the app's existing category-label
/// treatment (uppercase mono, tracked, muted — the same one the sheets' status
/// labels and the Codex plan badge use), which separates it from a field label
/// by LETTERFORM, not just by weight. `.textCase` rather than uppercase keys so
/// the Chinese strings pass through untouched.
///
/// Collapse state lives on the store, not in `@State`: the page unmounts every
/// time the panel switches, and this view would otherwise forget it instantly.
private struct SessionInfoSection<Content: View>: View {
    let title: String
    let store: WorkspaceStore
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    private var isExpanded: Bool { !store.collapsedInfoSections.contains(title) }

    var body: some View {
        VStack(alignment: .leading, spacing: SessionInfo.rowSpacing) {
            Button {
                withAnimation(Theme.chromeTransition) { store.toggleInfoSection(title) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 8)
                    Text(LocalizedStringKey(title), bundle: .kookyResources)
                        .font(SessionInfo.sectionFont)
                        .textCase(.uppercase)
                        .tracking(SessionInfo.sectionTracking)
                        .fixedSize()
                    Rectangle()
                        .fill(Theme.chromeHairline)
                        .frame(height: 1)
                }
                .foregroundStyle(isHovered ? Theme.chromeForeground : SessionInfo.sectionText)
                .frame(height: SessionInfo.sectionHeaderHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(SectionDisclosureStyle())
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(alignment: .leading, spacing: SessionInfo.rowSpacing) {
                    content()
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, SessionInfo.gutter)
        .padding(.top, SessionInfo.sectionGap)
    }
}

/// Plain button with a pressed state — `.plain` alone gives a disclosure
/// header no press feedback at all.
private struct SectionDisclosureStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
    }
}

// MARK: - Processes

/// One process on the session's terminal, shell at depth 0.
private struct ProcessRow: View {
    let process: SessionProcess

    var body: some View {
        HStack(spacing: 6) {
            // Fixed marker column outside the indent, so nesting reads off one
            // straight edge instead of stepping with the dot.
            Circle()
                .fill(process.isForeground ? Theme.activityRunning : .clear)
                .frame(width: 4, height: 4)
            Text(verbatim: process.name)
                .font(SessionInfo.valueFont)
                .foregroundStyle(
                    process.isForeground
                        ? Theme.chromeForeground
                        : Theme.chromeForeground.opacity(0.7)
                )
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, CGFloat(process.depth) * 6)
            if !process.ports.isEmpty {
                // "which port did my dev server take" — worth keeping whole,
                // so the NAME truncates first when the row runs out of room.
                Text(verbatim: process.ports.map { ":\($0)" }.joined(separator: " "))
                    .font(SessionInfo.labelFont)
                    .foregroundStyle(SessionInfo.labelText)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 8)
            Text(verbatim: "\(process.pid)")
                .font(SessionInfo.labelFont)
                .foregroundStyle(SessionInfo.labelText)
        }
    }
}

// MARK: - Fields

/// Label left, value right. For values short enough to sit beside their label —
/// everything except paths and identifiers, which get `BlockField`.
private struct InlineField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            FieldLabel(label)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(SessionInfo.valueFont)
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .help(value)
        }
    }
}

/// Label above a full-width value. For paths and identifiers: they need the
/// width, and they're what a user selects to copy.
private struct BlockField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SessionInfo.labelGap) {
            FieldLabel(label)
            Text(verbatim: value)
                .font(SessionInfo.valueFont)
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .help(value)
        }
    }
}

/// Reads exactly like the status bar's diff pill — file count first and muted
/// (it's a count, not a delta), then the shared `+X −Y` badge, the same
/// primitive the pill and the file-tree rows use. One diff vocabulary app-wide,
/// including the binary/mode-only `±` fallback.
private struct GitDiffField: View {
    let status: GitStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            FieldLabel("Git diff")
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(status.filesChanged)")
                    .font(SessionInfo.valueFont)
                    .foregroundStyle(Theme.chromeMuted)
                DiffCountBadge(
                    insertions: status.insertions,
                    deletions: status.deletions,
                    fontSize: SessionInfo.valueSize
                )
            }
        }
    }
}

/// The page's one raised surface, and it reuses the history search field's
/// treatment (`chromeHover`, radius 6) rather than inventing a card: this is
/// literal terminal content quoted back, so it earns a surface of its own.
private struct LastCommandField: View {
    let completed: Session.CompletedCommand

    private var command: String? { completed.text }
    private var failed: Bool { completed.exit != 0 }
    private var statusColor: Color { failed ? Theme.activityFailure : Theme.gitInsertion }

    var body: some View {
        VStack(alignment: .leading, spacing: SessionInfo.labelGap) {
            FieldLabel("Last command")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "$")
                        .foregroundStyle(Theme.chromeMuted)
                    commandText
                }
                .font(SessionInfo.valueFont)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 4, height: 4)
                    Text(
                        LocalizedStringKey(failed ? "failed" : "succeeded"),
                        bundle: .kookyResources
                    )
                    .foregroundStyle(statusColor)
                    Text(verbatim: "·")
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "exit %d", bundle: .kookyResources),
                            completed.exit
                        )
                    )
                    Text(verbatim: "·")
                    Text(verbatim: TabBarItem.formatDuration(completed.duration))
                    Spacer(minLength: 0)
                }
                .font(SessionInfo.stateFont)
                .foregroundStyle(SessionInfo.labelText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chromeHover)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// `—` when the shell never reported the text: a remote command, or a
    /// result that arrived before the session's first `CommandMarker`.
    @ViewBuilder
    private var commandText: some View {
        let text = Text(verbatim: command ?? "—")
            .foregroundStyle(command == nil ? Theme.chromeMuted : Theme.chromeForeground)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let command {
            text.help(command)
        } else {
            text
        }
    }
}

private struct FieldLabel: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(LocalizedStringKey(key), bundle: .kookyResources)
            .font(SessionInfo.labelFont)
            .foregroundStyle(SessionInfo.labelText)
    }
}

// MARK: - Design contract

/// Typography and spacing for the 230pt Session Info inspector.
///
/// Three text classes, and they must never be confusable:
///
/// | class   | size      | case      | color        |
/// |---------|-----------|-----------|--------------|
/// | SECTION | 9 medium  | UPPER +tr | muted 0.7    |
/// | label   | 10        | Sentence  | muted 0.8    |
/// | value   | 11        | —         | foreground   |
///
/// Every size is one the app already uses: 12 medium and 10 are the agent /
/// history row's two lines, 11 is the search field, 9.5 medium is the agents
/// list's state word, and 9 medium + tracking is the sheets' status label. An
/// inspector with its own scale would read as a different app one footer click
/// away, so additions take one of these roles instead of a new size at the
/// call site.
///
/// Spacing is a 3 : 11 : 24 rhythm — inside a field, between fields, between
/// sections. The jumps are what keep five groups of dense mono from reading as
/// one block; shrink the outer one and the page closes up again.
@MainActor
private enum SessionInfo {
    /// Matches `RightPanelHeader` and every right-panel row, so the whole
    /// column shares one left edge.
    static let gutter: CGFloat = 14

    /// Section title doubling as its collapse key — named because the poll
    /// loop checks it to skip scanning while the section is collapsed.
    static let processesTitle = "Processes"

    static let valueSize: CGFloat = 11

    static var titleFont: Font { Theme.mono(12, weight: .medium) }
    static var sectionFont: Font { Theme.mono(9, weight: .medium) }
    static var valueFont: Font { Theme.mono(valueSize) }
    static var labelFont: Font { Theme.mono(10) }
    static var stateFont: Font { Theme.mono(9.5, weight: .medium) }

    static let sectionTracking: CGFloat = 1.2
    static var sectionText: Color { Theme.chromeMuted.opacity(0.7) }
    static var labelText: Color { Theme.chromeMuted.opacity(0.8) }

    static let sectionHeaderHeight: CGFloat = 16
    static let sectionGap = Theme.space5
    static let rowSpacing: CGFloat = 11
    static let labelGap: CGFloat = 3
}
