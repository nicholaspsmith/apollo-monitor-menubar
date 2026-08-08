import Foundation

/// What the menu-bar icon and header convey.
public enum WatchdogState: Equatable {
    case active                 // loaded, enabled, healthy
    case disabled               // booted out / disabled — deliberately off
    case notInstalled           // no plist — never installed, or it was removed
    case problem(String)        // loaded but unhealthy (bad exit, or gone quiet)
}

/// The full display model, composed from launchd state + heartbeat + the log.
public struct WatchdogStatus: Equatable {
    public let state: WatchdogState
    /// Seconds since the last heartbeat, or nil if there's no heartbeat file yet.
    public let heartbeatAge: TimeInterval?
    public let lastKill: LogEvent?
    public let killsToday: Int

    public init(state: WatchdogState, heartbeatAge: TimeInterval?, lastKill: LogEvent?, killsToday: Int) {
        self.state = state
        self.heartbeatAge = heartbeatAge
        self.lastKill = lastKill
        self.killsToday = killsToday
    }

    /// True unless deliberately turned off — drives the Disable/Enable menu label.
    /// A missing agent is not "enabled": there is nothing to disable.
    public var isEnabled: Bool { state != .disabled && state != .notInstalled }

    /// Whether toggling can do anything. With no plist, `launchctl bootstrap` has
    /// no file to load, so the menu greys the toggle out rather than offering an
    /// action that always fails.
    public var isToggleable: Bool { state != .notInstalled }
}

public enum WatchdogStatusBuilder {
    /// The watchdog fires every 60s; allow a few missed ticks before calling a
    /// loaded-but-silent agent a problem, so a normal gap never flickers red.
    public static let staleHeartbeatThreshold: TimeInterval = 210

    /// - Parameters:
    ///   - isInstalled: the LaunchAgent plist exists on disk.
    ///   - isBootstrapped: `launchctl print <service>` succeeded (agent is loaded).
    ///   - lastExitCode: parsed from that print (nil ⇒ hasn't completed a run).
    ///   - isDisabled: from `print-disabled`.
    ///   - heartbeat: epoch of the last tick, or nil.
    ///   - now: current time.
    ///   - log: full text of the action log.
    public static func build(
        isInstalled: Bool,
        isBootstrapped: Bool,
        lastExitCode: Int?,
        isDisabled: Bool,
        heartbeat: Date?,
        now: Date,
        log: String,
        staleThreshold: TimeInterval = staleHeartbeatThreshold
    ) -> WatchdogStatus {
        let age = heartbeat.map { now.timeIntervalSince($0) }

        let state: WatchdogState
        // Absence is checked first and beats every other signal: launchd can still
        // report a service whose plist was deleted, and "off because you said so"
        // must not be confused with "was never here".
        if !isInstalled {
            state = .notInstalled
        } else if isDisabled || !isBootstrapped {
            state = .disabled
        } else if let code = lastExitCode, code != 0 {
            state = .problem("last run exited \(code)")
        } else if let age, age > staleThreshold {
            state = .problem("no check in \(Int(age))s")
        } else {
            state = .active
        }

        return WatchdogStatus(
            state: state,
            heartbeatAge: age,
            lastKill: LogParser.lastKill(log),
            killsToday: LogParser.killsToday(log, now: now)
        )
    }
}
