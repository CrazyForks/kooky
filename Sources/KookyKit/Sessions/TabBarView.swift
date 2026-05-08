import SwiftUI

struct TabBarView: View {
    @Bindable var workspace: Workspace
    let onActivateTab: (Session) -> Void
    let onAddTab: (AgentTemplate) -> Void
    let onCloseTab: (Session) -> Void

    @State private var isAddMenuOpen = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(workspace.tabs) { tab in
                    TabBarItem(
                        tab: tab,
                        isActive: tab.id == workspace.activeTabId,
                        onActivate: { onActivateTab(tab) },
                        onClose: { onCloseTab(tab) }
                    )
                }
                addButton
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.space2)
        }
        .frame(height: 40)
    }

    private var addButton: some View {
        // Popover, not Menu — SwiftUI's Menu bridges to NSMenu and drops custom
        // `Image(nsImage:)` icons (only systemImage survives the bridge).
        HoverableIconButton(
            systemName: "plus",
            fontSize: 11,
            size: 28,
            help: "New tab"
        ) {
            isAddMenuOpen.toggle()
        }
        .popover(isPresented: $isAddMenuOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(AgentTemplate.all) { template in
                    AgentMenuRow(template: template) {
                        onAddTab(template)
                        isAddMenuOpen = false
                    }
                }
            }
            .padding(Theme.space1)
            .frame(minWidth: 200)
            .background(Theme.chromeBackground)
        }
    }
}

private struct AgentMenuRow: View {
    let template: AgentTemplate
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space2) {
                AgentIconView(asset: template.iconAsset, fallbackSymbol: template.symbol, size: 16)
                Text(template.title)
                    .font(Theme.display(12.5, weight: .regular))
                    .foregroundStyle(Theme.chromeForeground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.space2 + 2)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Theme.chromeActive : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
