import Foundation

/// UA Mixer Engine's launchd identity, for restarting it the way the watchdog does.
public enum MixerEngine {
    public static let label = "com.uaudio.ua_mixer_engine"

    public static func serviceTarget(uid: uid_t) -> String { "gui/\(uid)/\(label)" }
}

/// Decides when a stale mixer engine should be restarted.
///
/// The failure this exists for (seen 2026-09-09): after a deep sleep the engine
/// re-mounts the Thunderbolt bus with zero hardware devices and leaves
/// `DeviceOnline` false for good, while macOS still lists the Apollo as a Core
/// Audio device. Every client — Console, this app — then faithfully shows the
/// Apollo as disconnected. Restarting the engine (`launchctl kickstart -k`) makes
/// it re-enumerate and the device comes straight back.
///
/// "Stale" is the conjunction of three facts: the socket is up (the engine is
/// running and answering), the engine says the device is offline, and Core Audio
/// says Universal Audio hardware is present. Any one alone is a different
/// situation — an unplugged Apollo, an engine that isn't running — that a restart
/// would not help, so none of them triggers one.
///
/// Guards against making things worse:
///   - a grace period, so the engine's own re-enumeration after wake (which
///     takes tens of seconds) is never pre-empted;
///   - one attempt per offline episode — if the restart didn't bring the device
///     back, restarting again won't either, and each restart pauses audio;
///   - a cooldown across episodes, so a flapping device can't drive a restart
///     loop.
///
/// Pure: the app feeds it snapshots and a clock and acts on the answer.
public struct EngineRecoveryPolicy: Equatable {
    public struct Snapshot: Equatable {
        public var socketConnected: Bool
        public var deviceOnline: Bool
        public var hardwarePresent: Bool

        public init(socketConnected: Bool, deviceOnline: Bool, hardwarePresent: Bool) {
            self.socketConnected = socketConnected
            self.deviceOnline = deviceOnline
            self.hardwarePresent = hardwarePresent
        }

        var isStale: Bool { socketConnected && !deviceOnline && hardwarePresent }
    }

    public enum Action: Equatable {
        case none
        case restartEngine
    }

    public static let defaultGrace: TimeInterval = 60
    public static let defaultCooldown: TimeInterval = 600

    public let grace: TimeInterval
    public let cooldown: TimeInterval

    /// When the current stale stretch began, or nil while not stale.
    private var staleSince: Date?
    /// Set by a restart (automatic or manual); cleared when the device comes online.
    private var attemptedThisEpisode = false
    private var lastAttempt: Date?

    public init(grace: TimeInterval = defaultGrace, cooldown: TimeInterval = defaultCooldown) {
        self.grace = grace
        self.cooldown = cooldown
    }

    /// The moment a restart becomes due if the stale state persists, or nil if no
    /// restart is pending (not stale, or this episode already had its attempt).
    /// For the menu: "restarting the engine in 40s".
    public var pendingRestartAt: Date? {
        guard let staleSince, !attemptedThisEpisode else { return nil }
        let afterGrace = staleSince.addingTimeInterval(grace)
        guard let lastAttempt else { return afterGrace }
        return max(afterGrace, lastAttempt.addingTimeInterval(cooldown))
    }

    /// Feed the current facts. Call on every engine state change and on a coarse
    /// tick (a few seconds) so the grace period elapses even when nothing changes.
    public mutating func update(_ snapshot: Snapshot, now: Date) -> Action {
        if snapshot.deviceOnline {
            attemptedThisEpisode = false
        }
        guard snapshot.isStale else {
            staleSince = nil
            return .none
        }
        if staleSince == nil { staleSince = now }

        guard let due = pendingRestartAt, now >= due else { return .none }
        return .restartEngine
    }

    /// The engine was (or is being) restarted. Counts as this episode's attempt
    /// whether the policy asked for it or the user clicked the menu item.
    public mutating func noteRestartIssued(now: Date) {
        attemptedThisEpisode = true
        lastAttempt = now
        staleSince = nil
    }

    /// The machine woke from sleep. Timers pending across sleep fire immediately
    /// on wake, so without this a stale stretch that began before sleep would
    /// trigger a restart at the very moment the engine is re-enumerating.
    public mutating func noteWake(now: Date) {
        if staleSince != nil { staleSince = now }
    }
}
