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
        case .problem:
            symbol = "exclamationmark.shield.fill"; color = .systemRed
        }

        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let color {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        }

        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "UA Watchdog status")
        let image = base?.withSymbolConfiguration(config) ?? base ?? NSImage()
        image.isTemplate = (color == nil)
        return image
    }
}
