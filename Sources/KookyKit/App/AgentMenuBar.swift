import AppKit
import Observation

/// App-level menu-bar view of `AgentMonitor` — the same cross-window agent
/// set that feeds the right sidebar. AppKit owns only the `NSStatusItem` and
/// native menu lifecycle; `AgentMonitor` remains the single source of truth.
@MainActor
final class AgentMenuBarController: NSObject, NSMenuDelegate {
    private let monitor: AgentMonitor
    private let settings: KookySettingsModel
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var observing = false

    init(
        monitor: AgentMonitor = .shared,
        settings: KookySettingsModel = .shared
    ) {
        self.monitor = monitor
        self.settings = settings
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    /// Starts a one-shot Observation loop. `AgentMonitor.entries` reads every
    /// session field that decides membership, so an agent starting/ending and
    /// a window being added/removed both refresh the count without a parallel
    /// notification system.
    func start() {
        guard !observing else { return }
        observing = true
        observe()
    }

    func stop() {
        observing = false
        removeStatusItem()
    }

    private func observe() {
        guard observing else { return }
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            // Observation fires at willSet. Read the settled model values on
            // the next main-actor turn, then register the one-shot tracker again.
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh() {
        guard settings.showAgentMenuBarItem else {
            removeStatusItem()
            return
        }
        let count = monitor.entries.count
        let item = ensureStatusItem()
        guard let button = item.button else { return }
        button.title = Self.countTitle(count)
        button.imagePosition = count == 0 ? .imageOnly : .imageLeading
        button.toolTip = count == 0 ? "No agents running" : "\(count) agent\(count == 1 ? "" : "s") active"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func ensureStatusItem() -> NSStatusItem {
        if let statusItem { return statusItem }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = KookyMenuBarIcon.make()
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        }
        item.menu = menu
        statusItem = item
        return item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // Rebuild at open time so titles, paths, states, ordering, and the session
    // set are current even if AppKit kept the native menu object around.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = monitor.entries
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: "No agents running", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for entry in entries {
            menu.addItem(menuItem(for: entry))
        }
    }

    private func menuItem(for entry: AgentMonitor.Entry) -> NSMenuItem {
        let item = NSMenuItem(
            title: Self.shortMenuText(entry.tabTitle),
            action: #selector(activateAgent(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = entry.id
        if #available(macOS 14.4, *) {
            item.subtitle = Self.shortMenuText("\(entry.locationLabel) · \(entry.state.label)")
        } else {
            // `NSMenuItem.subtitle` arrived after kooky's 14.0 floor. Keep
            // state visible on 14.0–14.3; the full path remains in the tooltip.
            item.title = Self.shortMenuText("\(entry.tabTitle) · \(entry.state.label)")
        }
        item.toolTip = entry.hoverText(tag: entry.tag)
        item.image = menuImage(for: entry.agent)
        item.isEnabled = true
        return item
    }

    private func menuImage(for agent: AgentTemplate) -> NSImage? {
        if let asset = agent.iconAsset, let source = AgentIcon.nsImage(asset: asset),
           let image = source.copy() as? NSImage {
            image.isTemplate = AgentIcon.isMonochrome(asset)
            return image
        }
        let image = NSImage(systemSymbolName: agent.symbol, accessibilityDescription: agent.title)
        image?.isTemplate = true
        return image
    }

    @objc private func activateAgent(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? UUID else { return }
        monitor.onActivate(sessionId)
    }

    static func countTitle(_ count: Int) -> String {
        count > 0 ? "\(count)" : ""
    }

    /// Native menu labels stay compact even when an OSC title or path is long.
    /// The full value remains available through the menu item's tooltip.
    static func shortMenuText(_ text: String, limit: Int = 30) -> String {
        guard limit > 0 else { return "" }
        let flattened = singleLine(text)
        guard flattened.count > limit else { return flattened }
        guard limit > 1 else { return "…" }
        return String(flattened.prefix(limit - 1)) + "…"
    }
}
