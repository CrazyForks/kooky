import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore

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
                    AgentOverviewSidebar(mode: store.rightSidebarMode)
                }
            }
        }
        .glassWindowBackground(fallback: chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .ignoresSafeArea(.all)
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
                systemName: "square.grid.2x2",
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

    private var sidebarTooltip: String {
        switch store.sidebarMode {
        case .full: return "Compact sidebar"
        case .compact: return "Hide sidebar"
        case .hidden: return "Show sidebar"
        }
    }

}
