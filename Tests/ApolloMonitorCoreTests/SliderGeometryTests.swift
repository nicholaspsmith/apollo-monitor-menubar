import XCTest
@testable import ApolloMonitorCore

/// The mouse-position → step-index mapping used by the menu slider. This is the
/// one piece of the drag path that can be checked without a real mouse, so it
/// lives in Core rather than in the view.
final class SliderGeometryTests: XCTestCase {
    // Matches VolumeSliderView.Layout.
    private let trackMinX = 20.0
    private let trackWidth = 150.0
    private let knobInset = 9.0

    private func index(atX x: Double) -> Int {
        VolumeStep.index(
            atX: x, trackMinX: trackMinX, trackWidth: trackWidth, knobInset: knobInset
        )
    }

    /// Both extremes must be reachable: the knob's centre travels from
    /// `trackMinX + knobInset` to `trackMaxX - knobInset`, so those exact points
    /// are 0% and 100%.
    func testTrackEndsReachBothExtremes() {
        XCTAssertEqual(index(atX: trackMinX + knobInset), 0)
        XCTAssertEqual(index(atX: trackMinX + trackWidth - knobInset), 20)
    }

    func testTrackCentreIsHalfway() {
        XCTAssertEqual(index(atX: trackMinX + trackWidth / 2), 10)
    }

    func testPositionsOutsideTheTrackClampRatherThanWrap() {
        XCTAssertEqual(index(atX: 0), 0)
        XCTAssertEqual(index(atX: -500), 0)
        XCTAssertEqual(index(atX: 10_000), 20)
    }

    /// Walking left to right must produce a monotonic ladder that visits every
    /// one of the 21 positions — no skipped or repeated steps.
    func testSweepIsMonotonicAndCoversEveryStep() {
        var seen: [Int] = []
        var previous = -1

        for tenth in 0...((Int(trackWidth)) * 10) {
            let x = trackMinX + Double(tenth) / 10
            let current = index(atX: x)
            XCTAssertGreaterThanOrEqual(current, previous, "went backwards at x=\(x)")
            if current != previous { seen.append(current) }
            previous = current
        }

        XCTAssertEqual(seen, Array(0...20))
    }

    func testDegenerateTrackDoesNotDivideByZero() {
        XCTAssertEqual(
            VolumeStep.index(atX: 5, trackMinX: 0, trackWidth: 0, knobInset: 9), 0
        )
        XCTAssertEqual(
            VolumeStep.index(atX: 5, trackMinX: 0, trackWidth: 18, knobInset: 9), 0
        )
    }
}
