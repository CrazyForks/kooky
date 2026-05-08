import AppKit

struct TerminalSessionConfig {
    var command: String
    var arguments: [String]
    var workingDirectory: String?
    var environment: [String: String]

    static func defaultShell() -> TerminalSessionConfig {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? KookyShellIntegration.zshPath
        return TerminalSessionConfig(command: shell, arguments: ["--login"], workingDirectory: nil, environment: [:])
    }

    /// Pinned zsh — pairs with the ZDOTDIR wrapper for KOOKY_AGENT + OSC 7.
    static func zshShell() -> TerminalSessionConfig {
        TerminalSessionConfig(command: KookyShellIntegration.zshPath, arguments: ["--login"], workingDirectory: nil, environment: [:])
    }

    /// Bash via launcher script — direct `--rcfile` flags don't work because
    /// libghostty makes every `command` a login shell, which strips
    /// `--rcfile` semantics. Launcher re-execs as interactive non-login.
    static func bashShell(launcher: String) -> TerminalSessionConfig {
        TerminalSessionConfig(command: launcher, arguments: [], workingDirectory: nil, environment: [:])
    }
}

@MainActor
protocol TerminalEngine: AnyObject {
    var view: NSView { get }
    var backgroundColor: NSColor { get }
    /// Called when the engine observes a working-directory change (libghostty's
    /// `GHOSTTY_ACTION_PWD`, fired when the shell emits OSC 7). Lets the
    /// workspace track the active tab's cwd so new tabs inherit the latest path.
    var onPwdChange: ((String) -> Void)? { get set }
    func start(config: TerminalSessionConfig)
    func terminate()
}
