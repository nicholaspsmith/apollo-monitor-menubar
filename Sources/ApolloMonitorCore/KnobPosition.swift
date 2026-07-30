/// Monitor knob position as a percentage of travel.
///
/// This is the `CRMonitorLevelTapered` value (0.0...1.0) expressed as 0–100%. It is
/// what Console's knob shows and what the menu slider mirrors, and it is only ever
/// *read* as a continuous value — the app never quantises the position it displays,
/// so the slider always sits exactly where the engine says the knob is.
///
/// Writes are rounded to the nearest whole percent. The engine then snaps that to
/// its own 1/54 grid and pushes the result back, so the displayed position ends up
/// being the hardware's actual one rather than what was asked for.
///
/// Nothing accumulates: the slider writes an absolute position from the mouse, and
/// the volume keys step absolute dB (see `LevelDb`). That is why no canonical step
/// index is needed to prevent drift.
public enum KnobPosition {
    public static let minPercent = 0
    public static let maxPercent = 100

    public static func clampPercent(_ percent: Int) -> Int {
        min(maxPercent, max(minPercent, percent))
    }

    public static func clampTapered(_ tapered: Double) -> Double {
        guard !tapered.isNaN else { return 0 }
        return min(1, max(0, tapered))
    }

    /// Reported knob position → whole percent, for display.
    public static func percent(tapered: Double) -> Int {
        guard !tapered.isNaN else { return minPercent }
        let scaled = (tapered * 100).rounded()
        if scaled <= Double(minPercent) { return minPercent }
        if scaled >= Double(maxPercent) { return maxPercent }
        return Int(scaled)
    }

    /// Whole percent → the value written to the engine.
    public static func tapered(percent: Int) -> Double {
        Double(clampPercent(percent)) / 100
    }

    /// Percent for a horizontal position along a slider track, rounded to 1%.
    ///
    /// `x` and `trackMinX` are in the same coordinate space. The usable span is
    /// inset by half a knob width at each end, because the knob's *centre* is what
    /// reaches the extremes — without the inset the last half-knob of travel would
    /// be unreachable and 100% could never be selected by mouse.
    public static func percent(
        atX x: Double,
        trackMinX: Double,
        trackWidth: Double,
        knobInset: Double
    ) -> Int {
        let usable = trackWidth - knobInset * 2
        guard usable > 0 else { return minPercent }
        return percent(tapered: (x - trackMinX - knobInset) / usable)
    }
}
