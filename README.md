# kooky

> **A terminal built for the coding experience.**
> 专为 coding 体验优化的 terminal。

An open-source macOS terminal with first-class vertical tabs and one-click AI agent sessions.

Built on **[libghostty](https://github.com/ghostty-org/ghostty)** for GPU-accelerated rendering. Native macOS UI via SwiftUI + AppKit.

## Status

v0.7.4 — Per-tab + per-workspace command-status dots driven by OSC 133 / FinalTerm shell integration: a small red dot on the failing tab pill (hover for `exit N · 12.4s`), the same red surfaces on the workspace row whenever any tab in any pane has a non-zero last exit. `⌘↑` / `⌘↓` jump to the previous / next prompt. ZDOTDIR wrapper installs the OSC 133 hooks (`precmd` emits A+D, PROMPT carries B re-injected each redraw, `preexec` emits C) without touching your `~/.zshrc`. Earlier on v0.7.x: tab + workspace manual rename via right-click → *Rename…* popover with empty-input clear-to-cwd semantics; URL ⌘+click in any terminal opens in your default browser; mouse shape follows libghostty (URL → pointing-hand, vim split → resize, etc.); `⌘=` / `⌘-` / `⌘0` font size; `⌘K` Clear Pane; sidebar mode (full / compact / hidden) persists across launches; About panel now sourced from `KookyApp` constants, never lies about which version is running. v0.7: Three-state collapsible sidebar (full / 52pt icon-only / hidden, `⌘⌃S` cycles), 32pt top chrome strip with traffic-light clearance + sidebar toggle + explicit `WindowDragHandle` (`window.isMovable = false` globally so tab DnD always beats AppKit's implicit title-bar drag). View menu becomes the navigation hub. New Help menu (Report Issue / View on GitHub) and DEBUG-only Debug menu (Cycle Activity previews idle → running → failure → attention in 4 keystrokes). v0.6: drag-reorder workspaces and tabs, cross-pane tab move that preserves session state (same engine / scrollback / agent), `+` doubles as drop-at-end target, double-click tab bar = Zoom, right-click menu shortcut hints, declarative menu DSL. v0.5:  splits — recursive `PaneNode` tree, per-pane tab bars, `⌘D` / `⌘⇧D` split, drag-resize divider, click-to-focus via libghostty's first-responder hook. Earlier still: Codex hooks via `notify` + wrapper bracketing, Claude Code full hooks, IME (中日韩 / 越南文 / etc.) via `NSTextInputClient`, keyboard shortcuts, workspace + tab persistence, hidden title bar, agent launcher (Claude Code / Codex / Gemini CLI / OpenCode / Amp) with inline auto-launch, OSC 7 cwd tracking, Onest + JetBrains Mono chrome, brand icons from [lobe-icons](https://github.com/lobehub/lobe-icons). 31-test XCTest suite. Up next: Gemini / OpenCode / Amp wrappers, then `.app` bundle + Settings UI.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the roadmap and design notes.

## Goals

- **Better vertical tabs.** Stable, fast, keyboard-driven, with persistent state.
- **One-click agent sessions.** Spin up Claude Code, Codex, Gemini CLI, or any other agent without typing the command.
- **macOS-native.** Feels like a Mac app, not a web view.
- **Zero cloud.** Fully local, no telemetry, no accounts.

## Install

Download the latest `Kooky-vX.Y.Z.dmg` from [Releases](https://github.com/iAmCorey/kooky/releases), open it, drag `Kooky.app` to `Applications`.

**First launch will be blocked by Gatekeeper** because the build is adhoc-signed (no paid Apple Developer ID yet — public-distribution signing + notarization are deferred until the project has real users). Bypass once with either:

```sh
# Option A — right-click in Finder, hold ⌃, click "Open"
# Option B — strip the quarantine attribute one-shot:
xattr -d com.apple.quarantine /Applications/Kooky.app
```

After the first launch, macOS remembers and won't ask again.

## Building from source

Requires Xcode 26+ and macOS 15+.

```sh
# One-time: download the prebuilt GhosttyKit xcframework into Vendor/.
./scripts/setup-libghostty.sh

swift build
swift run
swift test          # 31 unit tests covering AgentTemplate + WorkspaceStore (incl. persistence + splits + cross-pane move + OSC 133 command status)

# Produce a real macOS .app bundle (writes dist/Kooky.app):
./scripts/build-app.sh

# Package as DMG for distribution (writes dist/Kooky-vX.Y.Z.dmg):
./scripts/build-dmg.sh --build
```

`Vendor/` and `dist/` are gitignored. The libghostty setup script is idempotent and skips the download when the pinned SHA already matches.

## License

MIT — see [LICENSE](LICENSE). Bundled third-party assets retain their upstream licenses; see [NOTICE.md](NOTICE.md).
