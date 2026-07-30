/// Direction of a monitor-level adjustment.
public enum StepDirection: Sendable {
    case up, down
}

/// The 21-position ladder (0...20) the whole app counts in.
///
/// UA Mixer Engine snaps `CRMonitorLevelTapered` to a coarse internal grid —
/// 1/54 on an Apollo Twin MkII — so a requested 0.05 reads back as 0.055556
/// (3/54). Accumulating from the read-back value (`set(read() + 0.05)`) would
/// therefore compound the snap error on every keypress and the 20 increments
/// would not stay even.
///
/// So the step *index* is canonical: the app always writes `index / 20` and
/// never adds to a value it read. Coming the other way, `index(tapered:)`
/// recovers the index from whatever the engine reports — including the snapped
/// echo of our own writes, which is why our writes need no special-casing.
/// `round(snap(i / 20) * 20) == i` holds for every i in 0...20 for any grid
/// finer than 1/40, so this does not depend on the divisor being exactly 54.
public enum VolumeStep {
    /// Number of increments between silence and unity.
    public static let stepCount = 20

    /// Lowest and highest valid indices.
    public static let minIndex = 0
    public static let maxIndex = stepCount

    /// Knob position (`CRMonitorLevelTapered`, 0.0...1.0) for a step index.
    /// 0 is −96 dB (silence), `stepCount` is 0 dB (unity).
    public static func tapered(index: Int) -> Double {
        Double(clamp(index)) / Double(stepCount)
    }

    /// User-facing percentage for a step index: 0, 5, 10, … 100.
    public static func percent(index: Int) -> Int {
        clamp(index) * (100 / stepCount)
    }

    /// Nearest step index to a knob position reported by the engine.
    public static func index(tapered: Double) -> Int {
        // Bounds are checked in Double space before converting: `Int(.infinity)`
        // traps, so clamping after the conversion would be too late.
        guard !tapered.isNaN else { return minIndex }
        let scaled = (tapered * Double(stepCount)).rounded()
        if scaled <= Double(minIndex) { return minIndex }
        if scaled >= Double(maxIndex) { return maxIndex }
        return Int(scaled)
    }

    /// One step in `direction`, clamped at the ends.
    public static func next(index: Int, _ direction: StepDirection) -> Int {
        clamp(index + (direction == .up ? 1 : -1))
    }

    /// Step index for a horizontal position along a slider track.
    ///
    /// `x` and `trackMinX` are in the same coordinate space. The usable span is
    /// inset by half a knob width at each end, because the knob's *centre* is
    /// what reaches the extremes — without the inset the track's last half-knob
    /// of travel would be unreachable and 100% could never be selected by mouse.
    public static func index(
        atX x: Double,
        trackMinX: Double,
        trackWidth: Double,
        knobInset: Double
    ) -> Int {
        let usable = trackWidth - knobInset * 2
        guard usable > 0 else { return minIndex }
        return index(tapered: (x - trackMinX - knobInset) / usable)
    }

    public static func clamp(_ index: Int) -> Int {
        min(maxIndex, max(minIndex, index))
    }
}
