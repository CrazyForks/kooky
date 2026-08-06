import AppKit
import XCTest
@testable import KookyKit

@MainActor
final class KookyWindowLayoutTests: XCTestCase {
    func testTerminalMinimumUsesCompactPaneWidth() {
        XCTAssertEqual(KookyWindowLayout.minimumTerminalWidth, 200)
    }

    func testHiddenSidebarsKeepTopChromeMinimum() {
        XCTAssertEqual(
            KookyWindowLayout.minimumWindowWidth(
                leftMode: .hidden,
                expandedLeftWidth: SidebarView.maxWidth,
                rightMode: .hidden
            ),
            KookyWindowLayout.minimumChromeWidth
        )
    }

    func testFullSidebarsReserveTerminalAndBothSeparators() {
        XCTAssertEqual(
            KookyWindowLayout.minimumWindowWidth(
                leftMode: .full,
                expandedLeftWidth: SidebarView.fullWidth,
                rightMode: .full
            ),
            SidebarView.fullWidth
                + KookyWindowLayout.minimumTerminalWidth
                + AgentOverviewSidebar.fullWidth
                + 2 * KookyWindowLayout.separatorWidth
        )
    }

    func testResizableLeftSidebarRaisesWindowMinimum() {
        XCTAssertEqual(
            KookyWindowLayout.minimumWindowWidth(
                leftMode: .full,
                expandedLeftWidth: SidebarView.maxWidth,
                rightMode: .full
            ),
            SidebarView.maxWidth
                + KookyWindowLayout.minimumTerminalWidth
                + AgentOverviewSidebar.fullWidth
                + 2 * KookyWindowLayout.separatorWidth
        )
    }

    func testCompactSidebarsUseTheirRenderedWidths() {
        XCTAssertEqual(
            KookyWindowLayout.minimumWindowWidth(
                leftMode: .compact,
                expandedLeftWidth: SidebarView.maxWidth,
                rightMode: .compact
            ),
            max(
                KookyWindowLayout.minimumChromeWidth,
                SidebarView.compactWidth
                    + KookyWindowLayout.minimumTerminalWidth
                    + AgentOverviewSidebar.compactWidth
                    + 2 * KookyWindowLayout.separatorWidth
            )
        )
    }

    func testWindowMinimumStopsAtVisibleScreenWidth() {
        XCTAssertEqual(
            KookyWindowLayout.screenBoundMinimumWindowWidth(
                desiredWidth: 1_600,
                visibleScreenWidth: 1_200
            ),
            1_200
        )
        XCTAssertEqual(
            KookyWindowLayout.screenBoundMinimumWindowWidth(
                desiredWidth: 900,
                visibleScreenWidth: 1_200
            ),
            900
        )
        XCTAssertEqual(
            KookyWindowLayout.screenBoundMinimumWindowWidth(
                desiredWidth: 900,
                visibleScreenWidth: nil
            ),
            900
        )
    }

    func testHorizontalDividerKeepsBothLeafPanesAtMinimumWidth() {
        let first = PaneNode(pane: Pane())
        let second = PaneNode(pane: Pane())

        XCTAssertEqual(
            KookyWindowLayout.clampedSplitFraction(
                0.05,
                orientation: .horizontal,
                first: first,
                second: second,
                usableLength: 1_000
            ),
            0.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            KookyWindowLayout.clampedSplitFraction(
                0.95,
                orientation: .horizontal,
                first: first,
                second: second,
                usableLength: 1_000
            ),
            0.8,
            accuracy: 0.0001
        )
    }

    func testHorizontalDividerReservesWidthForNestedSubtree() {
        let first = PaneNode(content: .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.5
        ))
        let second = PaneNode(pane: Pane())

