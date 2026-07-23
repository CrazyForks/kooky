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
}
