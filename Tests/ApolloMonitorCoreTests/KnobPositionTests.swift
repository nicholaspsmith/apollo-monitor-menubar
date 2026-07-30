import XCTest
@testable import ApolloMonitorCore

final class KnobPositionTests: XCTestCase {
    func testTaperedToPercentRoundsToWholePercent() {
        XCTAssertEqual(KnobPosition.percent(tapered: 0), 0)
        XCTAssertEqual(KnobPosition.percent(tapered: 1), 100)
        XCTAssertEqual(KnobPosition.percent(tapered: 0.5), 50)
        // Values the engine actually reports, on its 1/54 grid.
        XCTAssertEqual(KnobPosition.percent(tapered: 0.259259), 26)
        XCTAssertEqual(KnobPosition.percent(tapered: 0.3148148059844971), 31)
        XCTAssertEqual(KnobPosition.percent(tapered: 0.148148), 15)
    }

    func testPercentToTapered() {
        XCTAssertEqual(KnobPosition.tapered(percent: 0), 0)
        XCTAssertEqual(KnobPosition.tapered(percent: 26), 0.26)
        XCTAssertEqual(KnobPosition.tapered(percent: 100), 1)
    }

    func testClampsRatherThanWraps() {
        XCTAssertEqual(KnobPosition.percent(tapered: -0.5), 0)
        XCTAssertEqual(KnobPosition.percent(tapered: 1.5), 100)
        XCTAssertEqual(KnobPosition.percent(tapered: .nan), 0)
        XCTAssertEqual(KnobPosition.percent(tapered: .infinity), 100)
        XCTAssertEqual(KnobPosition.tapered(percent: 500), 1)
        XCTAssertEqual(KnobPosition.tapered(percent: -20), 0)
        XCTAssertEqual(KnobPosition.clampTapered(.nan), 0)
    }

    /// A write of N% must read back as N% before the engine snaps it, or the slider
    /// would visibly jump away from where it was dropped for reasons of our own
    /// making rather than the hardware's.
    func testWriteReadRoundTripIsExactForEveryPercent() {
        for percent in 0...100 {
            XCTAssertEqual(
                KnobPosition.percent(tapered: KnobPosition.tapered(percent: percent)),
                percent
            )
        }
    }
}

/// The mouse-position → percent mapping used by the menu slider: the one piece of
/// the drag path checkable without a real mouse.
final class SliderGeometryTests: XCTestCase {
    // Matches VolumeSliderView.Layout.
    private let trackMinX = 20.0
    private let trackWidth = 150.0
    private let knobInset = 9.0

    private func percent(atX x: Double) -> Int {
        KnobPosition.percent(
            atX: x, trackMinX: trackMinX, trackWidth: trackWidth, knobInset: knobInset
        )
    }

    /// Both extremes must be reachable: the knob's centre travels from
    /// `trackMinX + knobInset` to `trackMaxX - knobInset`.
    func testTrackEndsReachBothExtremes() {
        XCTAssertEqual(percent(atX: trackMinX + knobInset), 0)
        XCTAssertEqual(percent(atX: trackMinX + trackWidth - knobInset), 100)
    }

    func testTrackCentreIsHalfway() {
        XCTAssertEqual(percent(atX: trackMinX + trackWidth / 2), 50)
    }

    func testPositionsOutsideTheTrackClamp() {
        XCTAssertEqual(percent(atX: 0), 0)
        XCTAssertEqual(percent(atX: -500), 0)
        XCTAssertEqual(percent(atX: 10_000), 100)
    }

    /// Sweeping left to right must be monotonic and never skip a percent — with a
    /// 132 px usable track and 101 stops, adjacent percents are ~1.3 px apart, so
    /// this also confirms the track is wide enough to select every one.
    func testSweepIsMonotonicAndCoversEveryPercent() {
        var seen: [Int] = []
        var previous = -1

        for tenth in 0...(Int(trackWidth) * 10) {
            let current = percent(atX: trackMinX + Double(tenth) / 10)
            XCTAssertGreaterThanOrEqual(current, previous, "went backwards")
            if current != previous { seen.append(current) }
            previous = current
        }

        XCTAssertEqual(seen, Array(0...100))
    }

    func testDegenerateTrackDoesNotDivideByZero() {
        XCTAssertEqual(
            KnobPosition.percent(atX: 5, trackMinX: 0, trackWidth: 0, knobInset: 9), 0
        )
        XCTAssertEqual(
            KnobPosition.percent(atX: 5, trackMinX: 0, trackWidth: 18, knobInset: 9), 0
        )
    }
}
