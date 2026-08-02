import XCTest
@testable import ApolloMonitorCore

final class LogParserTests: XCTestCase {
    /// Build a Date from a log-style stamp using the same config LogParser uses,
    /// so `killsToday` (which compares against Calendar.current) is tz-independent.
    private func date(_ stamp: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = LogParser.dateFormat
        return f.date(from: stamp)!
    }

    func testParsesKilledOrphanedHelper() {
        let e = LogParser.parseLine(
            "2026-07-30 16:16:07  KILLED orphaned UA Mixer Helper pid=32329 cpu=100.0% (fast-path: PPID=1)"
        )
        XCTAssertEqual(e?.kind, .killed)
        XCTAssertEqual(e?.label, "UA Mixer Helper")
    }

    func testParsesKilledRunawayLabel() {
        let e = LogParser.parseLine(
            "2026-07-30 16:16:20  KILLED runaway UA Mixer Sentinel pid=32331 cpu=100.0% (>=90% x 2 ticks)"
        )
        XCTAssertEqual(e?.kind, .killed)
        XCTAssertEqual(e?.label, "UA Mixer Sentinel")
    }

    func testParsesWarn() {
        let e = LogParser.parseLine(
            "2026-07-30 16:16:07  WARN UA Mixer Sentinel pid=32331 cpu=100.0% (tick 1/2 >=90%)"
        )
        XCTAssertEqual(e?.kind, .warn)
        XCTAssertEqual(e?.label, "UA Mixer Sentinel")
    }

    func testKickstartLineIsOther() {
        let e = LogParser.parseLine("2026-07-30 16:16:07  kickstarted UA mixer engine to restore audio path")
        XCTAssertEqual(e?.kind, .other)
        XCTAssertEqual(e?.label, "")
    }

    func testNonTimestampedLinesAreNil() {
        XCTAssertNil(LogParser.parseLine(""))
        XCTAssertNil(LogParser.parseLine("===== rekordbox aggregate removal ====="))
        XCTAssertNil(LogParser.parseLine("short"))
    }

    private let sampleLog = """
    2026-08-01 09:00:00  WARN UA Mixer Sentinel pid=100 cpu=95.0% (tick 1/2 >=90%)
    2026-08-01 09:01:00  KILLED runaway UA Mixer Sentinel pid=100 cpu=100.0% (>=90% x 2 ticks)
    2026-08-01 09:02:00  KILLED orphaned UA Mixer Helper pid=200 cpu=100.0% (fast-path: PPID=1)
    2026-08-01 09:02:00  kickstarted UA mixer engine to restore audio path
    2026-07-31 23:59:00  KILLED runaway UAD Meter pid=300 cpu=99.0% (>=90% x 2 ticks)
    """

    func testLastKillIsTheMostRecentKilledLine() {
        let last = LogParser.lastKill(sampleLog)
        XCTAssertEqual(last?.label, "UA Mixer Helper")
        XCTAssertEqual(last?.date, date("2026-08-01 09:02:00"))
    }

    func testKillsTodayCountsOnlyTodaysKills() {
        // Two kills on 08-01, one on 07-31, plus a WARN and a kickstart that must not count.
        XCTAssertEqual(LogParser.killsToday(sampleLog, now: date("2026-08-01 12:00:00")), 2)
        XCTAssertEqual(LogParser.killsToday(sampleLog, now: date("2026-07-31 12:00:00")), 1)
    }

    func testLastKillNilWhenNeverKilled() {
        let onlyWarns = "2026-08-01 09:00:00  WARN UA Connect pid=1 cpu=95.0% (tick 1/2 >=90%)"
        XCTAssertNil(LogParser.lastKill(onlyWarns))
        XCTAssertEqual(LogParser.killsToday(onlyWarns, now: date("2026-08-01 10:00:00")), 0)
    }
}
