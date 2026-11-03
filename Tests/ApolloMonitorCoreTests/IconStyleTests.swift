// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ApolloMonitorCore

final class IconStyleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "IconStyleTests"

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

    /// The Preferences window writes the same key the Icon submenu did, so an
    /// existing choice survives the move.
    func testKeyIsUnchanged() {
        XCTAssertEqual(IconStyle.key, "iconStyle")
        defaults.set("arc", forKey: "iconStyle")
        XCTAssertEqual(IconStyle.load(from: defaults), .arc)
    }

    func testDefaultsToTheFace() {
        XCTAssertEqual(IconStyle.load(from: defaults), .apollo)
    }

    /// The old "rocket" value, or anything else unknown, reads as the face.
    func testUnknownValueReadsAsTheFace() {
        defaults.set("rocket", forKey: IconStyle.key)
        XCTAssertEqual(IconStyle.load(from: defaults), .apollo)
    }

    func testRoundTrips() {
        for style in IconStyle.allCases {
            style.save(to: defaults)
            XCTAssertEqual(IconStyle.load(from: defaults), style)
        }
    }

    /// The tiles appear in this order, face first, with these captions.
    func testOrderAndTitles() {
        XCTAssertEqual(IconStyle.allCases, [.apollo, .arc])
        XCTAssertEqual(IconStyle.allCases.map(\.title), ["Apollo", "Arc"])
    }
}
