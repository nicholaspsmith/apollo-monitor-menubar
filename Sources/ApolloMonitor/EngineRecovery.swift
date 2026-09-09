import ApolloMonitorCore
import Foundation
import StatusItemKit

/// Restarts a mixer engine that has lost the Apollo — the app-side half of
/// `EngineRecoveryPolicy`: it feeds the policy what the engine and Core Audio say,
/// and when the policy asks for it (or the user does, from the menu) runs the same
/// `launchctl kickstart -k` the watchdog uses. No sudo: the engine is a user agent.
final class EngineRecovery {
    struct Attempt: Equatable {
        let date: Date
        let succeeded: Bool
        let manual: Bool
    }

    private var policy = EngineRecoveryPolicy()
    private let notifier = Notifier()
    private var notifierAuthorized = false
    private var restartInFlight = false

    /// The most recent restart this process issued, for the menu.
    private(set) var lastAttempt: Attempt?

    var pendingRestartAt: Date? { policy.pendingRestartAt }

    /// Run on every engine state change and on a coarse tick.
    func evaluate(_ state: MonitorState, hardwarePresent: Bool, now: Date = Date()) {
        let snapshot = EngineRecoveryPolicy.Snapshot(
            socketConnected: state.socketConnected,
            deviceOnline: state.deviceOnline,
            hardwarePresent: hardwarePresent
        )
        if policy.update(snapshot, now: now) == .restartEngine {
            log.notice("engine reports the Apollo offline while Core Audio has it; restarting UA Mixer Engine")
            restart(manual: false, now: now)
        }
    }

    func noteWake(now: Date = Date()) {
        policy.noteWake(now: now)
    }

    /// The menu's "Restart UA Mixer Engine" item.
    func restartNow(now: Date = Date()) {
        log.notice("restarting UA Mixer Engine at the user's request")
        restart(manual: true, now: now)
    }

    private func restart(manual: Bool, now: Date) {
        guard !restartInFlight else { return }
        restartInFlight = true
        policy.noteRestartIssued(now: now)

        // Off the main thread: launchctl returns in milliseconds, but the volume
        // keys run through this process's run loop and must not wait on a child.
        let target = MixerEngine.serviceTarget(uid: getuid())
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ok = Shell.run("/bin/launchctl", ["kickstart", "-k", target]) != nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.restartInFlight = false
                self.lastAttempt = Attempt(date: now, succeeded: ok, manual: manual)
                if ok {
                    log.notice("UA Mixer Engine restarted")
                } else {
                    log.error("launchctl kickstart -k \(target, privacy: .public) failed")
                }
                if !manual { self.notify(succeeded: ok) }
            }
        }
    }

    /// Authorization is requested here rather than at launch, so the permission
    /// prompt appears alongside the first thing worth telling the user about.
    private func notify(succeeded: Bool) {
        if !notifierAuthorized {
            notifier.requestAuthorization()
            notifierAuthorized = true
        }
        notifier.post(
            title: "Apollo Monitor",
            body: succeeded
                ? "The mixer engine had lost the Apollo; restarted it."
                : "The mixer engine has lost the Apollo and could not be restarted."
        )
    }
}
