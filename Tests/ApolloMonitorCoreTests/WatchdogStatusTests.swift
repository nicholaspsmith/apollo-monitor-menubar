import XCTest
@testable import ApolloMonitorCore

final class WatchdogStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_754_040_000)

    private func build(
        bootstrapped: Bool = true,
        exit: Int? = 0,
        disabled: Bool = false,
        heartbeatAgo: TimeInterval? = 30,
        log: String = ""
    ) -> WatchdogStatus {
        WatchdogStatusBuilder.build(
            isBootstrapped: bootstrapped,
            lastExitCode: exit,
            isDisabled: disabled,
            heartbeat: heartbeatAgo.map { now.addingTimeInterval(-$0) },
            now: now,
            log: log
        )
    }

    func testHealthyLoadedAgentIsActive() {
        XCTAssertEqual(build().state, .active)
        XCTAssertEqual(build().heartbeatAge, 30)
        XCTAssertTrue(build().isEnabled)
    }

    func testDisabledFlagWins() {
        XCTAssertEqual(build(disabled: true).state, .disabled)
        XCTAssertFalse(build(disabled: true).isEnabled)
    }

    func testNotBootstrappedIsDisabled() {
        // Booted out (not loaded) reads as off even if not explicitly `disable`d.
        XCTAssertEqual(build(bootstrapped: false).state, .disabled)
    }

    func testNonZeroExitIsProblem() {
        XCTAssertEqual(build(exit: 1).state, .problem("last run exited 1"))
    }

    func testStaleHeartbeatIsProblem() {
        // Loaded and exit 0, but hasn't checked in well over the threshold.
        XCTAssertEqual(build(heartbeatAgo: 600).state, .problem("no check in 600s"))
    }

    func testMissingHeartbeatIsStillActive() {
        // Just enabled, no heartbeat file yet — not a problem on its own.
        XCTAssertEqual(build(heartbeatAgo: nil).state, .active)
        XCTAssertNil(build(heartbeatAgo: nil).heartbeatAge)
    }

    func testDisabledBeatsProblem() {
        // If it's turned off, a stale/old exit code shouldn't surface as a problem.
        XCTAssertEqual(build(exit: 1, disabled: true).state, .disabled)
    }

    func testCarriesLogDerivedFields() {
        let log = """
        2026-08-01 09:01:00  KILLED runaway UA Mixer Sentinel pid=100 cpu=100.0% (>=90% x 2 ticks)
        """
        // now (epoch 1_754_040_000) is 2026-08-01 in the test's calendar.
        let cal = Calendar.current
        let killDate = LogParser.lastKill(log)!.date
        let status = build(log: log)
        XCTAssertEqual(status.lastKill?.label, "UA Mixer Sentinel")
        XCTAssertEqual(status.killsToday, cal.isDate(killDate, inSameDayAs: now) ? 1 : 0)
    }
}
