import ApolloMonitorCore
import AppKit

/// An on-screen volume overlay in the style of the system HUD.
///
/// The system's own HUD is suppressed (the volume key is swallowed), and even when
/// it did appear it was useless here — a slider greyed out because the Apollo has
/// no Core Audio volume for macOS to move. This is the replacement: same idea, but
/// showing the level that actually changed.
///
/// It is a non-activating borderless panel so it never takes focus from whatever
/// you are working in, and it ignores mouse events so it cannot swallow a click.
final class VolumeHUD {
    private enum Layout {
        static let width: CGFloat = 232
        static let height: CGFloat = 62
        static let inset: CGFloat = 14
        static let screenMargin: CGFloat = 16
        static let barHeight: CGFloat = 6
        static let cornerRadius: CGFloat = 16
        static let visibleDuration: TimeInterval = 1.4
    }

    private let panel: NSPanel
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let track = NSView()
    private let fill = NSView()
    private var hideTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0
        // Follow the user across spaces and sit above full-screen apps, the way a
        // system HUD does.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]

        let background = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height)
        )
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Layout.cornerRadius
        background.layer?.masksToBounds = true
        panel.contentView = background

        icon.frame = NSRect(x: Layout.inset, y: Layout.height - 38, width: 18, height: 18)
        icon.image = NSImage(
            systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume"
        )
        icon.contentTintColor = .labelColor
        background.addSubview(icon)

        nameLabel.frame = NSRect(
            x: Layout.inset + 26, y: Layout.height - 37,
            width: Layout.width - Layout.inset * 2 - 26, height: 16
        )
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        background.addSubview(nameLabel)

        valueLabel.frame = NSRect(
            x: Layout.width - Layout.inset - 62, y: Layout.inset - 4, width: 62, height: 14
        )
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        background.addSubview(valueLabel)

        let trackWidth = Layout.width - Layout.inset * 2 - 68
        track.frame = NSRect(
            x: Layout.inset, y: Layout.inset, width: trackWidth, height: Layout.barHeight
        )
        track.wantsLayer = true
        track.layer?.cornerRadius = Layout.barHeight / 2
        track.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.22).cgColor
        background.addSubview(track)

        fill.frame = NSRect(x: 0, y: 0, width: 0, height: Layout.barHeight)
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Layout.barHeight / 2
        fill.layer?.backgroundColor = NSColor.labelColor.cgColor
        track.addSubview(fill)
    }

    /// Show the overlay, or refresh it if already visible, and restart the timer.
    ///
    /// `fraction` is knob travel (0...1) for the bar; `db` is the precise level,
    /// which is what actually moves on every press — the bar is quantised to the
    /// engine's coarse 1/54 reporting grid, so the number carries the fine detail.
    func show(deviceName: String?, db: Double, fraction: Double) {
        nameLabel.stringValue = deviceName ?? "Monitor"
        valueLabel.stringValue = LevelDb.label(db)

        let clamped = max(0, min(1, fraction))
        fill.frame = NSRect(
            x: 0, y: 0, width: track.frame.width * clamped, height: Layout.barHeight
        )

        icon.image = NSImage(
            systemSymbolName: symbolName(for: clamped), accessibilityDescription: "Volume"
        )

        reposition()
        panel.orderFrontRegardless()
        log.notice("HUD \(LevelDb.label(db), privacy: .public) at \(NSStringFromRect(self.panel.frame), privacy: .public)")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(
            withTimeInterval: Layout.visibleDuration, repeats: false
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Top-right of the active screen, under the menu bar — where macOS puts its
    /// own volume HUD.
    private func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: area.maxX - Layout.width - Layout.screenMargin,
            y: area.maxY - Layout.height - Layout.screenMargin
        ))
    }

    private func symbolName(for fraction: Double) -> String {
        switch fraction {
        case ..<0.001: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
