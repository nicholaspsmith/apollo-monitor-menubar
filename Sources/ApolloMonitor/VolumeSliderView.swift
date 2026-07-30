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
    }

    private let slider = NSSlider()
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

        slider.frame = NSRect(
            x: Layout.leftPad,
            y: (Layout.height - 20) / 2,
            width: Layout.sliderWidth,
            height: 20
        )
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = self.tapered
        slider.isEnabled = isLive
        // Covers value changes that do not come through `mouseDown`: VoiceOver's
        // increment/decrement, and anything else driving the control directly.
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        addSubview(slider)

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
        slider.doubleValue = tapered
        slider.isEnabled = newIsLive
        refreshLabel()
    }

    private func refreshLabel() {
        // Both units: the slider shows knob position, but a volume key moves the
        // level by a whole dB, which the percentage is too coarse to reflect.
        readoutLabel.stringValue =
            "\(KnobPosition.percent(tapered: tapered))% · \(LevelDb.label(db))"
        readoutLabel.textColor = isLive ? .secondaryLabelColor : .tertiaryLabelColor
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
            trackMinX: slider.frame.minX,
            trackWidth: slider.frame.width,
            knobInset: Layout.knobInset
        ))
    }

    @objc private func sliderChanged() {
        commit(percent: KnobPosition.percent(tapered: slider.doubleValue))
    }

    private func commit(percent: Int) {
        guard percent != KnobPosition.percent(tapered: tapered) else { return }
        tapered = KnobPosition.tapered(percent: percent)
        slider.doubleValue = tapered
        refreshLabel()
        onPercentChange?(percent)
    }
}
