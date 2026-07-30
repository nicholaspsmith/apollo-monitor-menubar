import Foundation

/// How far one volume-key press moves the level while the key is held.
///
/// macOS delivers media-key repeats at its own rate — roughly one every 150 ms —
/// which at a flat 1 dB makes crossing a useful range take several seconds of
/// holding. Rather than fight the system repeat rate, a sustained hold takes bigger
/// steps the longer it runs, so a deliberate hold covers ground quickly while a
/// single deliberate press still moves exactly 1 dB.
public enum StepAcceleration {
    /// Presses closer together than this are treated as one continued hold. Sits
    /// comfortably above the ~150 ms system repeat interval, and well below the gap
    /// between two separate deliberate presses.
    public static let holdWindow: TimeInterval = 0.25

    public static func isContinuedHold(
        previous: Date?,
        now: Date,
        window: TimeInterval = holdWindow
    ) -> Bool {
        guard let previous else { return false }
        let gap = now.timeIntervalSince(previous)
        // A backwards clock must read as a new press, not a continued hold.
        return gap >= 0 && gap <= window
    }

    /// dB per press, given how many repeats this hold has already delivered.
    ///
    /// The first few stay at 1 dB so a quick double-tap is still fine adjustment;
    /// only a sustained hold speeds up.
    public static func step(consecutiveRepeats: Int) -> Double {
        switch consecutiveRepeats {
        case ..<5: return 1
        case ..<12: return 2
        default: return 3
        }
    }
}
