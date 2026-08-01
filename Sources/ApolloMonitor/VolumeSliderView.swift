import ApolloMonitorCore
import AppKit

/// A horizontal monitor-level slider for use as an `NSMenuItem.view`.
///
/// The knob sits at the position the engine reports, continuously — no quantising
/// on the display side, so it always matches Console. Dragging writes whole
/// percents; the engine snaps those to its own 1/54 grid and pushes back the real
/// position, which is what then gets shown.
///
/// Three AppKit details drive the shape of this:
///
/// 1. `NSMenu` reads a view's frame at insertion time, before any auto-layout
///    pass, so a constraint-only view would be zero-sized. Everything is laid out
///    with explicit frames (the same reason `MenuBuilder` does).
/// 2. An open menu runs its own modal event-tracking loop and does not reliably
///    deliver continuous drags to embedded views, so `NSSlider`'s own tracking
///    cannot be relied on. This view pulls events straight off the window queue
///    in `mouseDown` instead and treats the slider as a drawn control.
/// 3. For (2) to ever run, the click must not be swallowed by the `NSSlider`
///    subview sitting under the cursor — hence the `hitTest` override. Without
///    it, mouse events go to the slider, whose tracking the menu suppresses, and
///    dragging does nothing at all.
final class VolumeSliderView: NSView {
    private enum Layout {
        static let leftPad: CGFloat = 20
        static let rightPad: CGFloat = 12
        static let sliderWidth: CGFloat = 150
        static let labelWidth: CGFloat = 96
        static let gap: CGFloat = 8
        static let height: CGFloat = 24
        /// Half a knob width. See `KnobPosition.percent(atX:…)`.
        static let knobInset: CGFloat = 9
        static let knobDiameter: CGFloat = 18
        static let trackHeight: CGFloat = 4
    }

    private let readoutLabel = NSTextField(labelWithString: "")

    /// Called with a whole percent while dragging, de-duplicated.
    var onPercentChange: ((Int) -> Void)?
    /// Called when the drag finishes, so the caller can re-apply live state that was
    /// ignored during tracking.
    var onTrackingEnd: (() -> Void)?

    /// Knob travel, 0...1, as reported by the engine.
    private var tapered: Double
    private var db: Double
    private var isLive: Bool
    /// External updates are ignored mid-drag: the engine echoes a snapped value
    /// within milliseconds of each write, and applying it under the cursor would
    /// drag the knob back out from under the user.
    private var isTracking = false

    init(tapered: Double, db: Double, isLive: Bool) {
        self.tapered = KnobPosition.clampTapered(tapered)
        self.db = db
        self.isLive = isLive

        let width = Layout.leftPad + Layout.sliderWidth + Layout.gap
            + Layout.labelWidth + Layout.rightPad
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))

        readoutLabel.frame = NSRect(
            x: Layout.leftPad + Layout.sliderWidth + Layout.gap,
            y: (Layout.height - 16) / 2,
            width: Layout.labelWidth,
            height: 16
        )
        readoutLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        readoutLabel.textColor = .secondaryLabelColor
        readoutLabel.alignment = .right
        addSubview(readoutLabel)

        refreshLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - External updates

    /// Reflect a level that changed underneath us — the hardware knob, Console's
    /// fader, or a volume key pressed while the menu is open. Setting a control's
    /// value programmatically does not fire its action, so this cannot loop.
    func apply(tapered newTapered: Double, db newDb: Double, isLive newIsLive: Bool) {
        guard !isTracking else { return }
        tapered = KnobPosition.clampTapered(newTapered)
        db = newDb
        isLive = newIsLive
        needsDisplay = true
        refreshLabel()
    }

    // MARK: - Drawing

    /// `NSSlider` is not used for this. Its `trackFillColor` — the documented way
    /// to tint the filled portion — is ignored by AppKit, so the control can only
    /// be drawn as a uniform grey bar that reads as inactive. Since this view
    /// already owns hit-testing and tracking, `NSSlider` was contributing nothing
    /// but that drawing, and doing it here is both deterministic and a visual match
    /// for the overlay's bar.
    override func draw(_ dirtyRect: NSRect) {
        let track = trackRect
        let radius = track.height / 2

        NSColor.labelColor.withAlphaComponent(isLive ? 0.20 : 0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let centre = knobCentreX
        var filled = track
        filled.size.width = max(0, centre - track.minX)
        if filled.width > radius {
            (isLive ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
            NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
        }

        let knob = NSRect(
            x: centre - Layout.knobDiameter / 2,
            y: bounds.midY - Layout.knobDiameter / 2,
            width: Layout.knobDiameter,
            height: Layout.knobDiameter
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        (isLive ? NSColor.white : NSColor.white.withAlphaComponent(0.55)).setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.14).setStroke()
        NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    private var trackRect: NSRect {
        NSRect(
            x: Layout.leftPad,
            y: (Layout.height - Layout.trackHeight) / 2,
            width: Layout.sliderWidth,
            height: Layout.trackHeight
        )
    }

    /// The knob's centre travels between the track's insets, matching the geometry
    /// `KnobPosition.percent(atX:…)` inverts.
    private var knobCentreX: CGFloat {
        let track = trackRect
        let usable = track.width - Layout.knobInset * 2
        return track.minX + Layout.knobInset + usable * CGFloat(tapered)
    }

    private func refreshLabel() {
        // Both units: the slider shows knob position, but a volume key moves the
        // level by a whole dB, which the percentage is too coarse to reflect.
        readoutLabel.stringValue =
            "\(KnobPosition.percent(tapered: tapered))% · \(LevelDb.label(db))"
        readoutLabel.textColor = isLive ? .labelColor : .tertiaryLabelColor
    }

    // MARK: - Tracking

    /// Keep every mouse event in this view rather than letting the `NSSlider`
    /// subview take it — see the class comment.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isLive, let window else { return }

        isTracking = true
        defer {
            isTracking = false
            onTrackingEnd?()
        }

        var current = event
        while true {
            commit(at: current.locationInWindow)
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                break
            }
            if next.type == .leftMouseUp {
                commit(at: next.locationInWindow)
                break
            }
            current = next
        }
    }

    private func commit(at locationInWindow: NSPoint) {
        let local = convert(locationInWindow, from: nil)
        commit(percent: KnobPosition.percent(
            atX: local.x,
            trackMinX: trackRect.minX,
            trackWidth: trackRect.width,
            knobInset: Layout.knobInset
        ))
    }

    private func commit(percent: Int) {
        // Clamp before the comparison, so stepping past an end is a no-op rather
        // than repeatedly re-sending the same clamped value.
        let target = KnobPosition.clampPercent(percent)
        guard target != KnobPosition.percent(tapered: tapered) else { return }

        tapered = KnobPosition.tapered(percent: target)
        needsDisplay = true
        refreshLabel()
        onPercentChange?(target)
    }

    // MARK: - Accessibility

    // Drawing the control by hand means describing it by hand too, so VoiceOver
    // still sees a slider it can read and adjust.

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Monitor level" }
    override func accessibilityValue() -> Any? { KnobPosition.percent(tapered: tapered) }
    override func isAccessibilityEnabled() -> Bool { isLive }

    override func accessibilityPerformIncrement() -> Bool {
        guard isLive else { return false }
        commit(percent: KnobPosition.percent(tapered: tapered) + 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isLive else { return false }
        commit(percent: KnobPosition.percent(tapered: tapered) - 1)
        return true
    }

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        guard isLive, let percent = (accessibilityValue as? NSNumber)?.intValue else { return }
        commit(percent: KnobPosition.clampPercent(percent))
    }
}
