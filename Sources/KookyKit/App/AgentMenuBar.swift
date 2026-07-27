import AppKit
import Observation

/// App-level menu-bar view of `AgentMonitor` — the same cross-window agent
/// set that feeds the right sidebar. AppKit owns only the `NSStatusItem` and
/// native menu lifecycle; `AgentMonitor` remains the single source of truth.
@MainActor
final class AgentMenuBarController: NSObject, NSMenuDelegate {
    private let monitor: AgentMonitor
    private let settings: KookySettingsModel
    private let onOpenKooky: () -> Void
    private let onOpenSettings: () -> Void
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var observing = false

    init(
        monitor: AgentMonitor = .shared,
        settings: KookySettingsModel = .shared,
        onOpenKooky: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.settings = settings
        self.onOpenKooky = onOpenKooky
        self.onOpenSettings = onOpenSettings
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
        guard settings.showInMenuBar else {
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
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No agents running", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in entries {
                menu.addItem(menuItem(for: entry))
            }
        }
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Open Kooky", action: #selector(openKooky)))
        menu.addItem(actionItem(title: "Settings…", action: #selector(showSettingsWindow)))

        let keepAwake = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        keepAwake.submenu = keepAwakeMenu()
        keepAwake.isEnabled = true
        menu.addItem(keepAwake)

        menu.addItem(actionItem(title: "Quit Kooky", action: #selector(quitKooky)))

        // AppKit injects standard symbols after insertion (notably a gear for
        // Settings…), even when the item was created with `image == nil`.
        // Clear the completed menu so every row stays deliberately text-only.
        for item in menu.items where !item.isSeparatorItem {
            item.image = nil
        }
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    private func keepAwakeMenu() -> NSMenu {
        let submenu = NSMenu(title: "Keep Awake")
        submenu.autoenablesItems = false
        for mode in AwakeMode.allCases {
            let item = NSMenuItem(
                title: Self.awakeModeTitle(mode),
                action: #selector(setAwakeMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.awakeMode == mode ? .on : .off
            item.isEnabled = true
            submenu.addItem(item)
        }
        return submenu
    }

    private func menuItem(for entry: AgentMonitor.Entry) -> NSMenuItem {
        let item = NSMenuItem(
            title: Self.shortMenuText(entry.tabTitle),
            action: #selector(activateAgent(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = entry.id
        item.toolTip = entry.hoverText(tag: entry.tag)
        item.isEnabled = true
        return item
    }

    @objc private func activateAgent(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? UUID else { return }
        monitor.onActivate(sessionId)
    }

    @objc private func openKooky() {
        onOpenKooky()
    }

    @objc private func showSettingsWindow() {
        onOpenSettings()
    }

    @objc private func setAwakeMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = AwakeMode(rawValue: rawValue) else { return }
        settings.applyAwakeMode(mode)
    }

    @objc private func quitKooky() {
        NSApp.terminate(nil)
    }

    static func awakeModeTitle(_ mode: AwakeMode) -> String {
        switch mode {
        case .off: return "Off"
        case .auto: return "Auto"
        case .always: return "Always"
        }
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
