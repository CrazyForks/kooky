import Foundation
import Observation
import SwiftUI

// MARK: - Record

/// One resumable conversation found on disk — the unit the right sidebar's
/// History list renders. Built by `AgentSessionScanner` from each agent's own
/// session store, NOT from kooky's persistence: that's the point — sessions
/// started outside kooky (or in tabs long closed) are still listed, and no
/// hook-side id capture is needed because the id is already in the file.
struct AgentSessionRecord: Identifiable, Hashable, Sendable {
    /// Builtin `AgentTemplate` id ("claude-code" / "codex").
    let agentId: String
    let conversationId: String
    /// Best-effort display title; empty when nothing usable was found
    /// (the UI shows a placeholder — the record is still resumable).
    let title: String
    /// The directory the conversation ran in. Resume respawns here so the
    /// conversation's file references stay valid.
    let cwd: URL
    /// Session file's modification date — "when this conversation last moved".
    let lastActivity: Date

    var id: String { "\(agentId):\(conversationId)" }
}

// MARK: - Scanner

/// Reads agent session stores off the main actor. Every format here is a
/// private implementation detail of its agent with no stability promise, so
/// parsing is defensive throughout: a line that doesn't parse is skipped, a
/// file that yields no id/cwd is dropped, and only file HEADS are read — a
/// session transcript can be tens of MB, but everything the list needs
/// (title, cwd, id) lives in the first lines.
enum AgentSessionScanner {
    /// The agents whose session stores this scanner reads. Single source for
    /// the History view's filter chips and the README table's session-history
    /// column guard test — extend it alongside a new `scan` branch.
    static let supportedAgentIds: [String] = [AgentTemplate.claudeCodeID, AgentTemplate.codex.id]
    /// Head bytes per file. Big enough to clear oversized leading lines
    /// (Codex `session_meta` carries the whole base_instructions blob, which
    /// alone can pass 64KB — the M5.iiii lesson) while keeping a 300-file
    /// scan cheap.
    static let headByteLimit = 262_144
    /// Per-agent record cap. Files are stat'd and mtime-sorted BEFORE any
    /// content is read, so the cap bounds parsing work, not just list length.
    static let perAgentCap = 150

