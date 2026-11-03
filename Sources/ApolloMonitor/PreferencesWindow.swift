// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import ApolloMonitorCore
import AppKit
import StatusItemKit
import SwiftUI

/// Apollo Monitor's Preferences window (menu ▸ Preferences…, ⌘,): Start at
/// Login, the volume overlay and the menu-bar icon. It replaced the Settings
/// and Icon submenus, as in Mac Daddy and the rest of Menumon; the window and
/// form are StatusItemKit's shared `PreferencesPane` and `PreferencesForm`.
final class PreferencesModel: ObservableObject {
    @Published var showOverlay: Bool {
        didSet { if showOverlay != oldValue { onOverlay(showOverlay) } }
    }
    @Published var iconStyle: IconStyle {
        didSet { if iconStyle != oldValue { onIconStyle(iconStyle) } }
    }

    private let overlayPreference: OverlayPreference
    private let onOverlay: (Bool) -> Void
    private let onIconStyle: (IconStyle) -> Void

    /// `onOverlay` and `onIconStyle` do what the old menu items did: store the
    /// choice and act on it (take a showing overlay down, redraw the icon).
    init(overlayPreference: OverlayPreference,
         onOverlay: @escaping (Bool) -> Void,
         onIconStyle: @escaping (IconStyle) -> Void) {
        self.overlayPreference = overlayPreference
        self.onOverlay = onOverlay
        self.onIconStyle = onIconStyle
        showOverlay = overlayPreference.isEnabled
        iconStyle = IconStyle.current
    }

    /// Re-reads both, in case something else changed the stored values.
    func refresh() {
        showOverlay = overlayPreference.isEnabled
        iconStyle = IconStyle.current
    }

    /// Each icon as it looks in the bar, at half level and online.
    static let iconChoices: [IconTilePicker<IconStyle>.Choice] = IconStyle.allCases.map { style in
        let image: NSImage
        switch style {
        case .apollo: image = CharacterIcon.apollo(level: 0.5, online: true)
        case .arc: image = MeterIcon.arc(fraction: 0.5, color: .systemGreen)
        }
        return .init(id: style, title: style.title, image: image)
    }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        PreferencesForm {
            Section("General") {
                StartAtLoginToggle()
            }
            Section {
                Toggle("Show Volume Overlay", isOn: $model.showOverlay)
            } header: {
                Text("Volume Overlay")
            } footer: {
                PreferencesNote("Shows the device, a level bar and the exact dB below the menu bar whenever the level or mute changes: from the keys, the knob or Console. Dragging the menu's slider never shows it.")
            }
            Section("Menu Bar Icon") {
                IconTilePicker(PreferencesModel.iconChoices, selection: $model.iconStyle)
            }
        }
    }
}

extension PreferencesPane {
    /// Apollo Monitor's window, re-reading its model each time it is shown.
    static func apolloMonitor(model: PreferencesModel) -> PreferencesPane {
        let pane = PreferencesPane(appName: "Apollo Monitor") { PreferencesView(model: model) }
        pane.onShow = { model.refresh() }
        return pane
    }
}
