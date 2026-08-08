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
}
