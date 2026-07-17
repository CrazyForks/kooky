import SwiftUI

/// Square chrome button with a hover-state background tint — the single
/// source for the top-strip / sidebar / tab-bar hover affordance (28pt-ish
/// square, white-0.12 hover, radius 5). The generic form takes any label
/// (KeepAwakeButton's breathing dot); the `systemName` convenience covers
/// the common SF-symbol case and keeps its call sites tiny.
struct HoverableIconButton<Label: View>: View {
    let size: CGFloat
    let help: String?
    let action: () -> Void
    /// Optional rotation in degrees applied to the label. Animated via
    /// `easeOut(0.15)` so toggle controls (sidebar disclosure chevron) get
    /// a smooth state transition; default 0 leaves static buttons (× / +)
    /// untouched.
    var rotation: Double = 0
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    init(
        size: CGFloat,
        help: String?,
        action: @escaping () -> Void,
        rotation: Double = 0,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.size = size
        self.help = help
        self.action = action
        self.rotation = rotation
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .rotationEffect(.degrees(rotation))
                .animation(.easeOut(duration: 0.15), value: rotation)
                .frame(width: size, height: size)
                .background(isHovered ? Color.white.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help ?? "")
    }
}

extension HoverableIconButton where Label == AnyView {
    /// SF-symbol form — parameter order matches the original memberwise
    /// init so every existing call site (trailing-closure action AND the
    /// explicit `action:rotation:` form) compiles unchanged.
    init(
        systemName: String,
        fontSize: CGFloat,
        size: CGFloat,
        help: String?,
        action: @escaping () -> Void,
        rotation: Double = 0
    ) {
        self.init(size: size, help: help, action: action, rotation: rotation) {
            AnyView(
                Image(systemName: systemName)
                    .font(.system(size: fontSize, weight: .medium))
            )
        }
    }
}
