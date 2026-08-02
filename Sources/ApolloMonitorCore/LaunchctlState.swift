import Foundation

/// Parsers for the text output of `launchctl`. The app runs the commands (via
/// StatusItemKit's `Shell`); these turn the output into values, kept pure so the
/// fiddly string-matching is unit-testable against real fixtures.
public enum LaunchctlParser {
    /// `last exit code = N` from `launchctl print gui/<uid>/<label>`, or nil if the
    /// line is absent (job has never completed a run).
    public static func lastExitCode(fromPrint text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("last exit code = ") else { continue }
            return Int(t.dropFirst("last exit code = ".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Whether the label is disabled, from `launchctl print-disabled gui/<uid>`.
    /// Entries look like `"com.foo.bar" => enabled` (or `disabled`); older macOS
    /// prints `=> true`/`=> false`. Absent ⇒ not disabled (the default).
    public static func isDisabled(label: String, fromPrintDisabled text: String) -> Bool {
        let needle = "\"\(label)\""
        for line in text.split(separator: "\n") where line.contains(needle) {
            let value = line.split(separator: ">").last.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? ""
            return value == "disabled" || value == "true"
        }
        return false
    }
}
