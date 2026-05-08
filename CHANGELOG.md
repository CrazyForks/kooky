# Changelog

Notable changes per release. Tagged commits use `vX.Y` shortform.

## v0.1 — 2026-05-08

First public release. Native macOS terminal with vertical-tab workspaces and one-click AI agent sessions.

- **Terminal engine.** libghostty, Metal-accelerated, full ANSI/UTF-8/scrollback. `TerminalEngine` protocol abstracts the engine for tests and future swaps.
- **Session model.** Workspaces → Tabs. Sidebar lists workspaces; top tab bar lists each workspace's sessions. Closing the last tab closes the workspace; closing the last workspace closes the window.
- **Agent launcher.** Claude Code, Codex, Gemini CLI, OpenCode, Amp. The shell starts under a generated wrapper rc (zsh `ZDOTDIR` or bash `--rcfile` via a launcher script that re-execs as non-login) which `exec`s the agent inline before any prompt prints. No shell prompt or command echo before the agent UI.
- **Working-directory tracking.** OSC 7 `chpwd`/`PROMPT_COMMAND` hooks installed by the same wrappers; `GHOSTTY_ACTION_PWD` syncs `Session.currentDirectory`. The active tab's `cd` updates the workspace, new tabs and new workspaces inherit.
- **Chrome.** Onest (display) + JetBrains Mono (mono) registered at launch via `CTFontManager`. Brand PNG icons from lobe-icons. Sidebar leading icon shows the first non-terminal agent + a `+N` capsule for multi-agent workspaces; falls back to the terminal SF symbol for plain shells. Tab pill, sidebar row, and popover share one `hoverableRowBackground` modifier.
- **Tests.** 17 XCTest cases covering `AgentTemplate` (terminal vs agent shell selection, `KOOKY_AGENT` env wiring) and `WorkspaceStore` (initial state, add/close cascading, OSC 7 cwd inheritance). `WorkspaceStore.engineFactory` lets tests inject a no-op `TestEngine`.
