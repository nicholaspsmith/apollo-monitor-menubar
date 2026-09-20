// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ApolloMonitorCore

/// The menu-bar shield glyph for a watchdog state. Active is a *template* image so
/// the menu bar tints it like a native item (and inverts it when the menu opens);
/// disabled/problem use a palette colour so "off" and "trouble" read at a glance.
enum WatchdogIcon {
    static func image(for state: WatchdogState) -> NSImage {
        let symbol: String
        let color: NSColor?
        switch state {
        case .active:
            symbol = "checkmark.shield.fill"; color = nil
        case .disabled:
            symbol = "shield.slash"; color = .systemGray
        case .notInstalled:
            // Distinct from `disabled`'s slash: nothing was turned off here, the
            // agent simply isn't there.
            symbol = "xmark.shield"; color = .systemGray
        case .problem:
            symbol = "exclamationmark.shield.fill"; color = .systemRed
        }

        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let color {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        }

        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Mixer Watchdog status")
        let image = base?.withSymbolConfiguration(config) ?? base ?? NSImage()
        image.isTemplate = (color == nil)
        return image
    }
}
