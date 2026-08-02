import Foundation

/// One parsed line of `ua-watchdog.log`. The watchdog writes lines shaped like:
///
///     2026-07-30 16:16:07  KILLED orphaned UA Mixer Helper pid=32329 cpu=100.0% (fast-path: PPID=1)
///     2026-07-30 16:16:07  KILLED runaway UA Mixer Sentinel pid=32331 cpu=100.0% (>=90% x 2 ticks)
///     2026-07-30 16:16:07  WARN UA Mixer Sentinel pid=32331 cpu=100.0% (tick 1/2 >=90%)
///     2026-07-30 16:16:07  kickstarted UA mixer engine to restore audio path
///
/// A timestamp (`yyyy-MM-dd HH:mm:ss`), two spaces, then a message.
public struct LogEvent: Equatable {
    public enum Kind: Equatable { case killed, warn, other }

    public let date: Date
    public let kind: Kind
    /// The process label for KILLED/WARN lines (e.g. "UA Mixer Helper"); empty otherwise.
    public let label: String

    public init(date: Date, kind: Kind, label: String) {
        self.date = date
        self.kind = kind
        self.label = label
    }
}

public enum LogParser {
    /// The watchdog stamps local time via `date '+%Y-%m-%d %H:%M:%S'`, so parse in
    /// the current time zone. POSIX locale keeps parsing independent of region.
    public static let dateFormat = "yyyy-MM-dd HH:mm:ss"

    private static func makeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = dateFormat
        return f
    }

    /// Parse a single log line into an event, or nil if it isn't a timestamped line.
    public static func parseLine(_ line: String, formatter: DateFormatter? = nil) -> LogEvent? {
        let f = formatter ?? makeFormatter()
        // "yyyy-MM-dd HH:mm:ss" is 19 chars, followed by the two-space separator.
        guard line.count > 21 else { return nil }
        let stampStr = String(line.prefix(19))
        guard let date = f.date(from: stampStr) else { return nil }

        let message = line.dropFirst(19).trimmingCharacters(in: .whitespaces)

        if message.hasPrefix("KILLED") {
            return LogEvent(date: date, kind: .killed, label: extractLabel(fromKilled: message))
        }
        if message.hasPrefix("WARN") {
            return LogEvent(date: date, kind: .warn, label: extractLabel(afterFirstWord: message))
        }
        return LogEvent(date: date, kind: .other, label: "")
    }

    /// All timestamped events in the log text, in file (chronological) order.
    public static func events(_ text: String) -> [LogEvent] {
        let f = makeFormatter()
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
            parseLine(String($0), formatter: f)
        }
    }

    /// The most recent KILLED event by timestamp, or nil if the watchdog has never
    /// killed anything. Chooses by date rather than file position so an out-of-order
    /// line (e.g. across a DST fall-back) can't surface a stale kill as the latest.
    public static func lastKill(_ text: String) -> LogEvent? {
        events(text).filter { $0.kind == .killed }.max { $0.date < $1.date }
    }

    /// Count of KILLED events whose timestamp falls on the same calendar day as `now`.
    public static func killsToday(_ text: String, now: Date, calendar: Calendar = .current) -> Int {
        events(text).filter { $0.kind == .killed && calendar.isDate($0.date, inSameDayAs: now) }.count
    }

    // MARK: - Label extraction

    /// "KILLED orphaned UA Mixer Helper pid=…" / "KILLED runaway X pid=…" → the label.
    /// Drops the "KILLED" verb, an optional "orphaned"/"runaway" qualifier, and stops
    /// at " pid=".
    private static func extractLabel(fromKilled message: String) -> String {
        var rest = message.dropFirst("KILLED".count).trimmingCharacters(in: .whitespaces)
        for qualifier in ["orphaned ", "runaway "] where rest.hasPrefix(qualifier) {
            rest = String(rest.dropFirst(qualifier.count))
            break
        }
        return String(rest.prefix(upTo: rest.range(of: " pid=")?.lowerBound ?? rest.endIndex))
    }

    /// "WARN UA Mixer Sentinel pid=…" → "UA Mixer Sentinel". Drops the first word,
    /// stops at " pid=".
    private static func extractLabel(afterFirstWord message: String) -> String {
        guard let space = message.firstIndex(of: " ") else { return "" }
        let rest = message[message.index(after: space)...]
        return String(rest.prefix(upTo: rest.range(of: " pid=")?.lowerBound ?? rest.endIndex))
    }
}
