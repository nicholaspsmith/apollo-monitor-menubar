import XCTest
@testable import ApolloMonitorCore

final class OverlayRefreshTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A run of key presses must never rebuild — that is the hot path.
    func testRapidRepeatedShowsKeepTheSamePanel() {
        for gap in [0.0, 0.15, 1.0, 30.0, 299.0] {
            XCTAssertFalse(
                OverlayRefresh.needsFreshPanel(
                    lastShownAt: start, now: start.addingTimeInterval(gap)
                ),
                "rebuilt after only \(gap)s"
            )
        }
    }

    /// The failure showed up after the overlay had gone unused overnight, so a long
    /// gap is exactly when a fresh window is wanted.
    func testLongGapRebuilds() {
        for gap in [300.0, 3600.0, 16 * 3600.0] {
            XCTAssertTrue(
                OverlayRefresh.needsFreshPanel(
                    lastShownAt: start, now: start.addingTimeInterval(gap)
                ),
                "did not rebuild after \(gap)s idle"
            )
        }
    }

    func testThresholdBoundaryIsInclusive() {
        XCTAssertFalse(OverlayRefresh.needsFreshPanel(
            lastShownAt: start, now: start.addingTimeInterval(OverlayRefresh.idleThreshold - 0.001)
        ))
        XCTAssertTrue(OverlayRefresh.needsFreshPanel(
            lastShownAt: start, now: start.addingTimeInterval(OverlayRefresh.idleThreshold)
        ))
    }

    /// A clock that jumps backwards (time sync, or waking in a different zone) must
    /// not be read as a huge idle gap in the other direction.
    func testClockGoingBackwardsDoesNotRebuild() {
        XCTAssertFalse(OverlayRefresh.needsFreshPanel(
            lastShownAt: start, now: start.addingTimeInterval(-10_000)
        ))
    }
}
