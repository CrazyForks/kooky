import AppKit
import SwiftUI

/// Brutalist sheet for creating a git worktree from a source workspace.
/// Same visual language as `UpdatePromptView` / Settings — `Theme.chrome*`
/// tokens, mono kebab-case labels, sharp corners, 1pt hairlines, bracket
/// buttons. Form-only: the parent owns the actual git + workspace
/// materialization via the `create` closure and dismisses on success.
struct CreateWorktreeSheet: View {
    /// Parent passes this back from `create` so the sheet can surface
    /// failure inline (user fixes the branch name / path and retries)
    /// instead of dismissing.
    enum CreateOutcome: Equatable {
        case success
        case failure(String)
    }

    /// Bundle of form output handed to `create`.
    struct Request {
        let mode: WorktreeManager.BranchMode
        let path: URL
        /// Either the existing branch name or the new branch name — the
        /// value sidebar shows under `Workspace.worktreeBranch`.
        let branchForDisplay: String
        let template: AgentTemplate
    }

    let source: Workspace
    let launchTemplates: [AgentTemplate]
    let defaultLaunchTemplate: AgentTemplate
    let create: @MainActor (Request) async -> CreateOutcome
    let dismiss: () -> Void

    private enum BranchModeUI: Hashable { case newBranch, existing }
    private enum StartFromChoice: Hashable {
        case head
        case branch(String)
        case custom
    }

    @State private var branchMode: BranchModeUI = .newBranch
    @State private var newBranchName: String = ""
    @State private var startFromChoice: StartFromChoice = .head
    @State private var customStartRef: String = ""
    @State private var existingBranch: String = ""
    /// Loaded off-thread via `.task` on first sheet appear so the main
    /// thread doesn't block on `git for-each-ref` while the user is
    /// typing. Empty until the subprocess returns.
    @State private var availableBranches: [String] = []
    @State private var checkedOutBranches: Set<String> = []
    @State private var branchesLoaded: Bool = false
    /// Stable git root for the source workspace. `Workspace.workingDirectory`
    /// follows the active shell cwd, so it may be a nested folder by the time
    /// the user opens this sheet.
    @State private var sourceRoot: URL?
    /// User override for the auto-computed `<repo>-<branch>` sibling path.
    /// Empty = use the computed default at submit time. Lives only in
    /// the options section.
    @State private var worktreePathOverride: String = ""
    @State private var selectedTemplate: AgentTemplate?
    @State private var isOptionsExpanded: Bool = false
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLabel
                .padding(.bottom, 18)

            headline
            subtitle
                .padding(.top, 6)

            Rectangle()
                .fill(Theme.chromeHairline)
                .frame(width: 32, height: 1)
                .padding(.vertical, 22)