    static func scan(claudeProjectsRoot: URL, codexSessionsRoot: URL) -> [AgentSessionRecord] {
        let claude = scanStore(files: claudeSessionFiles(under: claudeProjectsRoot), parse: claudeRecord)
        let codex = scanStore(files: codexRolloutFiles(under: codexSessionsRoot), parse: codexRecord)
        return (claude + codex).sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func scanStore(
        files: [(url: URL, mtime: Date)],
        parse: (URL, Date) -> AgentSessionRecord?
    ) -> [AgentSessionRecord] {
        files
            .sorted { $0.mtime > $1.mtime }
            .prefix(perAgentCap)
            .compactMap { parse($0.url, $0.mtime) }
    }

    // MARK: Claude Code (~/.claude/projects/<munged-cwd>/<uuid>.jsonl)

    private static func claudeSessionFiles(under root: URL) -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return projects.flatMap { project -> [(url: URL, mtime: Date)] in
            guard let files = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return [] }
            return files.compactMap { file in
                // Session files sit next to same-named checkpoint DIRECTORIES;
                // the UUID gate also keeps stray non-session jsonl out.
                guard file.pathExtension == "jsonl",
                      UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                      let mtime = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                else { return nil }
                return (file, mtime)
            }
        }
    }

    private static let customTitleMarker = Data("custom-title".utf8)
    private static let summaryMarker = Data("\"summary\"".utf8)

    static func claudeRecord(file: URL, mtime: Date) -> AgentSessionRecord? {
        let conversationId = file.deletingPathExtension().lastPathComponent
        var customTitle: String?
        var summary: String?
        var firstUserText: String?
        var cwd: String?
        for line in headLines(of: file) {
            // Once the first-wins fields are settled, the only lines that can
            // still change the record are `custom-title` (last wins — a rename
            // appends rather than rewrites, so the whole head must be walked)
            // and a first `summary`. Gating the JSON parse on their byte
            // markers skips the multi-KB assistant/tool lines that dominate
            // the head — this is the scan's hottest loop. A marker false
            // positive just parses one extra line.
            if cwd != nil, firstUserText != nil,
               line.range(of: customTitleMarker) == nil,
               summary != nil || line.range(of: summaryMarker) == nil {
                continue
            }
            guard let object = jsonObject(line) else { continue }
            switch object["type"] as? String {
            case "custom-title":
                if let value = object["customTitle"] as? String { customTitle = value }
            case "summary":
                if summary == nil, let value = object["summary"] as? String { summary = value }
            case "user":
                // Sidechain transcripts are subagent work, not a conversation
                // the user can meaningfully resume — drop the whole file.
                // (Checked before the gate can engage: the first user line is
                // always parsed, because `firstUserText` is still nil then.)
                if object["isSidechain"] as? Bool == true { return nil }
                if cwd == nil { cwd = object["cwd"] as? String }
                if firstUserText == nil,
                   let message = object["message"] as? [String: Any],
                   let text = displayableUserText(messageContent(message["content"])) {
                    firstUserText = text
                }
            default:
                break
            }
        }
        // No cwd means no place to resume in — a wrong directory would break
        // every file reference in the conversation, so skip instead.
        guard let cwd else { return nil }
        return AgentSessionRecord(
            agentId: AgentTemplate.claudeCodeID,
            conversationId: conversationId,
            title: cleanedTitle(customTitle ?? summary ?? firstUserText ?? ""),
            cwd: URL(fileURLWithPath: cwd),
            lastActivity: mtime
        )
    }

    /// Claude `message.content` is either a plain string or an array of
    /// content blocks; the first text block carries what the user typed.
    private static func messageContent(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return nil }
        for block in blocks where block["type"] as? String == "text" {
            return block["text"] as? String
        }
        return nil
    }

    // MARK: Codex (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)

    private static func codexRolloutFiles(under root: URL) -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [(url: URL, mtime: Date)] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "jsonl",
                  file.lastPathComponent.hasPrefix("rollout-"),
                  let mtime = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            result.append((file, mtime))
        }
        return result
    }

    static func codexRecord(file: URL, mtime: Date) -> AgentSessionRecord? {
        // id + cwd come from the existing session_meta readers, which handle
        // two things a head-limited re-parse would regress on: the legacy
        // `session_id` key fallback, and a meta line larger than any fixed
        // head cap (they read newline-bounded, up to 4MB).
        guard let conversationId = CodexUsageMonitor.sessionMetaConversationId(atPath: file.path),
              let cwd = CodexUsageMonitor.sessionMetaCwd(atPath: file.path)
        else { return nil }
        var title: String?
        for line in headLines(of: file) {
            guard let object = jsonObject(line) else { continue }
            // `user_message` events carry exactly what the user typed —
            // unlike the first `response_item` user message, which is the
            // AGENTS.md / environment injection.
            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message"
            else { continue }
            if let text = displayableUserText(payload["message"] as? String) {
                title = text
                break
            }
        }
        return AgentSessionRecord(
            agentId: AgentTemplate.codex.id,
            conversationId: conversationId,
            title: cleanedTitle(title ?? ""),
            cwd: URL(fileURLWithPath: cwd),
            lastActivity: mtime
        )
    }

    // MARK: Shared parsing helpers

    /// Line slices from the file's first `headByteLimit` bytes, split on raw
    /// newlines — no String decode: JSONSerialization takes UTF-8 `Data`
    /// directly, so decoding ~256KB per file to `String` would be a wasted
    /// full pass. A line truncated at the boundary simply fails JSON parsing
    /// and is skipped.
    private static func headLines(of file: URL) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headByteLimit), !data.isEmpty else { return [] }
        return data.split(separator: UInt8(ascii: "\n"))
    }

    private static func jsonObject(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    /// First-user-message text is only a usable title when it's something the
    /// user actually typed. Injected blocks (`<command-name>`,
    /// `<system-reminder>`, Codex XML wrappers) and the Claude hook caveat all
    /// lead with a recognizable prefix — reject those and let the caller try
    /// the next candidate line.
    private static func displayableUserText(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("<"),
              !trimmed.hasPrefix("Caveat:")
        else { return nil }
        return trimmed
    }

    /// Titles come from prompt text that can be arbitrarily long and can span
    /// lines; the record stores one bounded line (`singleLine` is the shared
    /// tooltip-safety rule — an interior newline must never survive into
    /// composed UI strings).
    private static func cleanedTitle(_ raw: String) -> String {
        let flattened = singleLine(raw).trimmingCharacters(in: .whitespaces)
        return String(flattened.prefix(160))
    }
}

