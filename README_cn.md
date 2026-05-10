# kooky

> *给写代码的人用的 macOS 终端。*

🇨🇳 中文  ·  🇬🇧 [English](README.md)

![kooky 截图：侧边栏里有三个 workspace，两个 pane 并排运行 Claude Code 和 Codex，`+` 菜单展开了五种内置 agent](screenshot.png)

很多终端是在 AI agent 进入日常开发之前设计的。**kooky 让 agent 会话和普通 shell 一样成为独立 tab**：Claude Code / Codex / Gemini CLI 可以跟 shell 放在一起，界面也会跟着每个 agent 的状态变化。开源、仅支持 macOS、MIT 许可。底层 GPU 渲染基于 [libghostty](https://github.com/ghostty-org/ghostty)。

**[下载最新版](https://github.com/iAmCorey/kooky/releases/latest)**  ·  [架构文档](ARCHITECTURE.md)  ·  [更新日志](CHANGELOG.md)

---

## 它做什么

**垂直 tab，但不是凑合的那种。** 侧边栏管理所有 workspace，可以在三种宽度间折叠（`⌘⌃S` 循环切换）。每个 pane 都有自己的 tab 栏，分屏方式接近 。tab 可以拖动排序，也可以拖到另一个 pane；整个会话会连同引擎状态和 scrollback 一起移动。重启后状态会恢复。

**一键启动 AI agent。** Claude Code · Codex · Gemini CLI · OpenCode · Amp。`+` 菜单里选一个，agent 会在第一个 prompt 出现前启动。侧边栏圆点显示每个 agent 的状态：运行中、需要处理，或者空闲。

**知道 shell 刚刚发生了什么。** OSC 133 / FinalTerm 钩子装在 kooky 自己的 ZDOTDIR 里，**不会改你的** `~/.zshrc`。上一条命令失败时，对应 tab 和 workspace 会出现红点；悬停可看到 `exit N · 12.4s`。pane 底部状态栏会显示 Git 分支、diff 统计、Node 版本和 Python env；Node 和 Git 分支可以点击切换。`⌘↑` / `⌘↓` 可以在 scrollback 里跳到上一个 / 下一个命令提示符。

**完整的键盘操作。** `⌘T` / `⌘N` 新建 tab / workspace · `⌘W` / `⌘⇧W` 关闭 · `⌘1-9` / `⌥⌘1-9` 切换 · `⌘D` / `⌘⇧D` 向右 / 向下分屏 · `⌘[` `⌘]` 切换焦点 · `⌘=` / `⌘-` / `⌘0` 调整字号 · `⌘K` 清屏。

**该有的 macOS 体验都有。** Onest + JetBrains Mono 字体。顶部 32pt 的 chrome 区域给红绿灯留出位置，并提供专门的窗口拖拽区域，避免拖窗口和拖 tab 抢手势。自定义 About 面板、带快捷键提示的原生菜单、中日韩 / 越南文等 IME 都支持。状态写在 `~/Library/Application Support/kooky/`，不连云、不发遥测、不需要账号。

## 安装

从 [Releases](https://github.com/iAmCorey/kooky/releases) 下载最新的 `.dmg`，打开后把 `Kooky.app` 拖进 `Applications` 文件夹。

**第一次启动会被 Gatekeeper 拦下来**，因为当前构建是 adhoc 签名（还没有 Apple Developer ID；公开分发签名和公证会等有真实用户后再做）。你会看到 *"Kooky cannot be opened because Apple cannot check it for malicious software"* 或者 *"is damaged and cannot be opened"* 这两类报错。下面三种方法任选一个即可：

<details>
<summary><b>方法 A —— 走系统设置 <i>(推荐)</i></b></summary>

1. 先双击一次 `Kooky.app`，macOS 会弹警告，把警告窗口关掉。
2. 打开 **系统设置 → 隐私与安全性**，往下翻到 **安全性** 这一段。
3. 看到 *"Kooky was blocked to protect your Mac"* 后，点旁边的 **Open Anyway**，输入密码。
4. 再双击一次 `Kooky.app`，这次会有 **Open** 按钮，点它即可。
</details>

<details>
<summary><b>方法 B —— 终端一行命令</b></summary>

```sh
xattr -d com.apple.quarantine /Applications/Kooky.app
```
</details>

<details>
<summary><b>方法 C —— 连 "Open Anyway" 按钮都没有</b></summary>

新版 Sequoia 有时会对 adhoc 签名的 app 完全不显示 "Open Anyway" 按钮。这种情况下可以先把旧版的 "Anywhere" 选项打开，再回去走方法 A：

```sh
sudo spctl --global-disable      # macOS 15+；老系统用 --master-disable
# 系统设置 → 隐私与安全性 → "Allow applications from" 选 Anywhere
# 双击 Kooky.app，这次应该可以启动
sudo spctl --global-enable       # Kooky 跑过一次之后，立刻把 Gatekeeper 打开
```

注意：这是**系统级开关**。关着的时候，macOS 会允许任何未签名 app 启动。Kooky 跑过一次就把它重新打开；系统会单独记住已经信任过 Kooky，以后不会再拦。
</details>

macOS **只拦第一次启动**。之后从 Spotlight、Dock、Finder 启动都跟普通 app 一样。

## 从源码构建

需要 Xcode 26+ 和 macOS 14+（Sonoma，`@Observable` 的最低系统要求）。

```sh
./scripts/setup-libghostty.sh        # 一次性：把预编译的 libghostty xcframework 下到 Vendor/
swift build
swift run                            # 开发模式直接跑
swift test                           # 67 个单测

./scripts/build-app.sh               # 产出 dist/Kooky.app
./scripts/build-dmg.sh --build       # 产出 dist/Kooky-vX.Y.Z.dmg
```

`Vendor/` 和 `dist/` 都在 `.gitignore` 里。libghostty 的 setup 脚本可以反复跑；SHA 没变时会直接跳过。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。打包进来的第三方资源保留各自的许可证，详见 [NOTICE.md](NOTICE.md)。
