import XCTest
@testable import ApolloMonitorCore

final class StepAccelerationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testFirstPressIsNeverAHold() {
        XCTAssertFalse(StepAcceleration.isContinuedHold(previous: nil, now: now))
    }

    /// The system repeat interval is ~150 ms, so that must read as a hold.
    func testSystemRepeatIntervalCountsAsHold() {
        XCTAssertTrue(StepAcceleration.isContinuedHold(
            previous: now.addingTimeInterval(-0.15), now: now
        ))
    }

    func testDeliberateSeparatePressesAreNotAHold() {
        XCTAssertFalse(StepAcceleration.isContinuedHold(
            previous: now.addingTimeInterval(-0.6), now: now
        ))
        XCTAssertFalse(StepAcceleration.isContinuedHold(
            previous: now.addingTimeInterval(-30), now: now
        ))
    }

    func testClockGoingBackwardsIsNotAHold() {
        XCTAssertFalse(StepAcceleration.isContinuedHold(
            previous: now.addingTimeInterval(10), now: now
        ))
    }

    /// A single press, and a quick double-tap, must stay fine adjustment.
    func testShortHoldsStayAtOneDecibel() {
        for repeats in 0..<5 {
            XCTAssertEqual(StepAcceleration.step(consecutiveRepeats: repeats), 1)
        }
    }

    func testSustainedHoldAccelerates() {
        XCTAssertEqual(StepAcceleration.step(consecutiveRepeats: 5), 2)
        XCTAssertEqual(StepAcceleration.step(consecutiveRepeats: 11), 2)
        XCTAssertEqual(StepAcceleration.step(consecutiveRepeats: 12), 3)
        XCTAssertEqual(StepAcceleration.step(consecutiveRepeats: 100), 3)
    }

    /// Holding must cross the usable range in about a second rather than several.
    func testHoldCoversTheRangeQuickly() {
        var db = -60.0
        var repeats = 0
        while db < 0, repeats < 500 {
            db = LevelDb.next(
                db: db, .up, step: StepAcceleration.step(consecutiveRepeats: repeats)
            )
            repeats += 1
        }
        XCTAssertEqual(db, 0)
        // At the ~150 ms system repeat rate this is well under 2 seconds of holding,
        // versus 60 presses (9 s) at a flat 1 dB.
        XCTAssertLessThanOrEqual(repeats, 26, "hold took \(repeats) repeats")
    }
}
