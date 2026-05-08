import SwiftUI

struct TabBarItem: View {
    let tab: Session
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            AgentIconView(asset: tab.agent.iconAsset, fallbackSymbol: tab.agent.symbol, size: 15)
            Text(tab.title)
                .font(Theme.display(12, weight: .regular))
                .lineLimit(1)
            HoverableIconButton(
                systemName: "xmark",
                fontSize: 9,
                size: 16,
                help: "Close tab",
                action: onClose
            )
            .opacity(isHovered || isActive ? 1 : 0)
            .allowsHitTesting(isHovered || isActive)
        }
        .foregroundStyle(isActive ? Theme.chromeForeground : Theme.chromeForeground.opacity(0.6))
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isActive { return Theme.chromeActive }
        if isHovered { return Theme.chromeHover }
        return .clear
    }
}
