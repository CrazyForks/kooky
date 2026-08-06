import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    /// Narrow AppKit seam: the store remains the source of truth for sidebar
    /// state; the owning window controller only mirrors those widths into
    /// `NSWindow.minSize`. `true` asks it to animate a required expansion
    /// after a mode toggle; drag-driven width changes stay immediate.
    var onWindowLayoutChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            HStack(spacing: 0) {
                if store.sidebarMode != .hidden {
                    SidebarView(store: store, mode: store.sidebarMode)
                    Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                }
                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.rightSidebarMode != .hidden {
                    Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                    AgentOverviewSidebar(store: store, mode: store.rightSidebarMode)
                }
            }
        }
        .glassWindowBackground(fallback: chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .ignoresSafeArea(.all)
        .onChange(of: store.sidebarMode) { _, _ in
            onWindowLayoutChange(true)
        }
        .onChange(of: store.rightSidebarMode) { _, _ in
            onWindowLayoutChange(true)
        }
        .onChange(of: store.sidebarWidth) { _, _ in
            onWindowLayoutChange(false)
        }
        .onChange(of: minimumTerminalTreeWidth) { _, _ in
            // Split/close/workspace-switch is discrete. Expand immediately:
            // unlike sidebar mode changes, split creation does not suspend
            // existing engines for an animation-wide SIGWINCH burst.
            // A smaller tree only relaxes the future resize limit.
            onWindowLayoutChange(false)
        }
    }

    /// Top 32pt strip. `window.isMovable = false` is set globally, so the
    /// `WindowDragHandle` background is the only place AppKit allows
    /// window dragging. The responsive `SearchTriggerPill` is scoped to the
    /// drag-handle area (not the whole strip), with an explicit safety gap
    /// from the controls on either side. It condenses before disappearing,
    /// so narrow windows keep a usable quick-open target whenever possible;
    /// `⌘P` + the File menu remain available when it is fully hidden.
    private var topStrip: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 82).allowsHitTesting(false)
            HoverableIconButton(
                systemName: "sidebar.left",
                fontSize: 12,
                size: 28,
                help: sidebarTooltip
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setSidebarMode(store.sidebarMode.next)
                }
            }
            WindowDragHandle()
                .overlay {
                    GeometryReader { proxy in
                        if KookySettingsModel.shared.showSearchPill,
                           proxy.size.width >= SearchTriggerPill.minimumContainerWidth {
                            SearchTriggerPill {
                                NSApp.sendAction(#selector(AppDelegate.handleQuickOpen), to: nil, from: nil)
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                }
            OpenInButton(store: store)
                .padding(.trailing, 2)
            HoverableIconButton(
                systemName: "sidebar.right",
                fontSize: 12,
                size: 28,
                help: "Agent Panel"
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setRightSidebarMode(store.rightSidebarMode.next)
                }
            }
            InboxBell()
            // Rightmost on purpose: a status light lives in the corner —
            // like a hardware power LED — not mixed into the action buttons.
            KeepAwakeButton()
                .padding(.trailing, 8)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var mainPane: some View {
        if let workspace = store.active {
            PaneTreeView(node: workspace.root, workspace: workspace, store: store)
                .id(workspace.id)
        } else {
            Color.clear
        }
    }

    private var chromeBackground: Color {
        let color = store.active?.activeSession?.engine.backgroundColor ?? Theme.terminalSurface
        return Color(nsColor: color)
    }

    private var minimumTerminalTreeWidth: CGFloat {
        KookyWindowLayout.minimumTerminalTreeWidth(for: store.active?.root)
    }

    private var sidebarTooltip: String {
        switch store.sidebarMode {
        case .full: return String(localized: "Compact sidebar", bundle: .kookyResources)
        case .compact: return String(localized: "Hide sidebar", bundle: .kookyResources)
        case .hidden: return String(localized: "Show sidebar", bundle: .kookyResources)
        }
    }

}
