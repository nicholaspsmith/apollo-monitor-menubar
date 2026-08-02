import Foundation

/// Locations and identifiers of the `ua-watchdog` LaunchAgent this app inspects
/// and toggles. Kept as pure strings/joins so the logic stays testable; the app
/// supplies `home` (`NSHomeDirectory()`).
public enum WatchdogPaths {
    /// launchd label of the watchdog agent (see the plist's `Label`).
    public static let label = "com.nicholassmith.ua-watchdog"

    public static func plist(home: String) -> String {
        "\(home)/Library/LaunchAgents/\(label).plist"
    }

    /// Action log — the watchdog appends here only on WARN/KILL.
    public static func log(home: String) -> String {
        "\(home)/.local/state/ua-watchdog.log"
    }

    /// Heartbeat — the watchdog writes epoch seconds here every tick, so a stale
    /// value means it has stopped checking.
    public static func heartbeat(home: String) -> String {
        "\(home)/.local/state/ua-watchdog.heartbeat"
    }

    /// The launchd domain target for a per-user GUI agent, e.g. `gui/501`.
    public static func guiDomain(uid: UInt32) -> String { "gui/\(uid)" }

    /// The fully-qualified service target, e.g. `gui/501/com.nicholassmith.ua-watchdog`.
    public static func serviceTarget(uid: UInt32) -> String {
        "\(guiDomain(uid: uid))/\(label)"
    }
}
