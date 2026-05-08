# kooky

> **A terminal built for the coding experience.**
> 专为 coding 体验优化的 terminal。

An open-source macOS terminal with first-class vertical tabs and one-click AI agent sessions.

Built on **[libghostty](https://github.com/ghostty-org/ghostty)** for GPU-accelerated rendering. Native macOS UI via SwiftUI + AppKit.

## Status

M3 shipped — one-click agent launcher (Claude Code, Codex, Gemini CLI, OpenCode, Amp), per-tab working-directory tracking via OSC 7, workspace cwd that follows the active tab, refined chrome (custom Onest + JetBrains Mono fonts, brand icons from [lobe-icons](https://github.com/lobehub/lobe-icons)), and a 17-test XCTest suite. Up next: M4 — persistence + keyboard shortcuts (⌘T / ⌘W / ⌘1-9).

See [ARCHITECTURE.md](ARCHITECTURE.md) for the roadmap and design notes.

## Goals

- **Better vertical tabs.** Stable, fast, keyboard-driven, with persistent state.
- **One-click agent sessions.** Spin up Claude Code, Codex, Gemini CLI, or any other agent without typing the command.
- **macOS-native.** Feels like a Mac app, not a web view.
- **Zero cloud.** Fully local, no telemetry, no accounts.

## Building

Requires Xcode 26+ and macOS 15+.

```sh
# One-time: download the prebuilt GhosttyKit xcframework into Vendor/.
./scripts/setup-libghostty.sh

swift build
swift run
swift test          # 17 unit tests covering AgentTemplate + WorkspaceStore
```

`Vendor/` is gitignored; the setup script is idempotent and skips the download when the pinned SHA already matches.

## License

MIT — see [LICENSE](LICENSE). Bundled third-party assets retain their upstream licenses; see [NOTICE.md](NOTICE.md).
