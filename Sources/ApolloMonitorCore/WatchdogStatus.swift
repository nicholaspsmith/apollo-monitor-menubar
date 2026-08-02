import Foundation

/// What the menu-bar icon and header convey.
public enum WatchdogState: Equatable {
    case active                 // loaded, enabled, healthy
    case disabled               // booted out / disabled — deliberately off
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
    public var isEnabled: Bool { state != .disabled }

    /// One-line plain-text summary for the `--status` CLI, e.g.
    /// "active · checked 12s ago · last kill UA Mixer Helper · 2 today".
    public var summaryLine: String {
        switch state {
        case .disabled:
            return "disabled"
        case .problem(let reason):
            return "problem: \(reason)"
        case .active:
            var parts = ["active"]
            if let age = heartbeatAge { parts.append("checked \(RelativeTime.short(age)) ago") }
            if let kill = lastKill { parts.append("last kill \(kill.label)") }
            parts.append("\(killsToday) today")
            return parts.joined(separator: " · ")
        }
    }
}

public enum WatchdogStatusBuilder {
    /// The watchdog fires every 60s; allow a few missed ticks before calling a
    /// loaded-but-silent agent a problem, so a normal gap never flickers red.
    public static let staleHeartbeatThreshold: TimeInterval = 210

    /// - Parameters:
    ///   - isBootstrapped: `launchctl print <service>` succeeded (agent is loaded).
    ///   - lastExitCode: parsed from that print (nil ⇒ hasn't completed a run).
    ///   - isDisabled: from `print-disabled`.
    ///   - heartbeat: epoch of the last tick, or nil.
    ///   - now: current time.
    ///   - log: full text of the action log.
    public static func build(
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
        if isDisabled || !isBootstrapped {
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