// MARK: - Model

/// App-level cache of the on-disk session list, shared by every window's
/// History pane. `@MainActor @Observable` singleton like `AgentMonitor`, but a
/// snapshot store rather than a derived view: disk state has no observation
/// to ride, so views call `refresh()` on appear and the model republishes.
@MainActor
@Observable
final class AgentSessionHistory {
    static let shared = AgentSessionHistory()
    /// `internal` so tests can build isolated instances against fixture roots.
    init(claudeProjectsRoot: URL? = nil, codexSessionsRoot: URL? = nil) {
        self.claudeProjectsRoot = claudeProjectsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        // Static default root only: the scan isn't tied to any live session,
        // so there's no shell env to consult (`CodexUsageMonitor` needs one
        // because a Dock-launched kooky lacks the user's CODEX_HOME; here the
        // ProcessInfo fallback inside `defaultSessionsRoot` is the best
        // available).
        self.codexSessionsRoot = codexSessionsRoot
            ?? CodexUsageMonitor.defaultSessionsRoot()
    }

    private let claudeProjectsRoot: URL
    private let codexSessionsRoot: URL
    /// Appear-triggered refreshes within this window reuse the last result —
    /// every panel remount (agents↔history flip, hidden↔full) fires one, and
    /// a full rescan is ~75MB of file-head I/O. The header's rescan button
    /// bypasses it with `force: true`.
    private static let minSecondsBetweenScans: TimeInterval = 30

    private(set) var records: [AgentSessionRecord] = []
    /// True only until the FIRST scan lands — refreshes after that keep the
    /// stale list on screen instead of flashing a spinner over it.
    private(set) var isInitialLoad = true
    /// True while a scan is actually running — drives the refresh button's
    /// spinner so the view doesn't have to fabricate its own "refreshing"
    /// state.
    private(set) var isScanning = false
    private var lastScanCompleted: Date?

    func refresh(force: Bool = false) {
        guard !isScanning else { return }
        if !force, let last = lastScanCompleted,
           Date().timeIntervalSince(last) < Self.minSecondsBetweenScans {
            return
        }
        isScanning = true
        let claudeRoot = claudeProjectsRoot
        let codexRoot = codexSessionsRoot
        Task {
            let result = await Task.detached(priority: .utility) {
                AgentSessionScanner.scan(claudeProjectsRoot: claudeRoot, codexSessionsRoot: codexRoot)
            }.value
            // Equality gate: most rescans find nothing new, and an
            // `@Observable` write re-renders every window's History pane
            // regardless of change.
            if records != result { records = result }
            if isInitialLoad { isInitialLoad = false }
            lastScanCompleted = Date()
            isScanning = false
        }
    }
}

/// Short age tier shared by every "how long ago" label: `now`, `12m`, `3h`,
/// `5d`. The history rows and the notification inbox both build on this so
/// the app has one ago-vocabulary.
func relativeAgeTier(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
    return "\(Int(seconds / 86_400))d"
}

/// History-row label: the shared tiers, then a bare `MMM d` date once
/// "n days" stops being how people think of it.
func relativeActivityLabel(_ date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 7 * 86_400 { return relativeAgeTier(seconds) }
    return monthDayFormatter.string(from: date)
}

private let monthDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
}()

// MARK: - View

/// Right sidebar's History pane: search + agent filter over the on-disk
/// session list; a click resumes that conversation in a new tab of the
/// active workspace.
struct SessionHistoryView: View {
    let store: WorkspaceStore
    var history = AgentSessionHistory.shared

