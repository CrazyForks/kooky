import XCTest
@testable import KookyKit

@MainActor
final class KookyTerminalThemeTests: XCTestCase {
    func testPresetLookupAcceptsStableId() {
        let theme = KookyTerminalTheme.preset(for: "solarized-light")
        XCTAssertEqual(theme?.title, "Solarized Light")
    }

    func testPresetLookupAcceptsLegacyDisplayName() {
        let theme = KookyTerminalTheme.preset(for: "Solarized Light")
        XCTAssertEqual(theme?.id, "solarized-light")
    }

    func testPresetExpandsToConcreteGhosttyColors() {
        let theme = KookyTerminalTheme.preset(for: "dracula")
        XCTAssertEqual(theme?.lines.first, "background = #282A36")
        XCTAssertEqual(theme?.lines.filter { $0.hasPrefix("palette = ") }.count, 16)
    }

    func testNewPresetsAreRegistered() {
        for id in [
            "tokyo-night", "tokyo-day", "gruvbox-dark", "gruvbox-light",
            "ghostty-dark", "one-dark", "one-light",
        ] {
            XCTAssertNotNil(KookyTerminalTheme.preset(for: id), "missing preset \(id)")
        }
    }

    func testGhosttyDarkMatchesPinnedLibghosttyDefaults() {
        let theme = KookyTerminalTheme.preset(for: "ghostty-dark")
        XCTAssertEqual(theme?.title, "Ghostty Dark")
        XCTAssertEqual(theme?.backgroundHex, "#282C34")
        XCTAssertEqual(theme?.foregroundHex, "#FFFFFF")
        XCTAssertEqual(theme?.lines.first, "background = #282C34")
        XCTAssertEqual(theme?.lines.filter { $0.hasPrefix("palette = ") }.count, 16)
        XCTAssertTrue(theme?.lines.contains("palette = 0=#1D1F21") == true)
        XCTAssertTrue(theme?.lines.contains("palette = 15=#EAEAEA") == true)
    }

    func testIsDarkClassifiesPresetsForPickerGrouping() {
        XCTAssertEqual(KookyTerminalTheme.preset(for: "tokyo-night")?.isDark, true)
        XCTAssertEqual(KookyTerminalTheme.preset(for: "gruvbox-dark")?.isDark, true)
        XCTAssertEqual(KookyTerminalTheme.preset(for: "ghostty-dark")?.isDark, true)
        XCTAssertEqual(KookyTerminalTheme.preset(for: "one-dark")?.isDark, true)
        XCTAssertEqual(KookyTerminalTheme.preset(for: "tokyo-day")?.isDark, false)
        XCTAssertEqual(KookyTerminalTheme.preset(for: "gruvbox-light")?.isDark, false)
        XCTAssertEqual(KookyTerminalTheme.preset(for: "one-light")?.isDark, false)
    }

    func testSettingsThemeSelectionPreservesUnknownRawTheme() {
        let state = KookySettingsModel.themeSelection(for: "/Users/me/.config/ghostty/themes/custom")
        XCTAssertEqual(state.selection, KookySettingsModel.customThemeSelection)
        XCTAssertEqual(
            KookySettingsModel.persistedThemeValue(
                selection: state.selection,
                customRawValue: state.customRawValue
            ),
            "/Users/me/.config/ghostty/themes/custom"
        )
    }

    func testSettingsDefaultThemeSelectionClearsRawThemeWhenChosen() {
        let defaultSelection = KookySettingsModel.themeSelection(for: nil).selection
        XCTAssertNil(
            KookySettingsModel.persistedThemeValue(
                selection: defaultSelection,
                customRawValue: "/Users/me/.config/ghostty/themes/custom"
            )
        )
    }

    func testSettingsPresetThemeSelectionPersistsStableId() {
        let state = KookySettingsModel.themeSelection(for: "Solarized Light")
        XCTAssertEqual(state.selection, "solarized-light")
        XCTAssertEqual(
            KookySettingsModel.persistedThemeValue(
                selection: state.selection,
                customRawValue: nil
            ),
            "solarized-light"
        )
    }

