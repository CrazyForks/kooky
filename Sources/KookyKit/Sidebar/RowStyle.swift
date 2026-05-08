import SwiftUI

/// Shared row background palette for sidebar / tab / popover-menu rows.
/// Centralizes the hover/active alpha values so a future theme toggle has one
/// place to change.
extension View {
    func hoverableRowBackground(isActive: Bool = false, isHovered: Bool) -> some View {
        let color: Color
        if isActive {
            color = Color.white.opacity(0.10)
        } else if isHovered {
            color = Color.white.opacity(0.05)
        } else {
            color = .clear
        }
        return background(color)
    }

    /// Menu rows are single-state: hover === selected, so they use the active
    /// alpha (0.10) instead of the lighter hover (0.05).
    func menuRowHover(_ isHovered: Bool) -> some View {
        background(isHovered ? Color.white.opacity(0.10) : Color.clear)
    }
}
