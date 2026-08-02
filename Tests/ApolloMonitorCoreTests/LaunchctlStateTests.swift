import XCTest
@testable import ApolloMonitorCore

final class LaunchctlStateTests: XCTestCase {
    // Trimmed from real `launchctl print gui/501/com.nicholassmith.ua-watchdog`.
    private let printOutput = """
    com.nicholassmith.ua-watchdog = {
        active count = 0
        state = not running
        program = /bin/zsh
        runs = 2956
        last exit code = 0
        run interval = 60 seconds
    }
    """

    func testParsesLastExitCode() {
        XCTAssertEqual(LaunchctlParser.lastExitCode(fromPrint: printOutput), 0)
    }

    func testParsesNonZeroExitCode() {
        let out = "    last exit code = 78\n"
        XCTAssertEqual(LaunchctlParser.lastExitCode(fromPrint: out), 78)
    }

    func testMissingExitCodeIsNil() {
        XCTAssertNil(LaunchctlParser.lastExitCode(fromPrint: "state = running\nruns = 3"))
    }

    // Real `launchctl print-disabled gui/501` format on macOS 26.
    private let disabledOutput = """
    disabled services = {
        "com.docker.helper" => enabled
        "com.nicholassmith.ua-watchdog" => enabled
        "io.tailscale.ipn.macsys.login-item-helper" => enabled
    }
    """

    func testEnabledLabelIsNotDisabled() {
        XCTAssertFalse(
            LaunchctlParser.isDisabled(label: "com.nicholassmith.ua-watchdog", fromPrintDisabled: disabledOutput)
        )
    }

    func testDisabledLabelIsDisabled() {
        let out = disabledOutput.replacingOccurrences(
            of: "\"com.nicholassmith.ua-watchdog\" => enabled",
            with: "\"com.nicholassmith.ua-watchdog\" => disabled"
        )
        XCTAssertTrue(
            LaunchctlParser.isDisabled(label: "com.nicholassmith.ua-watchdog", fromPrintDisabled: out)
        )
    }

    func testLegacyTrueFalseFormat() {
        XCTAssertTrue(LaunchctlParser.isDisabled(label: "x", fromPrintDisabled: "\t\"x\" => true"))
        XCTAssertFalse(LaunchctlParser.isDisabled(label: "x", fromPrintDisabled: "\t\"x\" => false"))
    }

    func testAbsentLabelDefaultsToNotDisabled() {
        XCTAssertFalse(LaunchctlParser.isDisabled(label: "com.absent.thing", fromPrintDisabled: disabledOutput))
    }
}