    func testFreshAppearanceDefaultsToSystemWithIndependentThemePair() {
        let preferences = KookySettingsModel.themePreferences(
            appearance: [:],
            legacyRawTheme: nil
        )

        XCTAssertEqual(preferences.mode, .system)
        XCTAssertEqual(preferences.lightSelection, KookyTerminalTheme.defaultLightID)
        XCTAssertEqual(preferences.darkSelection, KookyTerminalTheme.defaultDarkID)
    }

    func testDefaultTemplateOptsNewInstallsIntoPairedThemes() throws {
        let data = try XCTUnwrap(KookySettings.defaultTemplate.data(using: .utf8))
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any]
        )
        let appearance = try XCTUnwrap(parsed["appearance"] as? [String: Any])

        XCTAssertEqual(
            appearance["themeSchemaVersion"] as? Int,
            KookySettings.pairedThemeSchemaVersion
        )
        XCTAssertEqual(
            KookySettings.effectiveThemeValue(parsed: parsed, systemIsDark: false),
            KookyTerminalTheme.defaultLightID
        )
        XCTAssertEqual(
            KookySettings.effectiveThemeValue(parsed: parsed, systemIsDark: true),
            KookyTerminalTheme.defaultDarkID
        )
    }

    func testLegacyDefaultKeepsGhosttyInheritance() {
        let parsed: [String: Any] = [
            "appearance": ["showSearchPill": false],
            "terminal": ["font-size": 14],
        ]

        XCTAssertNil(KookySettings.effectiveThemeValue(parsed: parsed, systemIsDark: false))
        XCTAssertNil(KookySettings.effectiveThemeValue(parsed: parsed, systemIsDark: true))
        XCTAssertFalse(
            KookySettingsModel.shouldEnablePairedThemeSchema(
                appearance: ["showSearchPill": false],
                legacyRawTheme: nil
            )
        )
    }

    func testExplicitLegacyThemeOptsIntoLosslessMigration() {
        XCTAssertTrue(
            KookySettingsModel.shouldEnablePairedThemeSchema(
                appearance: [:],
                legacyRawTheme: "dracula"
            )
        )
    }

    func testLegacyThemeMigratesToMatchingSideAndPreservesAppearance() {
        let light = KookySettingsModel.themePreferences(
            appearance: [:],
            legacyRawTheme: "Solarized Light"
        )
        XCTAssertEqual(light.mode, .light)
        XCTAssertEqual(light.lightSelection, "solarized-light")
        XCTAssertEqual(light.darkSelection, KookyTerminalTheme.defaultDarkID)

        let dark = KookySettingsModel.themePreferences(
            appearance: [:],
            legacyRawTheme: "dracula"
        )
        XCTAssertEqual(dark.mode, .dark)
        XCTAssertEqual(dark.lightSelection, KookyTerminalTheme.defaultLightID)
        XCTAssertEqual(dark.darkSelection, "dracula")
    }

    func testPairedThemesAndModeTakePrecedenceOverLegacyTheme() {
        let preferences = KookySettingsModel.themePreferences(
            appearance: [
                "mode": "system",
                "lightTheme": "solarized-light",
                "darkTheme": "dracula",
            ],
            legacyRawTheme: "rose-pine"
        )

        XCTAssertEqual(preferences.mode, .system)
        XCTAssertEqual(preferences.lightSelection, "solarized-light")
        XCTAssertEqual(preferences.darkSelection, "dracula")
    }

    func testEffectiveThemeFollowsModeAndSystemAppearance() {
        let parsed: [String: Any] = [
            "appearance": [
                "mode": "system",
                "lightTheme": "solarized-light",
                "darkTheme": "dracula",
            ],
            "terminal": [:],
        ]
        XCTAssertEqual(
            KookySettings.effectiveThemeValue(parsed: parsed, systemIsDark: false),
            "solarized-light"
        )
        XCTAssertEqual(
            KookySettings.effectiveThemeValue(parsed: parsed, systemIsDark: true),
            "dracula"
        )

        let forcedLight: [String: Any] = [
            "appearance": ["mode": "light", "darkTheme": "dracula"],
            "terminal": [:],
        ]
        XCTAssertEqual(
            KookySettings.effectiveThemeValue(parsed: forcedLight, systemIsDark: true),
            KookyTerminalTheme.defaultLightID
        )
    }

    func testEffectiveThemeStillAcceptsLegacyTerminalTheme() {
        let parsed: [String: Any] = ["terminal": ["theme": "rose-pine"]]
        XCTAssertEqual(
            KookySettings.effectiveThemeValue(parsed: parsed, systemIsDark: false),
            "rose-pine"
        )
    }

    func testSystemAppearanceResolutionUsesAppKitAppearance() throws {
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let highContrastDark = try XCTUnwrap(NSAppearance(named: .accessibilityHighContrastDarkAqua))
        let highContrastLight = try XCTUnwrap(NSAppearance(named: .accessibilityHighContrastAqua))

        XCTAssertTrue(KookyAppearanceMode.resolvesSystemDark(appearance: dark))
        XCTAssertTrue(KookyAppearanceMode.resolvesSystemDark(appearance: highContrastDark))
        XCTAssertFalse(KookyAppearanceMode.resolvesSystemDark(appearance: light))
        XCTAssertFalse(KookyAppearanceMode.resolvesSystemDark(appearance: highContrastLight))
    }

    func testUserThemesLoadsGhosttyThemeDirectoryFiles() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let themeURL = dir.appendingPathComponent("My Custom Theme")
        try """
        # comments are ignored
        background = #101820
        foreground = "F2AA4C"
        palette = 0=#101820
        """.write(to: themeURL, atomically: true, encoding: .utf8)

        let themes = KookyTerminalTheme.userThemes(in: dir)
        XCTAssertEqual(themes.map(\.title), ["My Custom Theme"])
        XCTAssertEqual(themes.first?.storedValue, "My Custom Theme")
        XCTAssertEqual(themes.first?.backgroundHex, "#101820")
        XCTAssertEqual(themes.first?.foregroundHex, "F2AA4C")
        XCTAssertEqual(themes.first?.isDark, true)
    }

    func testUserThemesAreGroupedByBackgroundLuminance() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "background = #F8F8F8\nforeground = #202020\n"
            .write(
                to: dir.appendingPathComponent("Bright Custom"),
                atomically: true,
                encoding: .utf8
            )
        try "foreground = #FFFFFF\n"
            .write(
                to: dir.appendingPathComponent("Missing Background"),
                atomically: true,
                encoding: .utf8
            )

        let themes = KookyTerminalTheme.userThemes(in: dir)
        XCTAssertEqual(themes.first { $0.title == "Bright Custom" }?.isDark, false)
        XCTAssertEqual(themes.first { $0.title == "Missing Background" }?.isDark, true)
    }

    func testSettingsThemeSelectionAcceptsUserThemeByFileName() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Issue 17")
        try "background = #000000\nforeground = #ffffff\n"
            .write(to: url, atomically: true, encoding: .utf8)

        let custom = KookyTerminalTheme.userThemes(in: dir)
        let state = KookySettingsModel.themeSelection(for: "Issue 17", in: KookyTerminalTheme.presets + custom)
        XCTAssertEqual(state.selection, "ghostty-user:Issue 17")
        XCTAssertEqual(
            KookySettingsModel.persistedThemeValue(
                selection: state.selection,
                customRawValue: nil,
                in: KookyTerminalTheme.presets + custom
            ),
            "Issue 17"
        )
    }

    func testGhosttyUserThemesDirectoryHonorsXDGConfigHome() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let xdg = KookyTerminalTheme.ghosttyUserThemesDirectory(
            environment: ["XDG_CONFIG_HOME": "/tmp/xdg"],
            homeDirectory: home
        )
        XCTAssertEqual(xdg.path, "/tmp/xdg/ghostty/themes")

        let fallback = KookyTerminalTheme.ghosttyUserThemesDirectory(
            environment: [:],
            homeDirectory: home
        )
        XCTAssertEqual(fallback.path, "/Users/example/.config/ghostty/themes")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kooky-theme-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
