import AppKit
import SwiftUI

/// `confirm-close-surface`: closing a tab whose process is still working
/// (vim, a build, an agent) asks first. Only USER-initiated single-tab
/// closes route here (⌘W, the tab's ✕, right-click Close) — workspace/window
/// cascades and process-exit auto-close call `closeTab` directly, so closing
/// a window can't stack N confirmations. The judgment is the core's own
/// (`needsConfirmQuit` = config × live child process; a dead child never
/// confirms), and kooky's baseline pins the config to false — this whole
/// path is opt-in via `terminal.confirm-close-surface`.
@MainActor
enum ConfirmCloseTab {
    static func request(_ session: Session, in workspace: Workspace, store: WorkspaceStore) {
        // The tab bar's ✕ can target a background tab whose engine view is
        // detached (window nil) — anchor on the key window then.
        guard session.engine.needsConfirmQuit,
              let window = session.engine.view.window ?? NSApp.keyWindow
        else {
            store.closeTab(session, in: workspace)
            return
        }
        ConsentSheetController.present(
            on: window,
            onDecision: { [weak store, weak session, weak workspace] confirmed in
                guard confirmed, let store, let session, let workspace else { return }
                store.closeTab(session, in: workspace)
            }
        ) { decide in
            ConfirmCloseSheet(tabTitle: session.title, decide: decide)
        }
    }
}

private struct ConfirmCloseSheet: View {
    let tabTitle: String
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "CLOSE-TAB", bundle: .kookyResources))
                .font(Theme.mono(10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(Theme.chromeMuted.opacity(0.85))
                .padding(.bottom, 18)

            Text(String.localizedStringWithFormat(
                String(localized: "Close “%@”?", bundle: .kookyResources),
                tabTitle
            ))
                .font(Theme.display(20, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(2)

            Text(String(localized: "A process is still running in this tab; closing will terminate it.", bundle: .kookyResources))
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            HStack(spacing: 10) {
                Spacer()
                BracketButton("cancel") { decide(false) }
                    .keyboardShortcut(.cancelAction)
                BracketButton("close tab") { decide(true) }
            }
            .padding(.top, 22)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .frame(width: 460, alignment: .topLeading)
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }
}
