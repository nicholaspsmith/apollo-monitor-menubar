import XCTest
@testable import ApolloMonitorCore

final class VolumeStepTests: XCTestCase {
    /// Model of UA Mixer Engine's internal quantization. Measured on an Apollo
    /// Twin MkII: every value written to CRMonitorLevelTapered reads back as the
    /// nearest multiple of 1/54.
    private func snap(_ tapered: Double, grid: Double = 54) -> Double {
        (tapered * grid).rounded() / grid
    }

    /// The invariant the whole design rests on: writing `index / 20`, letting the
    /// engine snap it, and reading it back recovers the same index. Without this
    /// the app would drift a step at a time and the 20 increments would not be
    /// even.
    func testIndexSurvivesEngineQuantization() {
        for index in VolumeStep.minIndex...VolumeStep.maxIndex {
            let written = VolumeStep.tapered(index: index)
            let readBack = snap(written)
            XCTAssertEqual(
                VolumeStep.index(tapered: readBack), index,
                "index \(index) wrote \(written), engine snapped to \(readBack)"
            )
        }
    }

    /// The property must not depend on 54 being the exact divisor — any grid
    /// finer than 1/40 keeps the snap error below half a step.
    func testIndexSurvivesOtherPlausibleGrids() {
        for grid in [41.0, 48.0, 54.0, 64.0, 100.0, 128.0, 256.0] {
            for index in VolumeStep.minIndex...VolumeStep.maxIndex {
                let readBack = snap(VolumeStep.tapered(index: index), grid: grid)
                XCTAssertEqual(
                    VolumeStep.index(tapered: readBack), index,
                    "grid 1/\(grid) broke index \(index)"
                )
            }
        }
    }

    func testTaperedSpansSilenceToUnity() {
        XCTAssertEqual(VolumeStep.tapered(index: 0), 0.0)
        XCTAssertEqual(VolumeStep.tapered(index: 20), 1.0)
        XCTAssertEqual(VolumeStep.tapered(index: 10), 0.5)
    }

    func testPercentIsTwentyEvenIncrements() {
        XCTAssertEqual(VolumeStep.percent(index: 0), 0)
        XCTAssertEqual(VolumeStep.percent(index: 1), 5)
        XCTAssertEqual(VolumeStep.percent(index: 20), 100)

        // Every step is exactly 5% — no rounding wobble anywhere on the ladder.
        for index in 1...VolumeStep.maxIndex {
            let delta = VolumeStep.percent(index: index) - VolumeStep.percent(index: index - 1)
            XCTAssertEqual(delta, 5, "step \(index) was not 5%")
        }
    }

    func testNextClampsAtBothEnds() {
        XCTAssertEqual(VolumeStep.next(index: 0, .down), 0)
        XCTAssertEqual(VolumeStep.next(index: 20, .up), 20)
        XCTAssertEqual(VolumeStep.next(index: 6, .up), 7)
        XCTAssertEqual(VolumeStep.next(index: 6, .down), 5)
    }

    func testTwentyPressesCrossTheWholeRange() {
        var index = VolumeStep.minIndex
        for _ in 1...VolumeStep.stepCount { index = VolumeStep.next(index: index, .up) }
        XCTAssertEqual(index, VolumeStep.maxIndex)
        XCTAssertEqual(VolumeStep.percent(index: index), 100)

        for _ in 1...VolumeStep.stepCount { index = VolumeStep.next(index: index, .down) }
        XCTAssertEqual(index, VolumeStep.minIndex)
    }

    func testIndexClampsOutOfRangeInput() {
        XCTAssertEqual(VolumeStep.index(tapered: -0.5), 0)
        XCTAssertEqual(VolumeStep.index(tapered: 1.5), 20)
        XCTAssertEqual(VolumeStep.index(tapered: .nan), 0)
        XCTAssertEqual(VolumeStep.index(tapered: .infinity), 20)
    }

    /// The level the rig was actually sitting at while this was built: 17/54,
    /// −22.0 dB, which is step 6 (30%).
    func testMeasuredLiveValueMapsToStepSix() {
        XCTAssertEqual(VolumeStep.index(tapered: 0.3148148059844971), 6)
        XCTAssertEqual(VolumeStep.percent(index: 6), 30)
    }
}
