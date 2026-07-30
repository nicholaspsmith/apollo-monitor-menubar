/// Monitor level in dB — the app's fine-grained unit.
///
/// `CRMonitorLevel` accepts and stores arbitrary values (−29.5, −27.25 and so on
/// all round-trip exactly), while `CRMonitorLevelTapered` snaps to a 1/54 grid and
/// holds the same value across a ~2 dB span. The tapered property is a coarse
/// *report* of the knob's position; dB is the real control. So stepping happens
/// here, and the tapered value is only ever read — for the slider's position.
///
/// One grid step is roughly 2 dB around normal listening levels, which makes a
/// 1 dB step about 0.9% of knob travel: finer than a whole percentage point of the
/// 0–100% scale, which cannot be expressed at all in only 55 hardware positions.
public enum LevelDb {
    /// Range reported by the engine for `CRMonitorLevel`.
    public static let minimum = -96.0
    public static let maximum = 0.0

    /// One press.
    public static let defaultStep = 1.0

    public static func clamp(_ db: Double) -> Double {
        guard !db.isNaN else { return minimum }
        return Swift.min(maximum, Swift.max(minimum, db))
    }

    /// One step in `direction`, snapped onto the whole-dB ladder.
    ///
    /// Flooring before stepping up (and ceiling before stepping down) means a level
    /// left on a fraction by the hardware knob or Console — −27.25, say — lands on
    /// −27 rather than −26.25. After the first press every value is a whole number.
    public static func next(
        db: Double,
        _ direction: StepDirection,
        step: Double = defaultStep
    ) -> Double {
        guard db.isFinite else { return minimum }
        switch direction {
        case .up: return clamp(db.rounded(.down) + step)
        case .down: return clamp(db.rounded(.up) - step)
        }
    }

    /// `-43 dB`, or `-27.3 dB` when the level is not a whole number.
    public static func label(_ db: Double) -> String {
        guard db.isFinite else { return "—" }
        if abs(db - db.rounded()) < 0.05 {
            return "\(Int(db.rounded())) dB"
        }
        return String(format: "%.1f dB", db)
    }
}