            form

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.activityFailure.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            HStack(spacing: 10) {
                Spacer()
                BracketButton("cancel") { dismiss() }
                    .disabled(isWorking)
                    .opacity(isWorking ? 0.4 : 1)
                BracketButton(isWorking ? "creating…" : "create worktree") {
                    submit()
                }
                .disabled(isWorking || !canSubmit)
                .opacity(canSubmit && !isWorking ? 1 : 0.4)
            }
            .padding(.top, 22)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .frame(width: 480, alignment: .topLeading)
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onAppear(perform: prefill)
        .task {
            // First render: kick off branch enumeration off the main
            // thread. The picker stays empty until this returns; the
            // sheet starts on `.newBranch` mode so most users never
            // wait on this.
            guard !branchesLoaded else { return }
            let cwd = source.workingDirectory
            // `repoRoot` is the gate; `list` and `localBranches` are
            // independent once it resolves, so kick them off in parallel
            // child tasks. Cuts sheet-open time from ~150-450ms to the
            // max of the two (~100-300ms) on a cold git cache.
            let loaded = await Task.detached(priority: .userInitiated) {
                let root = WorktreeManager.repoRoot(near: cwd)
                let queryCwd = root ?? cwd
                async let checkedOut: Set<String> = {
                    guard let root,
                          case .success(let infos) = WorktreeManager.list(repoPath: root)
                    else { return [] }
                    return WorktreeManager.checkedOutBranches(in: infos)
                }()
                async let branches = GitBranchInventory.localBranches(cwd: queryCwd)
                return (
                    root: root,
                    branches: await branches,
                    checkedOut: await checkedOut
                )
            }.value
            sourceRoot = loaded.root
            let branches = loaded.branches
            availableBranches = branches
            checkedOutBranches = loaded.checkedOut
            if existingBranch.isEmpty || loaded.checkedOut.contains(existingBranch) {
                existingBranch = branches.first { !loaded.checkedOut.contains($0) } ?? ""
            }
            branchesLoaded = true
            // No usable existing-branch target → fall back to new branch
            // (mode picker hides itself in this state; leaving branchMode
            // on `.existing` would strand the form on an empty picker).
            if existingBranch.isEmpty, branchMode == .existing {
                branchMode = .newBranch
            }
        }
    }

    // MARK: Sections

    private var statusLabel: some View {
        Text("CREATE-WORKTREE")
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(Theme.chromeMuted.opacity(0.85))
    }

    private var headline: some View {
        Text(source.title)
            .font(Theme.display(20, weight: .medium))
            .foregroundStyle(Theme.chromeForeground)
    }

    private var subtitle: some View {
        Text((sourcePathForDisplay.path as NSString).abbreviatingWithTildeInPath)
            .font(Theme.mono(11.5))
            .foregroundStyle(Theme.chromeMuted)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            modePicker
            branchField
            if !isOptionsExpanded {
                pathPreview
            }

            optionsToggle

            if isOptionsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    editRow(label: "worktree-path", text: $worktreePathOverride, placeholder: defaultPath)
                    if branchMode == .newBranch {
                        startFromControl
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("launch")
                        Picker("", selection: Binding(
                            get: { selectedTemplate ?? defaultLaunchTemplate },
                            set: { selectedTemplate = $0 }
                        )) {
                            ForEach(launchTemplates) { t in
                                Text(t.title).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        // Stay hidden until branches finish loading so the picker doesn't
        // flash in then disappear when we learn there's no selectable
        // existing branch. After loading: show only when there's something
        // to pick — a toggle whose only branch is "new" reads as broken.
        // Loading typically resolves in well under the sheet's open
        // animation, so users don't perceive the gap.
        if branchesLoaded && !selectableExistingBranches.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("mode")
                Picker("", selection: $branchMode) {
                    Text("new").tag(BranchModeUI.newBranch)
                    Text("existing").tag(BranchModeUI.existing)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var branchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(branchMode == .newBranch ? "new-branch" : "existing-branch")
            switch branchMode {
            case .newBranch:
                TextField("feat-x", text: $newBranchName)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .bracketBorder()
                if newBranchAlreadyExists {
                    newBranchConflictRow
                }
            case .existing:
                existingBranchMenu
            }
        }
    }

    private var newBranchConflictRow: some View {
        HStack(spacing: 8) {
            inlineStatus(newBranchConflictMessage, color: Theme.activityFailure.opacity(0.85))
            if !newBranchIsCheckedOut {
                Button("use existing") {
                    existingBranch = normalizedNewBranchName
                    branchMode = .existing
                }
                .buttonStyle(.plain)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeForeground)
            }
        }
    }

    @ViewBuilder
    private var existingBranchMenu: some View {
        if !branchesLoaded {
            inlineStatus("loading branches…")
        } else if availableBranches.isEmpty {
            inlineStatus("no local branches found")
        } else if selectableExistingBranches.isEmpty {
            inlineStatus("all local branches are already checked out")
        } else {
            Picker("", selection: $existingBranch) {
                ForEach(selectableExistingBranches, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var startFromControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("start-from")
            Picker("", selection: $startFromChoice) {
                Text("HEAD").tag(StartFromChoice.head)
                ForEach(availableBranches, id: \.self) { branch in
                    Text(branch).tag(StartFromChoice.branch(branch))
                }
                Text("custom ref…").tag(StartFromChoice.custom)
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if startFromChoice == .custom {
                TextField("origin/main, tag, or SHA", text: $customStartRef)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .bracketBorder()
                if customStartRefIsMissing {
                    inlineStatus("enter a ref")
                }
            }
        }
    }

    private var pathPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("worktree-path")
            Text(effectivePathDisplay)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.chromeMuted)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .bracketBorder()
        }
    }

    private func inlineStatus(_ text: String, color: Color = Theme.chromeMuted) -> some View {
        Text(text)
            .font(Theme.mono(11.5))
            .foregroundStyle(color)
    }

    private var optionsToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isOptionsExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isOptionsExpanded ? 90 : 0))
                Text("options")
                    .font(Theme.mono(10, weight: .medium))
                    .tracking(1.2)
            }
            .foregroundStyle(Theme.chromeMuted.opacity(0.85))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.chromeMuted.opacity(0.85))
    }

    @ViewBuilder
    private func editRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.chromeForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .bracketBorder()
        }
    }

    // MARK: Logic

    private var canSubmit: Bool {
        switch branchMode {
        case .newBranch:
            return !normalizedNewBranchName.isEmpty
                && !newBranchAlreadyExists
                && !customStartRefIsMissing
        case .existing:
            // Block submit until branches finish loading so a quick toggle
            // doesn't fire `create` with `existingBranch = ""`.
            return branchesLoaded
                && !existingBranch.isEmpty
                && !checkedOutBranches.contains(existingBranch)
        }
    }

    private var normalizedNewBranchName: String {
        newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newBranchAlreadyExists: Bool {
        branchesLoaded && availableBranches.contains(normalizedNewBranchName)
    }

    private var newBranchIsCheckedOut: Bool {
        checkedOutBranches.contains(normalizedNewBranchName)
    }

    private var newBranchConflictMessage: String {
        newBranchIsCheckedOut
            ? "branch is already checked out"
            : "branch exists locally"
    }

    private var customStartRefIsMissing: Bool {
        startFromChoice == .custom
            && customStartRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedStartRef: String? {
        switch startFromChoice {
        case .head:
            return nil
        case .branch(let branch):
            return branch
        case .custom:
            let trimmed = customStartRef.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func prefill() {
        if selectedTemplate == nil {
            selectedTemplate = defaultLaunchTemplate
        }
    }

    /// Branch the user is about to act on (new or existing). Drives the
    /// auto-computed `worktree-path` placeholder so it always reads as a
    /// finished proposal, not a half-filled `<repo>-` stub.
    private var currentBranchName: String {
        switch branchMode {
        case .newBranch: return normalizedNewBranchName
        case .existing: return existingBranch
        }
    }

    private var selectableExistingBranches: [String] {
        availableBranches.filter { !checkedOutBranches.contains($0) }
    }

    /// Sibling of the source repo: `<parent>/<repo-name>-<branch>`.
    /// Falls back to `<repo-name>-` when no branch has been typed yet so
    /// the placeholder still hints at the path's shape.
    private var defaultPath: String {
        let root = sourceRoot ?? source.workingDirectory
        let parentDir = root.deletingLastPathComponent()
        let base = root.lastPathComponent
        let name = WorktreeManager.defaultDirectoryName(sourceName: base, branch: currentBranchName)
        let candidate = parentDir.appendingPathComponent(name).path
        return (candidate as NSString).abbreviatingWithTildeInPath
    }

    private var effectivePathDisplay: String {
        let override = worktreePathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? defaultPath : (override as NSString).abbreviatingWithTildeInPath
    }

    private var sourcePathForDisplay: URL {
        sourceRoot ?? source.workingDirectory
    }

    private func submit() {
        // worktree-path falls back to the auto-computed default when the
        // user didn't expand options (or left it blank). The override
        // wins only when non-empty.
        let override = worktreePathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePath = override.isEmpty ? defaultPath : override
        let expanded = (effectivePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        let mode: WorktreeManager.BranchMode
        let branchForDisplay: String
        switch branchMode {
        case .newBranch:
            let name = normalizedNewBranchName
            mode = .newBranch(name: name, base: selectedStartRef)
            branchForDisplay = name
        case .existing:
            mode = .existing(branch: existingBranch)
            branchForDisplay = existingBranch
        }

        let request = Request(
            mode: mode,
            path: url,
            branchForDisplay: branchForDisplay,
            template: selectedTemplate ?? defaultLaunchTemplate
        )

        isWorking = true
        errorMessage = nil
        Task {
            let outcome = await create(request)
            switch outcome {
            case .success:
                dismiss()
            case .failure(let message):
                isWorking = false
                errorMessage = message
            }
        }
    }
}
