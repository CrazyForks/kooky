import XCTest
@testable import KookyKit

final class AgentTemplateTests: XCTestCase {
    func testTerminalTemplateHasNoAgentEnv() {
        XCTAssertNil(AgentTemplate.terminal.makeSessionConfig().environment["KOOKY_AGENT"])
    }

    func testAgentTemplatesPublishKookyAgentEnv() {
        XCTAssertEqual(AgentTemplate.claudeCode.makeSessionConfig().environment["KOOKY_AGENT"], "claude")
        XCTAssertEqual(AgentTemplate.codex.makeSessionConfig().environment["KOOKY_AGENT"], "codex")
        XCTAssertEqual(AgentTemplate.gemini.makeSessionConfig().environment["KOOKY_AGENT"], "gemini")
        XCTAssertEqual(AgentTemplate.opencode.makeSessionConfig().environment["KOOKY_AGENT"], "opencode")
        XCTAssertEqual(AgentTemplate.amp.makeSessionConfig().environment["KOOKY_AGENT"], "amp")
    }

    func testAllTemplatesAreUniqueAndIncludeTerminal() {
        let ids = AgentTemplate.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids must be unique")
        XCTAssertTrue(ids.contains("terminal"))
    }

    func testTerminalTemplateUsesUserDefaultShell() {
        let expected = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        XCTAssertEqual(AgentTemplate.terminal.makeSessionConfig().command, expected)
    }

    func testAgentTemplatesPickAShellWithIntegrationWrapper() {
        // Agent must run under one of our wrappers (zsh ZDOTDIR or bash
        // --rcfile) — anything else means KOOKY_AGENT never fires.
        for template in [AgentTemplate.claudeCode, .codex, .gemini, .opencode, .amp] {
            let cmd = template.makeSessionConfig().command
            XCTAssertTrue(
                cmd == "/bin/zsh" || cmd.contains("kooky-bash-launch-"),
                "agent template \(template.id) launched without a kooky shell wrapper: \(cmd)"
            )
        }
    }
}
