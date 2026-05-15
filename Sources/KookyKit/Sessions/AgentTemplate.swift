import AppKit
import Foundation
import SwiftUI

/// A named profile that turns into a `TerminalSessionConfig` when the user
/// picks it from the "+" menu. The shell starts under our wrapper `.zshrc`
/// (KookyShellIntegration), which sources the user's config, then — if
/// `KOOKY_AGENT` is set — invokes the agent inline. The user never sees the
/// shell prompt or the command echo, and on agent exit they land in a clean
/// shell prompt with their full PATH/aliases intact.
struct AgentTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    /// SF Symbol used when `iconAsset` is nil or fails to load.
    let symbol: String
    /// Filename (without extension) of a bundled PNG in `Resources/Icons/`.
    /// Sourced from github.com/lobehub/lobe-icons (MIT).
    let iconAsset: String?
    /// Brand-derived hue used for compact indicators (sidebar status pips).
    /// Picked from each lobe-icon's dominant fill so a row's pip group reads as
    /// the same family of marks shown elsewhere. sRGB hex.
    let tintHex: String?
    let initialCommand: String?

    var tint: Color? {
        tintHex.flatMap(Color.init(hex:))
    }

    /// `extraOptions` is appended after `initialCommand` (space-separated)
    /// when forming `KOOKY_AGENT`. The wrapper rc's `eval` splits on
    /// whitespace, so the caller handles its own quoting for tokens that
    /// contain spaces.
    func makeSessionConfig(extraOptions: String? = nil) -> TerminalSessionConfig {
        // Pick a shell that has a kooky integration wrapper. Plain terminal
        // sessions respect $SHELL where we have a wrapper (zsh/bash); other
        // shells (fish/nu/...) get $SHELL too, just without cwd tracking.
        // Agent sessions force a wrapped shell so KOOKY_AGENT auto-launch
        // works — `.other` users get zsh as a working fallback.
        var config: TerminalSessionConfig
        switch (KookyShellIntegration.detectedUserShell, initialCommand) {
        case (.bash, _):
            config = .bashShell(launcher: KookyShellIntegration.bashLauncherPath)
        case (.zsh, _):
            config = .zshShell()
        case (.other, .none):
            config = .defaultShell()
        case (.other, .some):
            config = .zshShell()
        }
        if let initialCommand {
            let trimmedExtras = extraOptions?.trimmingCharacters(in: .whitespaces) ?? ""
            config.environment["KOOKY_AGENT"] = trimmedExtras.isEmpty
                ? initialCommand
                : "\(initialCommand) \(trimmedExtras)"
        }
        return config
    }
}

extension AgentTemplate {
    static let terminal = AgentTemplate(
        id: "terminal",
        title: "Terminal",
        symbol: "terminal",
        iconAsset: nil,
        tintHex: nil,
        initialCommand: nil
    )

    static let claudeCode = AgentTemplate(
        id: "claude-code",
        title: "Claude Code",
        symbol: "sparkle",
        iconAsset: "claudecode",
        tintHex: "D97757",
        initialCommand: "claude"
    )

    static let codex = AgentTemplate(
        id: "codex",
        title: "Codex",
        symbol: "chevron.left.forwardslash.chevron.right",
        iconAsset: "codex",
        tintHex: "7A9DFF",
        initialCommand: "codex"
    )

    static let gemini = AgentTemplate(
        id: "gemini",
        title: "Gemini CLI",
        symbol: "diamond",
        iconAsset: "gemini",
        tintHex: "3186FF",
        initialCommand: "gemini"
    )

    static let opencode = AgentTemplate(
        id: "opencode",
        title: "OpenCode",
        symbol: "curlybraces",
        iconAsset: "opencode",
        tintHex: "B0B0B0",
        initialCommand: "opencode"
    )

    static let amp = AgentTemplate(
        id: "amp",
        title: "Amp",
        symbol: "bolt.fill",
        iconAsset: "amp",
        tintHex: "E8B168",
        initialCommand: "amp"
    )

    static let cursor = AgentTemplate(
        id: "cursor",
        title: "Cursor CLI",
        symbol: "cube",
        iconAsset: "cursor",
        tintHex: "F54E00",
        initialCommand: "cursor-agent"
    )

    static let copilot = AgentTemplate(
        id: "copilot",
        title: "GitHub Copilot",
        symbol: "hexagon.fill",
        iconAsset: "githubcopilot",
        tintHex: "6E40C9",
        initialCommand: "copilot"
    )

    /// The 8 templates shipped with kooky. User-defined custom agents are
    /// merged on top via `all` at runtime.
    static let builtin: [AgentTemplate] = [.terminal, .claudeCode, .codex, .gemini, .opencode, .amp, .cursor, .copilot]

