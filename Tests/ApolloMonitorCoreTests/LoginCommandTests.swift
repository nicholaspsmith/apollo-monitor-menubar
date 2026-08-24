import XCTest
@testable import ApolloMonitorCore

final class LoginCommandTests: XCTestCase {
    // argv[0] is always the binary path; parsing starts after it.
    private func parse(_ tail: String...) -> LoginRequest {
        LoginRequest.parse(arguments: ["/path/to/ApolloMonitor"] + tail)
    }

    func testNoFlagMeansRunTheApp() {
        XCTAssertEqual(parse(), .absent)
        XCTAssertEqual(parse("--step", "up"), .absent)
    }

    /// A bare `--login` reports rather than registers: an incomplete command
    /// must not silently change whether the app starts at login.
    func testBareFlagReportsStatus() {
        XCTAssertEqual(parse("--login"), .command(.status))
        XCTAssertEqual(parse("--login", "status"), .command(.status))
    }

    func testOnAndOff() {
        XCTAssertEqual(parse("--login", "on"), .command(.enable))
        XCTAssertEqual(parse("--login", "off"), .command(.disable))
    }

    /// A typo is a usage error, not a silent default to on.
    func testUnrecognisedValueIsRejected() {
        XCTAssertEqual(parse("--login", "yes"), .unrecognized("yes"))
        XCTAssertEqual(parse("--login", "ON"), .unrecognized("ON"))
    }

    /// `--login --step up` must not swallow the next flag as its value.
    func testDoesNotConsumeAFollowingFlag() {
        XCTAssertEqual(parse("--login", "--step"), .command(.status))
    }
}
