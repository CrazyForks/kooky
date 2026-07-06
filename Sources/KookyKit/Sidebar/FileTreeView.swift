import SwiftUI

/// Sidebar files mode: a header naming the active workspace's root, then the
/// flattened file tree. Mounted by `SidebarView` in place of the workspace
/// list while `store.sidebarContent == .files` (full mode only — 52pt can't
/// fit a tree).
struct FileTreeView: View {
    @Bindable var store: WorkspaceStore
    let model: FileTreeModel

    var body: some View {
        VStack(spacing: 0) {
            if let root = model.rootURL {
                header(root: root)
            }
            content
        }
        .onAppear { model.activate(root: store.active?.diskPath) }
        .onDisappear { model.deactivate() }
        // Follows the active workspace, and — for plain workspaces, where
        // `diskPath == workingDirectory` — OSC 7 cwd drift; worktrees stay
        // pinned via `worktreePath`.
        .onChange(of: store.active?.diskPath.path) { _, newPath in
            model.setRoot(newPath.map { URL(fileURLWithPath: $0) })
        }
    }

    private func header(root: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(root.lastPathComponent)
                .font(Theme.display(12.5, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(1)
            Text((root.path as NSString).abbreviatingWithTildeInPath)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.chromeMuted)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.space4)
        .padding(.bottom, Theme.space2)
        .help(root.path)
    }

    @ViewBuilder
    private var content: some View {
        if store.active == nil {
            emptyState("No active workspace")
        } else if model.rootError {
            emptyState("Folder unavailable")
        } else if model.rows.isEmpty {
            emptyState("Empty folder")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(model.rows) { row in
                        FileTreeRowView(row: row, model: model, store: store)
                    }
                }
                .padding(.horizontal, Theme.space2)
                .padding(.vertical, Theme.space2)
            }
            // Fresh scroll position when the tree re-roots — offsets from
            // the previous workspace's tree are meaningless here.
            .id(model.rootURL?.path)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(Theme.display(12))
            .foregroundStyle(Theme.chromeMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.space4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One flattened tree row — indent by depth, chevron for directories, icon,
/// name. Single click selects (and toggles a directory); double click opens
/// a file with its default app; right click opens the kooky popover menu.
private struct FileTreeRowView: View {
    let row: FileTreeRow
    let model: FileTreeModel
    let store: WorkspaceStore

    @State private var isHovered = false
    @State private var isContextMenuOpen = false

    /// Per-level indent. 14pt keeps ~10 levels readable inside the sidebar's
    /// 220pt; names beyond that truncate middle and the row tooltip carries
    /// the full path.
    private static let indentPerLevel: CGFloat = 14

    var body: some View {
        switch row.kind {
        case .entry(let node):
            entryRow(node)
        case .placeholder(let message):
            placeholderRow(message)
        }
    }

    private func entryRow(_ node: FileNode) -> some View {
        let isSelected = model.selectedId == row.id
        return HStack(spacing: Theme.space1) {
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.chromeMuted)
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.15), value: row.isExpanded)
                    .frame(width: 14)
            } else {
                // Keep file names column-aligned with sibling directories.
                Color.clear.frame(width: 14, height: 1)
            }
            Image(systemName: FileTreeLister.symbolName(for: node))
                .font(.system(size: 11))
                .foregroundStyle(Theme.chromeMuted)
                .frame(width: 16)
            Text(node.name)
                .font(Theme.display(12.5))
                .foregroundStyle(isSelected ? Theme.chromeForeground : Theme.chromeForeground.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * Self.indentPerLevel)
        .padding(.horizontal, Theme.space2)
        .padding(.vertical, 4)
        .hoverableRowBackground(isActive: isSelected, isHovered: isHovered)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        // count:2 must attach before count:1 or the double never recognizes.
        // A double-click on a file also fires the single handler on its
        // first click — select-then-open, same as Finder.
        .onTapGesture(count: 2) {
            if !node.isDirectory { NSWorkspace.shared.open(node.url) }
        }
        .onTapGesture {
            model.selectedId = row.id
            if node.isDirectory {
                withAnimation(.easeOut(duration: 0.12)) {
                    model.toggleExpanded(node)
                }
            }
        }
        .onHover { isHovered = $0 }
        .overlay(RightClickCatcher { _ in isContextMenuOpen = true })
        .popover(isPresented: $isContextMenuOpen, arrowEdge: .trailing) {
            contextMenu(node)
        }
        .help(node.url.path)
    }

    private func contextMenu(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !node.isDirectory {
                KookyMenuRow(title: "Open") {
                    isContextMenuOpen = false
                    NSWorkspace.shared.open(node.url)
                }
            }
            KookyMenuRow(title: "Reveal in Finder") {
                isContextMenuOpen = false
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            KookyMenuDivider()
            KookyMenuRow(title: "Copy Path") {
                isContextMenuOpen = false
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(node.url.path, forType: .string)
            }
            // Same escape + paste path as dropping a file from Finder onto a
            // pane, so the two can't drift.
            KookyMenuRow(
                title: "Insert Path into Terminal",
                isDisabled: store.active?.activeSession == nil
            ) {
                isContextMenuOpen = false
                store.active?.activeSession?.engine
                    .paste(KookyShellIntegration.backslashEscape(node.url.path))
            }
        }
        .padding(Theme.space1)
        .frame(minWidth: 220)
        .background(Theme.chromeBackground)
    }

    /// Muted, non-interactive note under an expanded-but-unlistable
    /// directory ("no access").
    private func placeholderRow(_ message: String) -> some View {
        HStack(spacing: Theme.space1) {
            Color.clear.frame(width: 14, height: 1)
            Text(message)
                .font(Theme.display(11.5))
                .foregroundStyle(Theme.chromeMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * Self.indentPerLevel)
        .padding(.horizontal, Theme.space2)
        .padding(.vertical, 4)
    }
}
