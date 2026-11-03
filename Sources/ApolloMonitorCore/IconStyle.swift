// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The menu-bar icon: the Apollo face (tick arc = level) or the plain arc.
/// Persisted under `iconStyle`; anything unrecognised there (the old "rocket"
/// value among them) reads as the face.
public enum IconStyle: String, CaseIterable {
    case apollo, arc

    public static let key = "iconStyle"

    public var title: String { self == .apollo ? "Apollo" : "Arc" }

    public static func load(from defaults: UserDefaults = .standard) -> IconStyle {
        defaults.string(forKey: key).flatMap(IconStyle.init) ?? .apollo
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }

    public static var current: IconStyle {
        get { load() }
        set { newValue.save() }
    }
}
