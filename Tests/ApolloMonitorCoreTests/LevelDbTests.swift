import XCTest
@testable import ApolloMonitorCore

final class LevelDbTests: XCTestCase {
    func testStepsByWholeDecibels() {
        XCTAssertEqual(LevelDb.next(db: -43, .up), -42)
        XCTAssertEqual(LevelDb.next(db: -43, .down), -44)
        XCTAssertEqual(LevelDb.next(db: -1, .up), 0)
    }

    /// A level left on a fraction by the hardware knob or Console must land on the
    /// whole-dB ladder, not carry the fraction along forever.
    func testStepSnapsFractionalLevelsOntoTheLadder() {
        XCTAssertEqual(LevelDb.next(db: -27.25, .up), -27)
        XCTAssertEqual(LevelDb.next(db: -27.25, .down), -28)
        XCTAssertEqual(LevelDb.next(db: -28.7, .up), -28)
        XCTAssertEqual(LevelDb.next(db: -28.7, .down), -29)

        // And once on the ladder it stays there.
        var db = -27.25
        for _ in 1...3 { db = LevelDb.next(db: db, .up) }
        XCTAssertEqual(db, -25)
    }

    func testClampsAtBothEnds() {
        XCTAssertEqual(LevelDb.next(db: 0, .up), 0)
        XCTAssertEqual(LevelDb.next(db: -96, .down), -96)
        XCTAssertEqual(LevelDb.clamp(12), 0)
        XCTAssertEqual(LevelDb.clamp(-500), -96)
    }

    func testNonFiniteInputFallsToSilenceNotUnity() {
        // Defaulting the wrong way here would mean a stray value slamming the
        // monitors to 0 dB.
        XCTAssertEqual(LevelDb.next(db: .nan, .up), -96)
        XCTAssertEqual(LevelDb.clamp(.nan), -96)
        XCTAssertEqual(LevelDb.next(db: .infinity, .up), -96)
    }

    func testWholeRangeIsReachableInSingleSteps() {
        var db = LevelDb.minimum
        var presses = 0
        while db < LevelDb.maximum, presses < 200 {
            db = LevelDb.next(db: db, .up)
            presses += 1
        }
        XCTAssertEqual(db, 0)
        XCTAssertEqual(presses, 96, "96 presses should span -96 dB to 0 dB")
    }

    func testLabelDropsTrailingZeroButKeepsRealFractions() {
        XCTAssertEqual(LevelDb.label(-43), "-43 dB")
        XCTAssertEqual(LevelDb.label(-43.0), "-43 dB")
        XCTAssertEqual(LevelDb.label(0), "0 dB")
        XCTAssertEqual(LevelDb.label(-27.3), "-27.3 dB")
        // -27.25 is exact in binary and %.1f rounds a tie to even, so this is
        // -27.2 rather than -27.3.
        XCTAssertEqual(LevelDb.label(-27.25), "-27.2 dB")
    }
}
