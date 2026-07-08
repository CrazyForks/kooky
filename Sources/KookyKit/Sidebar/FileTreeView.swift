import SwiftUI

/// Sidebar files mode: a header naming the active workspace's root, then the
/// flattened file tree. Mounted by `SidebarView` in place of the workspace
/// list while `store.sidebarContent == .files` (full mode only — 52pt can't
/// fit a tree).
struct FileTreeView: View {
    let store: WorkspaceStore
    let model: FileTreeModel

    @State private var activationToken = 0

    var body: some View {
        VStack(spacing: 0) {
            if let root = model.rootURL {
                header(root: root)
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            }
            content
        }
        .onAppear { activationToken = model.activate(root: store.active?.diskPath) }
        // Tokened: an animated unmount's late onDisappear must not deactivate
        // the model a newer mount just activated (frozen-tree race).
        .onDisappear { model.deactivate(token: activationToken) }
        // Follows the active workspace, and — for plain workspaces, where
        // `diskPath == workingDirectory` — OSC 7 cwd drift; worktrees stay
        // pinned via `worktreePath`.
        .onChange(of: store.active?.diskPath.path) { _, newPath in
            model.setRoot(newPath.map { URL(fileURLWithPath: $0) })
        }
    }

    private func header(root: URL) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.6))
                Text(root.lastPathComponent)
                    .font(Theme.display(13, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text((root.path as NSString).abbreviatingWithTildeInPath)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeFaint)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.space3)
        .padding(.top, Theme.space1)
        .padding(.bottom, Theme.space2)
        .help(root.path)
    }

    @ViewBuilder
    private var content: some View {
        if store.active == nil {
            emptyState("square.dashed", "No active workspace")
        } else if model.rootError {
            emptyState("folder.badge.questionmark", "Folder unavailable")
        } else if model.rows.isEmpty {
            emptyState("folder", "Empty folder")
        } else {
            ScrollView(showsIndicators: false) {
                // spacing 0 keeps the indent guides visually continuous down
                // the column; each row carries its own hover/selected fill.
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        FileTreeRowView(row: row, model: model, store: store)
                    }
                }
                .padding(.horizontal, Theme.space2)
                .padding(.top, Theme.space1)
                .padding(.bottom, Theme.space2)
            }
            // Fresh scroll position when the tree re-roots — offsets from
            // the previous workspace's tree are meaningless here.
            .id(model.rootURL?.path)
        }
    }

    private func emptyState(_ symbol: String, _ message: String) -> some View {
        VStack(spacing: Theme.space2) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.chromeFaint)
            Text(message)
                .font(Theme.display(12))
                .foregroundStyle(Theme.chromeMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One flattened tree row — indent guides by depth, chevron for directories,
/// icon, name. Single click selects (and toggles a directory); double click
/// opens a file with its default app; drag carries the file/folder URL so a
/// drop onto a terminal pane inserts its escaped path (same path as a Finder
/// drag — the pane's `performDragOperation` reads the same `.fileURL`); right
/// click opens the kooky popover menu.
private struct FileTreeRowView: View {
    let row: FileTreeRow
    let model: FileTreeModel
    let store: WorkspaceStore

    @State private var isHovered = false
    @State private var isContextMenuOpen = false
    @State private var lastDirectoryToggle: Date = .distantPast

    /// Per-level indent. 14pt keeps ~10 levels readable inside the sidebar's
    /// full width; the guide line sits at the column centre so it lands under
    /// the parent row's chevron. Names beyond depth truncate middle and the
    /// row tooltip carries the full path.
    private static let indentPerLevel: CGFloat = 14
    private static let chevronColumn: CGFloat = 14
    private static let iconColumn: CGFloat = 17

    var body: some View {
        switch row.kind {
        case .entry(let node):
            entryRow(node)
        case .placeholder:
            placeholderRow()
        }
    }

    /// One 1pt guide per ancestor level, full row height. Centred in the
    /// 14pt column so it aligns exactly under the parent chevron (chevron
    /// centre = 7pt into its own 14pt column = guide centre of the next
    /// level down).
    @ViewBuilder
    private func indentGuides(_ depth: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.chromeHairline)
                    .frame(width: 1)
                    .frame(width: Self.indentPerLevel)
            }
        }
        .padding(.leading, Theme.space2)
    }

    /// The shared row frame: the caller's leading columns + label, a trailing
    /// spacer, depth indentation, and the common padding recipe. The indent
    /// guides draw in a full-height *background* — as HStack siblings they'd
    /// stop at the content height and leave a gap across the vertical
    /// padding of every row, rendering as dashes instead of continuous
    /// lines. Row-kind-specific modifiers (hover fill, gestures, drag) chain
    /// onto the result at the `entryRow` call site.
    private func rowShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * Self.indentPerLevel)
        .padding(.vertical, 3.5)
        .padding(.leading, Theme.space2)
        .padding(.trailing, Theme.space2)
        .background(alignment: .leading) { indentGuides(row.depth) }
    }

    private func entryRow(_ node: FileNode) -> some View {
        let isSelected = model.selectedId == row.id
        return rowShell {
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected || isHovered ? Theme.chromeMuted : Theme.chromeFaint)
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                    .frame(width: Self.chevronColumn)
            } else {
                // Explicit spacer, NOT an empty conditional with a frame — a
                // frame on an empty view renders nothing, and files would sit
                // 14pt left of sibling directories.
                Color.clear.frame(width: Self.chevronColumn, height: 1)
            }
            Image(systemName: FileTreeLister.symbolName(for: node))
                .font(.system(size: 11))
                .foregroundStyle(iconColor(node, selected: isSelected))
                .frame(width: Self.iconColumn)
            Text(node.name)
                .font(Theme.display(12.5))
                .foregroundStyle(nameColor(selected: isSelected))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 2)
        }
        .animation(.easeOut(duration: 0.15), value: row.isExpanded)
        .hoverableRowBackground(isActive: isSelected, isHovered: isHovered)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        // Drag carries the raw file URL (public.file-url). The terminal pane's
        // `performDragOperation` reads exactly this and backslash-escapes the
        // path, so a tree drag lands identically to a Finder drag.
        .onDrag {
            NSItemProvider(object: node.url as NSURL)
        } preview: {
            dragPreview(node)
        }
        // count:2 must attach before count:1 or the double never recognizes.
        // A double-click on a file also fires the single handler on its
        // first click — select-then-open, same as Finder.
        .onTapGesture(count: 2) {
            if !node.isDirectory { NSWorkspace.shared.open(node.url) }
        }
        .onTapGesture {
            model.selectedId = row.id
            guard node.isDirectory else { return }
            // Whether the single-tap fires once or twice for a double-click
            // varies across macOS releases; swallow a second toggle inside
            // the double-click window so a Finder-habit double-click reads
            // as "expand", never an open-shut flicker.
            let now = Date()
            guard now.timeIntervalSince(lastDirectoryToggle) > NSEvent.doubleClickInterval else { return }
            lastDirectoryToggle = now
            withAnimation(.easeOut(duration: 0.12)) {
                model.toggleExpanded(node)
            }
        }
        .onHover { isHovered = $0 }
        .overlay(RightClickCatcher { _ in isContextMenuOpen = true })
        .popover(isPresented: $isContextMenuOpen, arrowEdge: .trailing) {
            contextMenu(node)
        }
        .help(node.url.path)
    }

    /// File/folder icon tint — a single-colour hierarchy: folders read as
    /// containers (more solid), files as leaves (muted), the selected row
    /// promotes to full foreground. No hue; kooky's chrome stays monochrome.
    private func iconColor(_ node: FileNode, selected: Bool) -> Color {
        if selected { return Theme.chromeForeground }
        if node.isDirectory { return Theme.chromeForeground.opacity(0.6) }
        return isHovered ? Theme.chromeForeground.opacity(0.72) : Theme.chromeMuted
    }

    private func nameColor(selected: Bool) -> Color {
        if selected { return Theme.chromeForeground }
        return Theme.chromeForeground.opacity(isHovered ? 0.95 : 0.82)
    }

    /// Compact chip shown under the cursor while dragging — icon + name on the
    /// chrome surface, so the drag reads as "this file" rather than a snapshot
    /// of the whole hover-highlighted row.
    private func dragPreview(_ node: FileNode) -> some View {
        HStack(spacing: Theme.space1) {
            Image(systemName: FileTreeLister.symbolName(for: node))
                .font(.system(size: 11))
                .foregroundStyle(Theme.chromeForeground.opacity(0.8))
            Text(node.name)
                .font(Theme.display(12))
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.space2)
        .padding(.vertical, Theme.space1)
        .background(Theme.chromeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.chromeHairline, lineWidth: 1))
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
    /// directory, indented to match its parent's children.
    private func placeholderRow() -> some View {
        rowShell {
            Color.clear.frame(width: Self.chevronColumn, height: 1)
            Text("no access")
                .font(Theme.display(11.5))
                .foregroundStyle(Theme.chromeFaint)
                .lineLimit(1)
        }
    }
}