    @State private var query = ""
    /// nil = every agent; else a builtin `AgentTemplate` id.
    @State private var agentFilter: String?
    /// Keeps the spinner up for a beat after a click: the scan usually
    /// finishes faster than the eye, and a spinner that never visibly
    /// appears reads as a dead button. The real in-flight fact is the
    /// model's `isScanning`; this only stretches its tail.
    @State private var spinnerMinHold = false

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: "session history", count: history.records.count) {
                refreshButton
            }
            searchField
            filterChips
            let visible = filteredRecords
            if visible.isEmpty {
                PanelEmptyState(
                    symbol: "clock",
                    message: history.isInitialLoad ? "scanning…" : "no sessions found"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { record in
                            SessionHistoryRow(record: record) {
                                store.resumeAgentSession(record)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { history.refresh() }
    }

    private var refreshButton: some View {
        HoverableIconButton(
            size: 22,
            help: "Rescan sessions",
            action: {
                history.refresh(force: true)
                spinnerMinHold = true
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    spinnerMinHold = false
                }
            }
        ) {
            if history.isScanning || spinnerMinHold {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .scaleEffect(0.65)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.chromeMuted)
            // Hand-drawn placeholder: on macOS a `prompt` Text ignores its
            // color modifiers and renders at the system placeholder
            // brightness, which reads glaring on dark chrome.
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("search sessions")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeMuted.opacity(0.5))
                        .allowsHitTesting(false)
                }
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.chromeForeground)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Theme.chromeHover)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var filterChips: some View {
        HStack(spacing: 4) {
            filterChip(nil, label: "all")
            // Chips for the stores the scanner ACTUALLY reads, not for
            // whatever happens to be in the current result set — a filter
            // that disappears because its list is momentarily empty would
            // drop the user back to `all` mid-browse.
            ForEach(AgentSessionScanner.supportedAgentIds, id: \.self) { agentId in
                filterChip(agentId, label: AgentTemplate.builtin(id: agentId)?.title.lowercased() ?? agentId)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func filterChip(_ agentId: String?, label: String) -> some View {
        let isActive = agentFilter == agentId
        return Button {
            agentFilter = agentId
        } label: {
            Text(label)
                .font(Theme.mono(10, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Theme.chromeForeground : Theme.chromeMuted)
                .padding(.horizontal, 8)
                .frame(height: 19)
                .hoverableRowBackground(isActive: isActive, isHovered: false)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredRecords: [AgentSessionRecord] {
        history.records.filter { record in
            if let agentFilter, record.agentId != agentFilter { return false }
            guard !query.isEmpty else { return true }
            return record.title.localizedCaseInsensitiveContains(query)
                || record.cwd.path.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct SessionHistoryRow: View {
    let record: AgentSessionRecord
    let onResume: () -> Void
    private let template: AgentTemplate?

    @State private var isHovered = false

    init(record: AgentSessionRecord, onResume: @escaping () -> Void) {
        self.record = record
        self.onResume = onResume
        self.template = AgentTemplate.builtin(id: record.agentId)
    }

    var body: some View {
        HStack(spacing: 10) {
            AgentIconView(asset: template?.iconAsset, fallbackSymbol: template?.symbol ?? "sparkles", size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title.isEmpty ? "untitled" : record.title)
                    .font(Theme.mono(12, weight: .medium))
                    .foregroundStyle(record.title.isEmpty ? Theme.chromeMuted : Theme.chromeForeground)
                    .lineLimit(1)
                Text("\(record.cwd.lastPathComponent) · \(relativeActivityLabel(record.lastActivity))")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .hoverableRowBackground(isHovered: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: onResume)
        .onHover { isHovered = $0 }
        .help(hoverText)
    }

    private var hoverText: String {
        let name = singleLine(template?.title ?? record.agentId)
        let title = singleLine(record.title.isEmpty ? "untitled" : record.title)
        let location = singleLine((record.cwd.path as NSString).abbreviatingWithTildeInPath)
        return "\(name) · \(relativeActivityLabel(record.lastActivity))\n\(title)\n\(location)"
    }
}
