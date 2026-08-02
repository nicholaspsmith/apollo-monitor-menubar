import Foundation
import StatusItemKit
import ApolloMonitorCore

/// Reads the watchdog LaunchAgent's live state and toggles it — the app's bridge
/// between `launchctl`/files and the pure `UAWatchdogCore` model. Every action is
/// in the user's own `gui/<uid>` domain, so nothing here needs sudo.
struct WatchdogController {
    private let uid = getuid()
    private var home: String { NSHomeDirectory() }

    /// Gather current state. `launchctl print` exits non-zero (→ Shell returns nil)
    /// when the agent isn't loaded, which is exactly our "not bootstrapped" signal.
    func status(now: Date = Date()) -> WatchdogStatus {
        let printText = Shell.run("/bin/launchctl", ["print", WatchdogPaths.serviceTarget(uid: uid)])
        let disabledText = Shell.run("/bin/launchctl", ["print-disabled", WatchdogPaths.guiDomain(uid: uid)]) ?? ""

        return WatchdogStatusBuilder.build(
            isBootstrapped: printText != nil,
            lastExitCode: printText.flatMap(LaunchctlParser.lastExitCode(fromPrint:)),
            isDisabled: LaunchctlParser.isDisabled(label: WatchdogPaths.label, fromPrintDisabled: disabledText),
            heartbeat: readHeartbeat(),
            now: now,
            log: (try? String(contentsOfFile: WatchdogPaths.log(home: home), encoding: .utf8)) ?? ""
        )
    }

    /// Persistently enable or disable the agent. Disable also `disable`s it so it
    /// stays off across reboots; enable re-`enable`s and bootstraps it back in.
    func setEnabled(_ enabled: Bool) {
        let service = WatchdogPaths.serviceTarget(uid: uid)
        let domain = WatchdogPaths.guiDomain(uid: uid)
        if enabled {
            _ = Shell.run("/bin/launchctl", ["enable", service])
            _ = Shell.run("/bin/launchctl", ["bootstrap", domain, WatchdogPaths.plist(home: home)])
        } else {
            _ = Shell.run("/bin/launchctl", ["bootout", service])   // may 'not loaded' — fine
            _ = Shell.run("/bin/launchctl", ["disable", service])
        }
    }

    private func readHeartbeat() -> Date? {
        guard
            let text = try? String(contentsOfFile: WatchdogPaths.heartbeat(home: home), encoding: .utf8),
            let secs = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: secs)
    }
}
