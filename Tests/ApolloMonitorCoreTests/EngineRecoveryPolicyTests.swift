import XCTest
@testable import ApolloMonitorCore

final class EngineRecoveryPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_450_000)
    private var policy = EngineRecoveryPolicy(grace: 60, cooldown: 600)

    private func stale(_ present: Bool = true) -> EngineRecoveryPolicy.Snapshot {
        .init(socketConnected: true, deviceOnline: false, hardwarePresent: present)
    }
    private var online: EngineRecoveryPolicy.Snapshot {
        .init(socketConnected: true, deviceOnline: true, hardwarePresent: true)
    }
    private var socketDown: EngineRecoveryPolicy.Snapshot {
        .init(socketConnected: false, deviceOnline: false, hardwarePresent: true)
    }

    func testOnlineNeverRestarts() {
        XCTAssertEqual(policy.update(online, now: t0), .none)
        XCTAssertEqual(policy.update(online, now: t0 + 3600), .none)
        XCTAssertNil(policy.pendingRestartAt)
    }

    func testOfflineWithoutHardwareIsNotStale() {
        // Unplugged Apollo: the engine is right, nothing to recover.
        XCTAssertEqual(policy.update(stale(false), now: t0), .none)
        XCTAssertEqual(policy.update(stale(false), now: t0 + 600), .none)
        XCTAssertNil(policy.pendingRestartAt)
    }

    func testSocketDownIsNotStale() {
        // Engine not running is a different problem (and the watchdog's).
        XCTAssertEqual(policy.update(socketDown, now: t0), .none)
        XCTAssertEqual(policy.update(socketDown, now: t0 + 600), .none)
    }

    func testRestartsAfterGrace() {
        XCTAssertEqual(policy.update(stale(), now: t0), .none)
        XCTAssertEqual(policy.pendingRestartAt, t0 + 60)
        XCTAssertEqual(policy.update(stale(), now: t0 + 59), .none)
        XCTAssertEqual(policy.update(stale(), now: t0 + 60), .restartEngine)
    }

    func testOnlyOneAttemptPerEpisode() {
        _ = policy.update(stale(), now: t0)
        XCTAssertEqual(policy.update(stale(), now: t0 + 60), .restartEngine)
        policy.noteRestartIssued(now: t0 + 60)
        XCTAssertNil(policy.pendingRestartAt)
        // Still offline long after — the restart didn't help; don't loop.
        XCTAssertEqual(policy.update(stale(), now: t0 + 120), .none)
        XCTAssertEqual(policy.update(stale(), now: t0 + 7200), .none)
        XCTAssertNil(policy.pendingRestartAt)
    }

    func testRestartingTheEngineDropsTheSocketWithoutEndingTheEpisode() {
        _ = policy.update(stale(), now: t0)
        XCTAssertEqual(policy.update(stale(), now: t0 + 60), .restartEngine)
        policy.noteRestartIssued(now: t0 + 60)
        _ = policy.update(socketDown, now: t0 + 61)
        XCTAssertEqual(policy.update(stale(), now: t0 + 200), .none)
    }

    func testDeviceComingOnlineEndsTheEpisode() {
        _ = policy.update(stale(), now: t0)
        XCTAssertEqual(policy.update(stale(), now: t0 + 60), .restartEngine)
        policy.noteRestartIssued(now: t0 + 60)
        _ = policy.update(online, now: t0 + 63)
        // A fresh episode, past the cooldown, gets its own attempt.
        _ = policy.update(stale(), now: t0 + 700)
        XCTAssertEqual(policy.update(stale(), now: t0 + 760), .restartEngine)
    }

    func testCooldownHoldsAcrossEpisodes() {
        _ = policy.update(stale(), now: t0)
        XCTAssertEqual(policy.update(stale(), now: t0 + 60), .restartEngine)
        policy.noteRestartIssued(now: t0 + 60)
        _ = policy.update(online, now: t0 + 63)
        // Flaps back to offline soon after: grace elapses, but the cooldown hasn't.
        _ = policy.update(stale(), now: t0 + 100)
        XCTAssertEqual(policy.update(stale(), now: t0 + 160), .none)
        XCTAssertEqual(policy.pendingRestartAt, t0 + 660)
        XCTAssertEqual(policy.update(stale(), now: t0 + 659), .none)
        XCTAssertEqual(policy.update(stale(), now: t0 + 660), .restartEngine)
    }

    func testWakeRestartsTheGraceClock() {
        // Timers that were pending across sleep fire at once on wake; a restart
        // at that instant would pre-empt the engine's own re-enumeration.
        _ = policy.update(stale(), now: t0)
        policy.noteWake(now: t0 + 55)
        XCTAssertEqual(policy.update(stale(), now: t0 + 60), .none)
        XCTAssertEqual(policy.pendingRestartAt, t0 + 115)
        XCTAssertEqual(policy.update(stale(), now: t0 + 115), .restartEngine)
    }

    func testBriefOfflineBlipResetsTheClock() {
        _ = policy.update(stale(), now: t0)
        _ = policy.update(online, now: t0 + 30)
        _ = policy.update(stale(), now: t0 + 40)
        XCTAssertEqual(policy.update(stale(), now: t0 + 60), .none)
        XCTAssertEqual(policy.update(stale(), now: t0 + 100), .restartEngine)
    }

    func testManualRestartCountsAsTheEpisodesAttempt() {
        _ = policy.update(stale(), now: t0)
        policy.noteRestartIssued(now: t0 + 10)
        XCTAssertEqual(policy.update(stale(), now: t0 + 120), .none)
    }

    func testServiceTarget() {
        XCTAssertEqual(MixerEngine.serviceTarget(uid: 501), "gui/501/com.uaudio.ua_mixer_engine")
    }
}