        XCTAssertEqual(
            KookyWindowLayout.clampedSplitFraction(
                0.1,
                orientation: .horizontal,
                first: first,
                second: second,
                usableLength: 800
            ),
            401.0 / 800.0,
            accuracy: 0.0001
        )
    }

    func testHorizontalDividerLocksProportionallyWhenScreenCannotFitAllMinima() {
        let first = PaneNode(content: .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.5
        ))
        let second = PaneNode(pane: Pane())

        let expected = 401.0 / 601.0
        XCTAssertEqual(
            KookyWindowLayout.clampedSplitFraction(
                0.1,
                orientation: .horizontal,
                first: first,
                second: second,
                usableLength: 500
            ),
            expected,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            KookyWindowLayout.clampedSplitFraction(
                0.9,
                orientation: .horizontal,
                first: first,
                second: second,
                usableLength: 500
            ),
            expected,
            accuracy: 0.0001
        )
    }

    func testVerticalDividerKeepsExistingTenPercentHeightBound() {
        XCTAssertEqual(
            KookyWindowLayout.clampedSplitFraction(
                0.01,
                orientation: .vertical,
                first: PaneNode(pane: Pane()),
                second: PaneNode(pane: Pane()),
                usableLength: 1_000
            ),
            0.1,
            accuracy: 0.0001
        )
    }

    func testControllerExpandsForPaneTreePresentAtInitialization() throws {
        let store = WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
        store.sidebarWidth = SidebarView.maxWidth
        store.setRightSidebarMode(.full)
        let workspace = try XCTUnwrap(store.active)
        var pane = try XCTUnwrap(workspace.activePane)
        for _ in 0..<7 {
            pane = try XCTUnwrap(store.splitPane(pane, orientation: .horizontal, in: workspace))
        }

        let desired = KookyWindowLayout.minimumWindowWidth(
            leftMode: store.sidebarMode,
            expandedLeftWidth: store.sidebarWidth,
            rightMode: store.rightSidebarMode,
            terminalWidth: KookyWindowLayout.minimumTerminalTreeWidth(for: workspace.root)
        )
        let expected = KookyWindowLayout.screenBoundMinimumWindowWidth(
            desiredWidth: desired,
            visibleScreenWidth: NSScreen.main?.visibleFrame.width
        )
        guard expected > 1_100 else {
            throw XCTSkip("the test display is not wider than the default window")
        }

        let controller = KookyWindowController(windowId: UUID(), store: store)
        defer {
            controller.close()
            store.terminate()
        }
        XCTAssertEqual(try XCTUnwrap(controller.window).frame.width, expected, accuracy: 1)
    }

    func testHorizontalSplitAddsBothPaneWidthsAndDivider() {
        let root = PaneNode(content: .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.5
        ))

        XCTAssertEqual(
            KookyWindowLayout.minimumTerminalTreeWidth(for: root),
            2 * KookyWindowLayout.minimumTerminalWidth + KookyWindowLayout.separatorWidth
        )
    }

    func testVerticalSplitReusesTheSameHorizontalSpan() {
        let root = PaneNode(content: .split(
            orientation: .vertical,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.5
        ))

        XCTAssertEqual(
            KookyWindowLayout.minimumTerminalTreeWidth(for: root),
            KookyWindowLayout.minimumTerminalWidth
        )
    }

    func testNestedHorizontalSplitCountsEveryVisibleColumn() {
        let right = PaneNode(content: .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.5
        ))
        let root = PaneNode(content: .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: right,
            fraction: 0.5
        ))

        XCTAssertEqual(
            KookyWindowLayout.minimumTerminalTreeWidth(for: root),
            3 * KookyWindowLayout.minimumTerminalWidth + 2 * KookyWindowLayout.separatorWidth
        )
    }

    func testRepeatedRightSplitRebalancesAncestorColumns() throws {
        let left = PaneNode(pane: Pane())
        let target = PaneNode(pane: Pane())
        let root = PaneNode(content: .split(
            orientation: .horizontal,
            first: left,
            second: target,
            fraction: 0.5
        ))
        target.content = .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.5
        )

        XCTAssertTrue(KookyWindowLayout.rebalanceHorizontalSplits(in: root, alongPathTo: target))
        guard case .split(.horizontal, _, _, let rootFraction) = root.content else {
            return XCTFail("root should remain horizontal")
        }
        XCTAssertEqual(rootFraction, 1.0 / 3.0, accuracy: 0.001,
                       "one left column and two right columns should allocate 1/3 : 2/3")
        guard case .split(.horizontal, _, _, let childFraction) = target.content else {
            return XCTFail("target should become a horizontal split")
        }
        XCTAssertEqual(childFraction, 0.5, accuracy: 0.001)
    }

    func testRebalanceDoesNotChangeUnrelatedHorizontalBranch() throws {
        let unrelated = PaneNode(content: .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.7
        ))
        let target = PaneNode(content: .split(
            orientation: .horizontal,
            first: PaneNode(pane: Pane()),
            second: PaneNode(pane: Pane()),
            fraction: 0.5
        ))
        let root = PaneNode(content: .split(
            orientation: .vertical,
            first: unrelated,
            second: target,
            fraction: 0.6
        ))

        XCTAssertTrue(KookyWindowLayout.rebalanceHorizontalSplits(in: root, alongPathTo: target))
        guard case .split(.horizontal, _, _, let unrelatedFraction) = unrelated.content else {
            return XCTFail("unrelated branch should remain horizontal")
        }
        XCTAssertEqual(unrelatedFraction, 0.7, accuracy: 0.001)
        guard case .split(.vertical, _, _, let verticalFraction) = root.content else {
            return XCTFail("root should remain vertical")
        }
        XCTAssertEqual(verticalFraction, 0.6, accuracy: 0.001)
    }
}
