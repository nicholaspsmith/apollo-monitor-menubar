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
///
/// **On the panel being rebuilt.** After ~16 hours of uptime spanning sleep/wake
/// and a display being detached, a running instance reached the state where every
/// `show()` ran with a correct frame on a valid screen and `orderFrontRegardless()`
/// returned, yet the window server had no window for this process at all — nothing
/// appeared. Restarting fixed it instantly with identical inputs. App hiding and a
/// closed window were both tested and ruled out, and the trigger was never
/// reproduced.
///
/// Detecting it from inside is not possible either: `CGWindowListCopyWindowInfo`
/// answers differently for the calling process, reporting this app's own
/// ordered-out window as on screen. So the panel is not repaired on detection — it
/// is replaced across the transitions that preceded the failure (waking, a screen
/// configuration change, or simply having gone unused for a while). Building one is
/// sub-millisecond and this never fires during a run of key presses.
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

    private var panel: NSPanel
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let track = NSView()
    private let fill = NSView()
    private var hideTimer: Timer?

    /// When the overlay was last needed, for the idle rule in `OverlayRefresh`.
    private var lastShownAt = Date()
    /// Symbol rendering is not free, and a held key redraws this several times a
    /// second for one of only four images.
    private var symbolCache: [String: NSImage] = [:]

    init() {
        // Subviews are built once and reparented into each panel, so a rebuild
        // costs only the window itself.
        icon.frame = NSRect(x: Layout.inset, y: Layout.height - 38, width: 18, height: 18)
        icon.contentTintColor = .labelColor

        nameLabel.frame = NSRect(
            x: Layout.inset + 26, y: Layout.height - 37,
            width: Layout.width - Layout.inset * 2 - 26, height: 16
        )
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        valueLabel.frame = NSRect(
            x: Layout.width - Layout.inset - 62, y: Layout.inset - 4, width: 62, height: 14
        )
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        track.frame = NSRect(
            x: Layout.inset, y: Layout.inset,
            width: Layout.width - Layout.inset * 2 - 68, height: Layout.barHeight
        )
        track.wantsLayer = true
        track.layer?.cornerRadius = Layout.barHeight / 2
        track.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.22).cgColor

        fill.frame = NSRect(x: 0, y: 0, width: 0, height: Layout.barHeight)
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Layout.barHeight / 2
        fill.layer?.backgroundColor = NSColor.labelColor.cgColor
        track.addSubview(fill)

        panel = Self.makePanel()
        adoptSubviews()

        // The two environmental changes known to have preceded the failure.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildPanel(reason: "screen parameters changed")
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildPanel(reason: "woke from sleep")
        }
    }

    // MARK: - Panel construction

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
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
        // Held by a strong reference; releasing it on close would be a use-after
        // free waiting to happen.
        panel.isReleasedWhenClosed = false
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
        return panel
    }

    /// Move the shared subviews into the current panel. `addSubview` reparents, so
    /// this also detaches them from any previous one.
    private func adoptSubviews() {
        guard let background = panel.contentView else { return }
        for view in [icon, nameLabel, valueLabel, track] {
            background.addSubview(view)
        }
    }

    private func rebuildPanel(reason: String) {
        log.notice("HUD rebuilding panel: \(reason, privacy: .public)")
        let old = panel
        old.orderOut(nil)
        panel = Self.makePanel()
        adoptSubviews()
    }

    // MARK: - Showing

    /// Show the overlay, or refresh it if already visible, and restart the timer.
    ///
    /// `fraction` is knob travel (0...1) for the bar; `db` is the precise level,
    /// which is what actually moves on every press — the bar is quantised to the
    /// engine's coarse 1/54 reporting grid, so the number carries the fine detail.
    func show(deviceName: String?, db: Double, fraction: Double) {
        let now = Date()
        if OverlayRefresh.needsFreshPanel(lastShownAt: lastShownAt, now: now) {
            rebuildPanel(reason: "unused for \(Int(now.timeIntervalSince(lastShownAt)))s")
        }
        lastShownAt = now

        nameLabel.stringValue = deviceName ?? "Monitor"
        valueLabel.stringValue = LevelDb.label(db)

        let clamped = max(0, min(1, fraction))
        fill.frame = NSRect(
            x: 0, y: 0, width: track.frame.width * clamped, height: Layout.barHeight
        )
        icon.image = symbol(named: symbolName(for: clamped))

        present()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(
            withTimeInterval: Layout.visibleDuration, repeats: false
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func present() {
        // While the overlay is already up — which is the whole of a held key — the
        // labels have been updated in place and there is nothing else to do.
        // Re-ordering and re-animating every repeat is pure cost.
        if !(panel.isVisible && panel.alphaValue == 1) {
            reposition()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        log.notice("HUD \(self.valueLabel.stringValue, privacy: .public) at \(NSStringFromRect(self.panel.frame), privacy: .public)")
    }

    private func symbol(named name: String) -> NSImage? {
        if let cached = symbolCache[name] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Volume")
        symbolCache[name] = image
        return image
    }

    /// Take it down now — used when the overlay is switched off while it is up.
    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        hide()
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
