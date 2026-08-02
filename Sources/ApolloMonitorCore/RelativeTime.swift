import Foundation

/// Compact relative-age formatting shared by the menu header and the `--status`
/// CLI: "12s" / "3m" / "1h".
public enum RelativeTime {
    public static func short(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}
