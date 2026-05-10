# kooky

> *A macOS terminal built for the coding experience.*

🇬🇧 English  ·  🇨🇳 [中文](README_cn.md)

![kooky — sidebar with three workspaces, two panes running Claude Code and Codex side by side, the `+` menu showing the five built-in agent templates](screenshot.png)

Existing terminals were built before AI agents lived in your dev loop. **kooky treats agent sessions as first-class tabs** — Claude Code, Codex, and Gemini CLI live next to your shells, and the chrome reacts to what each one is doing. Open-source, macOS-only, MIT. GPU rendering via [libghostty](https://github.com/ghostty-org/ghostty).

**[Download latest](https://github.com/iAmCorey/kooky/releases/latest)**  ·  [Architecture notes](ARCHITECTURE.md)  ·  [Changelog](CHANGELOG.md)

---

## What it does

**Vertical tabs that don't suck.** Sidebar workspace list with three-state collapse (`⌘⌃S`). Each pane owns its own tab strip, . Drag tabs to reorder; drag across panes to move sessions whole. State persists across launches.

**One-click AI agent sessions.** Claude Code · Codex · Gemini CLI · OpenCode · Amp. Pick one from the `+` menu — the agent boots before your first prompt prints. Sidebar dot tracks per-agent activity (running / attention / idle).

**Knows what your shell did.** OSC 133 / FinalTerm hooks installed via a ZDOTDIR wrapper that **does not touch** your `~/.zshrc`. Per-tab + per-workspace red dot when the last command failed; hover for `exit N · 12.4s`. Pane status bars show git branch, diff stats, Node version, and Python env; click the Node or branch pill to switch. `⌘↑` / `⌘↓` jump between prompts in scrollback.

**Full keyboard.** `⌘T` / `⌘N` new tab / workspace · `⌘W` / `⌘⇧W` close · `⌘1-9` / `⌥⌘1-9` switch · `⌘D` / `⌘⇧D` split right / down · `⌘[` `⌘]` focus pane · `⌘=` / `⌘-` / `⌘0` font size · `⌘K` clear pane.

**Real macOS chrome.** Onest + JetBrains Mono. 32pt top strip with traffic lights and a window-drag handle that wins the title-bar-vs-tab-DnD race. Custom About panel, native menus with shortcut hints, IME for 中日韩 / Vietnamese / etc. State lives in `~/Library/Application Support/kooky/`; no cloud, no telemetry, no accounts.

## Install

Download the latest `.dmg` from [Releases](https://github.com/iAmCorey/kooky/releases). Open it and drag `Kooky.app` to `Applications`.

**First launch is blocked by Gatekeeper** because the build is adhoc-signed (no Apple Developer ID yet — public-distribution signing and notarization will come when there are real users). You'll see *"Kooky cannot be opened because Apple cannot check it for malicious software"* or *"is damaged and cannot be opened"*. Pick whichever bypass works for you:

<details>
<summary><b>Path A — System Settings <i>(recommended)</i></b></summary>

1. Double-click `Kooky.app`. macOS shows the warning. Dismiss it.
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
swift test                           # 67 unit tests

./scripts/build-app.sh               # writes dist/Kooky.app
./scripts/build-dmg.sh --build       # writes dist/Kooky-vX.Y.Z.dmg
```

`Vendor/` and `dist/` are gitignored. The libghostty setup script is idempotent.

## License

MIT — see [LICENSE](LICENSE). Bundled third-party assets retain their upstream licenses; see [NOTICE.md](NOTICE.md).
