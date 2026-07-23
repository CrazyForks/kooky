# kooky

[![License](https://img.shields.io/github/license/iAmCorey/kooky?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/iAmCorey/kooky?style=flat-square)](https://github.com/iAmCorey/kooky/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-007AFF?style=flat-square)](https://github.com/iAmCorey/kooky/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/iAmCorey/kooky/total?style=flat-square)](https://github.com/iAmCorey/kooky/releases)
[![Stars](https://img.shields.io/github/stars/iAmCorey/kooky?style=flat-square)](https://github.com/iAmCorey/kooky/stargazers)

> *A minimal modern terminal for AI coding.*

🇬🇧 English  ·  🇨🇳 [中文](README_CN.md)  ·  🇯🇵 [日本語](README_JA.md)

![kooky](img/screenshot-1.png)

A minimal modern terminal built for AI coding. Sidebar workspaces; horizontal / vertical split panes; one-click agent launch; per-agent activity readout; live workspace state with one-click Node and branch switching. Open-source, MIT-licensed. No accounts, no telemetry; app state stays local. GPU rendering via [libghostty](https://github.com/ghostty-org/ghostty).

**[Download latest](https://github.com/iAmCorey/kooky/releases/latest)**  ·  [Changelog](CHANGELOG.md)

---

## Features

**Vertical tabs, split panes & windows.** Sidebar workspaces with three-state collapse (`⌘⌃S`); drag the sidebar's right edge to widen it, and the width sticks per window. Each pane owns its own tab strip and active tab; split it right or down from the two buttons on its tab bar, or with ⌘D / ⌘⇧D. Rename a tab with ⌘R, a workspace with ⌘⇧R. `⌘⇧N` opens another window. Drag a tab to reorder it, move it across panes, or drop it into a different window — the live session moves whole, scrollback and running process intact. State persists across launches; every open window is restored. Open any folder as a new workspace: drop it onto the sidebar from Finder, or use ⌘O. Press `⌘⇧E` to zoom the active pane to fullscreen and back — the other panes slide off-screen but their processes keep running.

![Vertical tabs on the left, one pane split into four](img/screenshot-2.png)

**One-click AI agent sessions.** Claude Code · Codex · Gemini CLI · OpenCode · Amp · Cursor CLI · Copilot CLI · Grok Build · Antigravity CLI · Kimi Code · Pi · Kiro CLI · Droid. Pick one from the `+` menu; the agent boots before your first prompt prints. Agent conversations auto-resume across kooky restarts using each CLI's exact session ID, so closing and reopening a tab picks up where you left off.

![Every supported agent, each toggleable in Settings](img/screenshot-4.png)

**Git worktrees.** Right-click any git workspace → "Create Worktree…" to spin one up on a new branch (or check out an existing one). Each worktree shows up nested under its source repo in the sidebar with its own tabs + agent — let Claude work on a feature branch without touching what's running on main. Worktrees you create from the command line show up automatically the next time you launch kooky.

**SSH workspaces.** File → New SSH Workspace… (or ⌘P) creates a workspace that lives on a remote machine: every new tab, split, and restored tab reconnects to the same host on its own. Agent tabs start their agent on the remote — with the remote's own shell setup loaded, so tools installed through nvm and friends are found. Paste a local file or screenshot and kooky uploads it first, then pastes a path the remote agent can actually open. Connections to the same host are shared: extra tabs attach instantly, and password-authenticated hosts work throughout, pasting included.

**Keep-awake.** Your Mac won't fall asleep under a working agent. A breathing status light in the top bar cycles three notches: Off; Auto — awake while an agent works or an SSH session is live, lid closed included (one-time admin authorization), asleep again the moment the work ends; and Always — a caffeinate you can see, awake until you switch it down. Flip sleep-disable anywhere else (`sudo pmset`, another tool) and the dial follows within seconds, in both directions.

**Recent projects.** kooky remembers every folder you open a workspace on — no setup, no manual adding. Reopen one from File → Open Recent, or press ⌘P and type the project's name: closed projects show up as "recent" entries and reopen with a single Enter. Deleted folders hide automatically, and worktree / SSH directories never clutter the list.

**Right-click a selection → "Ask <agent>".** Select an error / log line / file path, right-click, pick any agent — a new tab spawns with the selection already submitted as the first prompt. Zero ⌘C / ⌘V to go from "what is this" to an actual answer.

**Quick Open (⌘P).** Fuzzy-search across every window's workspaces, tabs, agents, Terminal presets, and recent project folders from one floating panel. Type to filter, ↑↓ to navigate, Enter to jump or spawn. Triggers from ⌘P or the search pill in the top chrome.

**Sidebar file tree.** A toggle at the bottom of the sidebar swaps the workspace list for a file tree of the active workspace's folder. Expand directories, double-click to open a file, right-click for Reveal in Finder / Copy Path / Insert Path into Terminal (file rows also get Open) — or just drag a file or folder straight into the terminal to insert its escaped path, same as a Finder drag. Changed files show their `+X −Y` line counts (the same numbers the status bar totals), and a collapsed folder rolls up its subtree's changes. The tree follows the active tab's directory (worktree workspaces stay pinned to their worktree folder) and refreshes live as files change on disk.

**Friction-free input.** Hold ⌘ and click a local file path such as `/path/file.swift:42` to open it in your preferred editor; web links can use a preferred browser (Settings → General → Open With). Click anywhere on the zsh prompt to move the shell cursor there (no modifier needed, same UX as ghostty.app). Drag a file or folder from Finder onto any pane to drop its escaped absolute path at the cursor.

**Prompt composer (⌘L).** A chat-style box rises from the bottom of the pane for writing a long, multi-line prompt without a stray Return firing it off mid-thought. Return sends it to the current agent (or shell), Shift+Return adds a newline, Esc cancels and keeps your draft. Open it with ⌘L or the compose button in the pane status bar.

**Agent activity readout.** Sidebar dot tracks each agent in real time — running (blue), waiting on you (amber), idle (none). Tab + workspace dots also turn red when the last command exited non-zero; hover for `exit N · 12.4s`. For Claude Code and Pi sessions, the pane status bar also shows the tool the agent is running right now (Bash / Edit / Read / etc.) and how long — click the pill for the full session history; failed calls turn red immediately. Toggle the pill per agent in Settings → Status Bar.

**Works with zsh, bash, and fish.** Manually-typed agent detection, cwd tracking, the status-bar slots, and one-click agent launch behave the same across all three shells — and keep working even alongside shell autocomplete tools like Fig / Amazon Q / kiro.

**Notifications.** When an agent in a tab you're not looking at starts waiting on you, or a command there fails, kooky posts a macOS notification — turn each kind on or off in Settings → Notifications. A bell in the top bar (⇧⌘I) keeps a running inbox of those alerts across every window — who's waiting, what failed, what finished — with a red dot when something's unread. Click an entry to jump straight to that tab; switching to a tab clears its alerts on its own.

![The notification center, collected across every window](img/screenshot-3.png)

**Agent panel.** A right-side sidebar — toggle in the top bar, three collapse states like the left one — lists every agent across all your windows at once, sorted by who needs you first: waiting on you, then failed, then running, then idle. Click any row to jump straight to that tab; compact mode shrinks it to a rail of status-tinted icons.

**Open in your editor or terminal.** A split button in the top bar hands the current tab's directory to another app. Click the icon to reopen in your last-used app, or the chevron to pick from any supported app installed on your Mac: VS Code · Cursor · Windsurf · Zed · Sublime Text · Antigravity · Trae · Kiro · Xcode · IntelliJ IDEA · PyCharm · WebStorm · Terminal · iTerm · Ghostty · Warp · Finder. Reorder or hide them under Settings → Open in.

**Live workspace state.** Pane status bar shows the git repo + branch + diff (`N files +X −Y`), Python venv, Node version, active proxy (`https_proxy` / `http_proxy` / `all_proxy`), and — when you SSH into a remote — the `user@host` you're logged into (turn it on under Settings → General). Auto-refreshes when an agent's Bash tool or another terminal switches branches. Click the Node or branch pill to switch versions / branches without typing; click the repo pill to open it on GitHub (GitLab / Bitbucket too), copy its URL, or reveal it in Finder; click the proxy pill to see and copy the full `name=value`.

**SwiftUI-native, minimal chrome.** Onest + JetBrains Mono. Custom About panel, native menus with shortcut hints, full IME support.

**Configurable.** Settings (`⌘,`) covers themes, font, cursor, default new-tab behavior, Terminal presets, agents, Open in, and the pane status bar. Theme changes update the whole window immediately, including custom Ghostty themes in your themes folder.

**Local by default.** No accounts, no telemetry, no cloud sync. Kooky keeps its own state on your device.

**libghostty-powered.** GPU-accelerated cell rendering, same engine as ghostty — synced to your display's refresh rate, so scrolling stays smooth and tear-free on 120Hz / ProMotion screens.

## Install

Download the latest `.dmg` from [Releases](https://github.com/iAmCorey/kooky/releases). Open it and drag `Kooky.app` to `Applications`.

**First launch is blocked by Gatekeeper** because the build is adhoc-signed (no Apple Developer ID yet — public-distribution signing and notarization will come when there are real users). You'll see *"Kooky cannot be opened because Apple cannot check it for malicious software"* or *"is damaged and cannot be opened"*. Pick whichever bypass works for you:

<details>
<summary><b>Path A — System Settings <i>(recommended)</i></b></summary>

1. Double-click `Kooky.app`. If shows the warning. Dismiss it.
2. **System Settings → Privacy & Security**, scroll to **Security**.
3. Click **Open Anyway** next to *"Kooky was blocked to protect your Mac"*. Enter your password.
4. Double-click `Kooky.app` again → click **Open**. Done.
</details>

<details>
<summary><b>Path B — Terminal (one-liner)</b></summary>

```sh
xattr -d com.apple.quarantine /Applications/Kooky.app
```
</details>

<details>
<summary><b>Path C — when "Open Anyway" doesn't appear at all</b></summary>

Sequoia sometimes hides the Open Anyway button entirely for adhoc-signed apps. Re-enable the legacy "Anywhere" option, then redo Path A:

```sh
sudo spctl --global-disable      # macOS 15+; older systems use --master-disable
# System Settings → Privacy & Security → "Allow applications from" → Anywhere
# Open Kooky.app → it now launches
sudo spctl --global-enable       # turn Gatekeeper back on
```

This is **system-wide** while disabled. Re-enable as soon as kooky launches once (the per-app whitelist persists).
</details>

macOS only blocks the first launch. After that, Spotlight / Dock / Finder all work normally.

## Build from source

Requires Xcode 26+ and macOS 14+ (Sonoma — `@Observable` is the floor).

```sh
./scripts/setup-libghostty.sh        # one-time: fetch the libghostty xcframework
swift build
swift run                            # dev mode
swift test                           # 547 unit tests

./scripts/build-app.sh               # writes dist/Kooky.app
./scripts/build-dmg.sh --build       # writes dist/Kooky-vX.Y.Z.dmg
```

`Vendor/` and `dist/` are gitignored. The libghostty setup script is idempotent.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=iAmCorey/kooky&type=Date)](https://star-history.com/#iAmCorey/kooky&Date)

## License

MIT — see [LICENSE](LICENSE). Bundled third-party assets retain their upstream licenses; see [NOTICE.md](NOTICE.md).
