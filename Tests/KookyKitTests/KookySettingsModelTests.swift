import XCTest
@testable import KookyKit

@MainActor
final class KookySettingsModelTests: XCTestCase {
    func testShowSearchPillDefaultsToVisible() {
        XCTAssertTrue(
            KookySettingsModel.resolvedShowSearchPill(
                appearance: [:],
                legacyGeneral: [:]
            )
        )
    }

    func testShowSearchPillReadsLegacyGeneralKey() {
        XCTAssertFalse(
            KookySettingsModel.resolvedShowSearchPill(
                appearance: [:],
                legacyGeneral: ["showSearchPill": false]
            )
        )
    }

    func testShowSearchPillPrefersNewAppearanceKey() {
        XCTAssertTrue(
            KookySettingsModel.resolvedShowSearchPill(
                appearance: ["showSearchPill": true],
                legacyGeneral: ["showSearchPill": false]
            )
        )
    }

    func testAgentMenuBarItemDefaultsToVisible() {
        XCTAssertTrue(
            KookySettingsModel.resolvedShowInMenuBar(
                general: [:],
                legacyAppearance: [:]
            )
        )
    }

    func testAgentMenuBarItemReadsGeneralSetting() {
        XCTAssertFalse(
            KookySettingsModel.resolvedShowInMenuBar(
                general: ["showInMenuBar": false],
                legacyAppearance: [:]
            )
        )
    }

    func testAgentMenuBarItemMigratesAppearanceSetting() {
        XCTAssertFalse(
            KookySettingsModel.resolvedShowInMenuBar(
                general: [:],
                legacyAppearance: ["showAgentMenuBarItem": false]
            )
        )
        XCTAssertTrue(
            KookySettingsModel.resolvedShowInMenuBar(
                general: ["showInMenuBar": true],
                legacyAppearance: ["showAgentMenuBarItem": false]
            )
        )
    }

    func testAgentMenuBarTextIsCappedAtThirtyCharacters() {
        let exact = String(repeating: "a", count: 30)
        XCTAssertEqual(AgentMenuBarController.shortMenuText(exact), exact)

        let long = String(repeating: "b", count: 40)
        let shortened = AgentMenuBarController.shortMenuText(long)
        XCTAssertEqual(shortened.count, 30)
        XCTAssertTrue(shortened.hasSuffix("…"))
        XCTAssertEqual(AgentMenuBarController.shortMenuText("first\nsecond"), "first second")
    }

    func testAgentMenuBarCountIsHiddenWhenNoAgentIsRunning() {
        XCTAssertEqual(AgentMenuBarController.countTitle(0), "")
        XCTAssertEqual(AgentMenuBarController.countTitle(1), "1")
        XCTAssertEqual(AgentMenuBarController.countTitle(12), "12")
    }

    func testAgentMenuBarAppActionsAndAwakeModesFollowAgentList() throws {
        let monitor = AgentMonitor()
        let model = KookySettingsModel()
        model.awakeMode = .auto
        let controller = AgentMenuBarController(
            monitor: monitor,
            settings: model,
            onOpenKooky: {},
            onOpenSettings: {}
        )
        let menu = NSMenu()

        controller.menuNeedsUpdate(menu)

        XCTAssertEqual(menu.items.count, 6)
        XCTAssertEqual(menu.items[0].title, "No agents running")
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, "Open Kooky")
        XCTAssertEqual(menu.items[3].title, "Settings…")
        XCTAssertEqual(menu.items[4].title, "Keep Awake")
        XCTAssertEqual(menu.items[5].title, "Quit Kooky")

        let awakeItems = try XCTUnwrap(menu.items[4].submenu).items
        XCTAssertEqual(awakeItems.map(\.title), ["Off", "Auto", "Always"])
        XCTAssertEqual(awakeItems.map(\.state), [.off, .on, .off])
    }

    func testKookyMenuBarIconIsAnEighteenPointColourImage() {
        let image = KookyMenuBarIcon.make()
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(image.isTemplate)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    // MARK: - Custom agent persistence

    /// Every field must survive settings.json and come back. Serialise and
    /// parse are written as a pair but live in `save()` / `load()`, so a field
    /// added to one and forgotten in the other would silently reset on the
    /// user's next launch — an imported icon being the case that prompted
    /// this (issue #40).
    ///
    /// The reflection step is what gives the test teeth: every property of
    /// `CustomAgentData` defaults to `""`, so a newly added field would take
    /// its default here, round-trip as `"" == ""`, and pass while being
    /// dropped in production. Enumerating the live property list instead
    /// fails the moment a field exists that this test doesn't populate.
    func testCustomAgentFieldsAreAllRoundTripped() throws {
        let original = CustomAgentData(
            id: "custom-1",
            title: "My Agent",
            command: "aichat --model gpt-4",
            baseAgentId: AgentTemplate.claudeCodeID,
            iconAsset: "custom-1-deadbeef.png",
            symbol: "wand.and.stars",
            tintHex: "FF8800",
            env: "ANTHROPIC_BASE_URL=https://example.test"
        )
        for child in Mirror(reflecting: original).children {
            let name = child.label ?? "(unnamed)"
            let value = try XCTUnwrap(
                child.value as? String,
                "\(name) isn't a String — extend this test to cover its type"
            )
            XCTAssertFalse(
                value.isEmpty,
                "\(name) was added to CustomAgentData but left unset here, so the round trip "
                + "below can't tell whether the codec drops it"
            )
        }
        let dict = KookySettingsModel.serializeCustomAgents([original])
        XCTAssertEqual(
            dict.first?.count, Mirror(reflecting: original).children.count,
            "every field must reach settings.json"
        )
        XCTAssertEqual(try XCTUnwrap(KookySettingsModel.parseCustomAgents(dict).first), original)
    }

    /// Clearing an icon must drop the key entirely rather than write an empty
    /// string, so settings.json only ever carries what the user actually set.
    func testClearedIconDropsTheKey() {
        let dict = KookySettingsModel.serializeCustomAgents([CustomAgentData(id: "custom-1")])
        XCTAssertNil(dict.first?["iconAsset"])
        XCTAssertEqual(dict.first?.count, 1, "only `id` should remain")
    }

    func testParseDropsBuiltinCollisionsAndDuplicates() {
        let parsed = KookySettingsModel.parseCustomAgents([
            ["id": AgentTemplate.claudeCodeID, "title": "impostor"],
            ["id": "custom-1", "title": "first"],
            ["id": "custom-1", "title": "second"],
            ["title": "no id at all"],
        ])
        XCTAssertEqual(parsed.map(\.id), ["custom-1"])
        XCTAssertEqual(parsed.first?.title, "first")
    }
}
