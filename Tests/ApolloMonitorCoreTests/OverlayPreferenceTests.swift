import XCTest
@testable import ApolloMonitorCore

final class OverlayPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "OverlayPreferenceTests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    /// The overlay is the app's main feedback once the system HUD is suppressed,
    /// so a fresh install must have it on.
    func testDefaultsToEnabledWhenNeverSet() {
        XCTAssertNil(defaults.object(forKey: OverlayPreference.key))
        XCTAssertTrue(OverlayPreference(defaults: defaults).isEnabled)
    }

    /// The reason `object(forKey:)` is used: `bool(forKey:)` reports false for a
    /// key that was never written, which is indistinguishable from a real false.
    func testDisabledIsDistinguishableFromUnset() {
        XCTAssertFalse(defaults.bool(forKey: OverlayPreference.key), "unset reads as false")

        let preference = OverlayPreference(defaults: defaults)
        preference.isEnabled = false
        XCTAssertFalse(preference.isEnabled)
        XCTAssertNotNil(defaults.object(forKey: OverlayPreference.key))
    }

    func testRoundTripsBothWays() {
        let preference = OverlayPreference(defaults: defaults)
        preference.isEnabled = false
        XCTAssertFalse(OverlayPreference(defaults: defaults).isEnabled)

        preference.isEnabled = true
        XCTAssertTrue(OverlayPreference(defaults: defaults).isEnabled)
    }
}
