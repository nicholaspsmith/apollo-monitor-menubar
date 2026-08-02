import XCTest
@testable import ApolloMonitorCore

final class RelativeTimeTests: XCTestCase {
    func testFormatsSecondsMinutesHours() {
        XCTAssertEqual(RelativeTime.short(0), "0s")
        XCTAssertEqual(RelativeTime.short(12), "12s")
        XCTAssertEqual(RelativeTime.short(59), "59s")
        XCTAssertEqual(RelativeTime.short(60), "1m")
        XCTAssertEqual(RelativeTime.short(185), "3m")
        XCTAssertEqual(RelativeTime.short(3600), "1h")
        XCTAssertEqual(RelativeTime.short(7200), "2h")
    }

    func testSummaryLineForEachState() {
        let killLog = "2026-08-01 09:00:00  KILLED orphaned UA Mixer Helper pid=1 cpu=100.0% (fast-path: PPID=1)"
        let active = WatchdogStatus(
            state: .active, heartbeatAge: 12,
            lastKill: LogParser.lastKill(killLog), killsToday: 2
        )
        XCTAssertEqual(active.summaryLine, "active · checked 12s ago · last kill UA Mixer Helper · 2 today")

        let disabled = WatchdogStatus(state: .disabled, heartbeatAge: nil, lastKill: nil, killsToday: 0)
        XCTAssertEqual(disabled.summaryLine, "disabled")

        let problem = WatchdogStatus(state: .problem("last run exited 1"), heartbeatAge: 5, lastKill: nil, killsToday: 0)
        XCTAssertEqual(problem.summaryLine, "problem: last run exited 1")
    }
}