    /// All templates available right now — `builtin` plus the user's custom
    /// agents from Settings → Coding Agents. MainActor-isolated because it
    /// reads `KookySettingsModel.shared` to materialise custom entries.
    @MainActor
    static var all: [AgentTemplate] {
        builtin + KookySettingsModel.shared.customAgents.map(AgentTemplate.fromCustom)
    }

    /// Looks up a template by the slug an agent's hook system reports — the
    /// same string as the template's `initialCommand` (the binary name the
    /// user types). Returns nil for unknown slugs. MainActor because it
    /// pulls the live `all` (built-in + custom).
    @MainActor
    static func from(hookSlug: String) -> AgentTemplate? {
        all.first { $0.initialCommand == hookSlug }
    }

    /// All non-terminal templates resolved against the user's saved order.
    /// Templates absent from `model.agentOrder` (typically: a fresh kooky
    /// install, or an agent shipped in a newer version) are appended in
    /// their `AgentTemplate.all` position so nothing silently disappears.
    @MainActor
    static func ordered(model: KookySettingsModel) -> [AgentTemplate] {
        let nonTerminal = all.filter { $0.id != "terminal" }
        // Use `uniquingKeysWith` so a hand-edited settings.json that puts a
        // custom agent on a builtin id (or two customs on the same id) lands
        // on the first occurrence instead of crashing the launcher. Builtin
        // entries are appended first in `all`, so they win the tie.
        let byId = Dictionary(nonTerminal.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let userOrderIds = model.agentOrder.filter { byId.keys.contains($0) }
        let userOrderSet = Set(userOrderIds)
        let missing = nonTerminal.filter { !userOrderSet.contains($0.id) }
        return userOrderIds.compactMap { byId[$0] } + missing
    }

    /// What the `+` menu renders: Terminal pinned first (not user-controlled),
    /// then `ordered(model:)` filtered to visible agents whose `initialCommand`
    /// is set. The `initialCommand != nil` gate skips half-configured custom
    /// agents (just-added or command-cleared) so the launch surface never
    /// offers a row that would spawn a plain Terminal but get recorded as
    /// that custom agent. They still appear in Settings → Coding Agents so
    /// the user can finish editing them.
    @MainActor
    static func visibleOrdered(model: KookySettingsModel) -> [AgentTemplate] {
        [.terminal] + ordered(model: model).filter {
            !model.hiddenAgents.contains($0.id) && $0.initialCommand != nil
        }
    }

    /// Resolves the user's chosen default template for `+` / `⌘T`. Returns
    /// `nil` (meaning "no default, show the picker") when the saved id is
    /// missing, unknown, or points to an agent the user has since hidden.
    /// Looking the id up in `visibleOrdered` gives the stale-default-after-
    /// hide fallback for free; Terminal is always present there so it stays
    /// selectable even though it's not customisable from the Settings list.
    @MainActor
    static func defaultLaunchTemplate(model: KookySettingsModel) -> AgentTemplate? {
        guard let id = model.defaultAgentId else { return nil }
        return visibleOrdered(model: model).first { $0.id == id }
    }

    /// Materialises a user-defined custom agent into a runtime `AgentTemplate`.
    /// `iconAsset` stays nil — v1 only supports SF Symbol fallbacks for custom
    /// agents, not bundled PNGs.
    static func fromCustom(_ data: CustomAgentData) -> AgentTemplate {
        AgentTemplate(
            id: data.id,
            title: data.title.isEmpty ? data.id : data.title,
            symbol: data.symbol.isEmpty ? "wand.and.stars" : data.symbol,
            iconAsset: nil,
            tintHex: data.tintHex.isEmpty ? nil : data.tintHex,
            initialCommand: data.command.isEmpty ? nil : data.command
        )
    }
}

/// User-defined agent entry. Stored in `settings.json` under
/// `agents.custom`; round-tripped through `KookySettingsModel.customAgents`.
struct CustomAgentData: Hashable, Identifiable {
    /// Slug — must be unique across builtin + custom. Generated as
    /// `custom-N` on creation; user-editable from Settings.
    var id: String
    /// Display title shown in the `+` menu and Settings row.
    var title: String
    /// Full launch command, e.g. `aichat --model gpt-4o`. Whitespace-split
    /// by the wrapper's `eval`, same as the `agents.options` field.
    var command: String
    /// SF Symbol fallback. Falls back to `wand.and.stars` if user typoed.
    var symbol: String
    /// Optional sRGB hex (no `#`) for the sidebar pip tint. Empty = no tint.
    var tintHex: String

    init(id: String, title: String = "", command: String = "", symbol: String = "wand.and.stars", tintHex: String = "") {
        self.id = id
        self.title = title
        self.command = command
        self.symbol = symbol
        self.tintHex = tintHex
    }
}
