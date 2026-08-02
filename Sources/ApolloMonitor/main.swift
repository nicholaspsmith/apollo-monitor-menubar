import ApolloMonitorCore
import AppKit
import HotkeyKit
import StatusItemKit

/// Apollo Monitor — a menu-bar control for the Apollo's monitor level.
///
/// The Apollo exposes no volume control to Core Audio, so macOS volume keys and
/// `set volume` cannot touch it. This drives UA Mixer Engine's StateTree API
/// directly (127.0.0.1:4710) instead, which is the same channel UAD Console
/// uses, and works whether or not the Console window is open.
final class App: NSObject, NSApplicationDelegate {
    private enum Token {
        static let up = "monitor.up"
        static let down = "monitor.down"
        static let mute = "monitor.mute"
    }

    /// NX media-key codes, from `IOKit/hidsystem/ev_keymap.h`.
    private enum MediaKey {
        static let soundUp: Int32 = 0    // NX_KEYTYPE_SOUND_UP
        static let soundDown: Int32 = 1  // NX_KEYTYPE_SOUND_DOWN
        static let mute: Int32 = 7       // NX_KEYTYPE_MUTE
    }

    private var status: StatusItemController!
    private let engine = EngineClient()
    private let output = DefaultOutputWatcher()
    private let hud = VolumeHUD()
    private let overlayPreference = OverlayPreference()
    private var tap: HotkeyTap!
    private var trustTimer: Timer?

    /// Folded-in UA Watchdog surface (a submenu, not a separate app): the launchd
    /// controller, the last status shown (so the toggle knows enable vs disable),
    /// and a clock formatter for the "last kill" time.
    private let watchdog = WatchdogController()
    private var watchdogStatus: WatchdogStatus?
    private let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// What the overlay last reflected, so it only appears on a real change.
    /// Tracked even while the overlay is switched off — see
    /// `showOverlayIfStateChanged`.
    private struct Observed: Equatable {
        let db: Double
        let muted: Bool
    }
    private var lastObserved: Observed?
    /// Coalesced UI work. Redrawing runs on the next main-queue turn rather than
    /// inside the event-tap callback, so the keystroke is never waiting on drawing.
    private var pendingState: MonitorState?
    private var uiRefreshScheduled = false
    /// What the menu-bar icon was last drawn from, to skip identical redraws.
    private var lastIconKey: String?
    /// Cadence tracking for hold acceleration.
    private var lastPressAt: Date?
    private var consecutiveRepeats = 0
    /// Dragging the menu slider is its own feedback; an overlay on top of the open
    /// menu would just be in the way.
    private var hudSuppressedUntil = Date.distantPast

    /// The slider inside the currently-open menu, if any, so pushes from the
    /// hardware knob move it while the user is looking at it.
    private weak var sliderView: VolumeSliderView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in
                self?.reassertTap()
                // Belt and braces: the property listener normally keeps this
                // current, but a stale answer here means the volume keys go to
                // the wrong device.
                self?.output.refresh()
                self?.refreshIcon()
            },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) }
        )
        status.start()

        engine.onChange = { [weak self] state in self?.scheduleUIRefresh(state) }
        engine.start()

        // The machine's own volume keys, not a chord: macOS cannot control the
        // Apollo's level (it has no Core Audio volume), so pressing them today
        // only raises a HUD with a greyed-out slider. Taking them over is both the
        // obvious gesture and free of the conflicts a chord like ⌘⌥↑ runs into.
        //
        // Bound with and without `.fn` because some keyboards report the function
        // layer's modifier on media keys and `Binding.matches` is exact.
        tap = HotkeyTap(
            bindings: [
                Binding(token: Token.up, trigger: .mediaKey(MediaKey.soundUp, [])),
                Binding(token: Token.up, trigger: .mediaKey(MediaKey.soundUp, [.fn])),
                Binding(token: Token.down, trigger: .mediaKey(MediaKey.soundDown, [])),
                Binding(token: Token.down, trigger: .mediaKey(MediaKey.soundDown, [.fn])),
                // Mute must not repeat on hold, or holding it would flap the
                // output on and off several times a second.
                Binding(token: Token.mute, trigger: .mediaKey(MediaKey.mute, []),
                        repeatsOnHold: false),
                Binding(token: Token.mute, trigger: .mediaKey(MediaKey.mute, [.fn]),
                        repeatsOnHold: false),
            ],
            onMatch: { [weak self] token in self?.handle(token: token) ?? false }
        )

        if !tap.isTrusted { tap.requestTrust() }
        startTapIfPossible()
        refreshIcon()
    }

    // MARK: - Tap lifecycle

    private func startTapIfPossible() {
        // Gate on trust, not on start()'s return: an untrusted process can get a
        // non-nil-but-inert tap, and granting permission later won't activate it
        // without recreating.
        guard tap.isTrusted else {
            scheduleTrustRecheck()
            refreshIcon()
            return
        }
        if !tap.isRunning { tap.start() }
        trustTimer?.invalidate()
        trustTimer = nil
        refreshIcon()
    }

    /// Other apps re-create their session taps on display reconfiguration,
    /// head-inserting in front of ours, after which they see our keys first.
    /// Re-creating ours each poll tick keeps it frontmost at negligible cost.
    private func reassertTap() {
        guard let tap, tap.isTrusted, tap.isRunning else { return }
        tap.stop()
        tap.start()
    }

    private func scheduleTrustRecheck() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.tap.isTrusted { self.startTapIfPossible() }
        }
    }

    // MARK: - Action

    /// Returns true to swallow the volume key so macOS never also acts on it —
    /// which is what suppresses the useless greyed-out volume HUD.
    ///
    /// Passing the key through is the important branch: unless the Apollo is both
    /// the current output device and reachable, the key has to keep working the way
    /// it always did, or switching to the built-in speakers would leave them with
    /// no volume keys at all.
    private func handle(token: String) -> Bool {
        guard output.isUniversalAudio, engine.state.isLive else { return false }

        if token == Token.mute {
            engine.toggleMute()
            return true
        }

        let direction: StepDirection
        switch token {
        case Token.up: direction = .up
        case Token.down: direction = .down
        default: return false
        }

        // Everything here is on the event-tap callback, which the system will
        // disable if it dawdles, and which delays the keystroke itself. So this
        // does only arithmetic and a socket write; drawing happens afterwards.
        let now = Date()
        consecutiveRepeats =
            StepAcceleration.isContinuedHold(previous: lastPressAt, now: now)
            ? consecutiveRepeats + 1
            : 0
        lastPressAt = now

        engine.stepDb(direction, step: StepAcceleration.step(consecutiveRepeats: consecutiveRepeats))
        return true
    }

    // MARK: - Coalesced UI

    /// State changes arrive in bursts — the optimistic write, then the engine's dB
    /// echo, then its coarser tapered echo — and each one used to trigger a full
    /// redraw from inside the tap callback. Collapsing them into one pass on the
    /// next main-queue turn keeps the keystroke off the drawing path.
    private func scheduleUIRefresh(_ state: MonitorState) {
        pendingState = state
        guard !uiRefreshScheduled else { return }
        uiRefreshScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.uiRefreshScheduled = false
            guard let state = self.pendingState else { return }
            self.pendingState = nil

            self.refreshIcon()
            self.sliderView?.apply(
                tapered: state.tapered, db: state.db, isLive: state.isLive
            )
            self.showOverlayIfStateChanged(state)
        }
    }

    /// The overlay follows the state itself rather than the keypress, so turning the
    /// knob on the Apollo, moving Console's fader, or muting from the menu all show
    /// the same readout. Driven off dB rather than the tapered position because dB
    /// changes on every single press, and off mute because muting changes no level
    /// at all — without it the mute key would have no visible effect beyond the
    /// menu-bar arc going grey.
    private func showOverlayIfStateChanged(_ state: MonitorState) {
        guard state.isLive else { return }

        // Track even while the overlay is switched off, or the record goes stale:
        // changes made with it off would leave the last *shown* value behind, and
        // coming back to that value later would read as "no change" and show
        // nothing.
        let previous = lastObserved
        lastObserved = Observed(db: state.db, muted: state.muted)

        guard overlayPreference.isEnabled else { return }
        guard let previous, previous != lastObserved else { return }
        guard Date() >= hudSuppressedUntil else { return }

        hud.show(
            deviceName: state.deviceName,
            db: state.db,
            fraction: state.tapered,
            muted: state.muted
        )
    }

    // MARK: - Icon + menu

    private func refreshIcon() {
        let state = engine.state
        let fraction = CGFloat(state.tapered)
        let live = state.isLive && !state.muted && tap?.isRunning == true

        // The arc is 18 points across, so changes finer than this cannot show.
        // Skipping identical redraws matters during a held key, when the level
        // changes several times a second.
        let key = "\(Int((state.tapered * 200).rounded()))|\(live)"
        guard key != lastIconKey else { return }
        lastIconKey = key

        // Full colour, not a template: template tinting keeps only the drawn alpha
        // and would throw the green away. `MeterIcon.arc` draws its track at 28%
        // alpha of the same colour, so this reads as a soft green track with a
        // solid green fill, and stays legible on a light or dark menu bar.
        //
        // Grey when the level cannot be changed — engine down, Apollo offline,
        // muted, or Accessibility not yet granted. The menu says which.
        status.setIcon(MeterIcon.arc(
            fraction: fraction,
            color: live ? .systemGreen : .systemGray
        ))
    }

    private func buildMenu(_ menu: NSMenu) {
        let state = engine.state

        // Take over enabling. AppKit's automatic version disables anything with a
        // nil action, which greys out the status line and the slider row even when
        // the Apollo is connected and both are perfectly current.
        menu.autoenablesItems = false

        menu.addItem(infoItem(state.statusLine, enabled: state.isLive))

        let sliderItem = NSMenuItem()
        let slider = VolumeSliderView(
            tapered: state.tapered, db: state.db, isLive: state.isLive
        )
        slider.onPercentChange = { [weak self] percent in
            guard let self else { return }
            self.hudSuppressedUntil = Date().addingTimeInterval(1)
            self.engine.setPercent(percent)
        }
        // Tracking ignored live updates; show the position the hardware settled on.
        slider.onTrackingEnd = { [weak self] in
            guard let self else { return }
            let current = self.engine.state
            self.sliderView?.apply(
                tapered: current.tapered, db: current.db, isLive: current.isLive
            )
        }
        sliderItem.view = slider
        sliderItem.isEnabled = state.isLive
        sliderView = slider
        menu.addItem(sliderItem)

        menu.addItem(.separator())

        let mute = actionItem("Mute", #selector(toggleMute))
        mute.state = state.muted ? .on : .off
        mute.isEnabled = state.isLive
        menu.addItem(mute)

        let dim = actionItem("Dim", #selector(toggleDim))
        dim.state = state.dimmed ? .on : .off
        dim.isEnabled = state.isLive
        menu.addItem(dim)

        if !(tap?.isTrusted ?? false) {
            menu.addItem(.separator())
            menu.addItem(actionItem("⚠ Grant Accessibility…", #selector(grantTrust)))
        } else if !output.isUniversalAudio {
            // Otherwise "my volume keys stopped controlling the Apollo" is a
            // mystery with no visible cause.
            menu.addItem(.separator())
            // Genuinely an inactive state, so this one stays muted.
            menu.addItem(infoItem("Volume keys: system output isn't the Apollo", enabled: false))
        }

        menu.addItem(.separator())

        menu.addItem(watchdogMenuItem())

        menu.addItem(.separator())

        let overlay = actionItem("Show Volume Overlay", #selector(toggleOverlay))
        overlay.state = overlayPreference.isEnabled ? .on : .off
        menu.addItem(overlay)

        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(actionItem("Quit Apollo Monitor", #selector(quit), key: "q"))
    }

    /// A non-clickable row. `enabled` controls only how it draws — full-strength
    /// when it is reporting something live, muted when it is not.
    private func infoItem(_ title: String, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = enabled
        return item
    }

    private func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - UA Watchdog submenu

    /// The folded-in UA Watchdog surface: its state on the parent item's shield
    /// icon, and a submenu with details + a persistent Disable/Enable toggle. State
    /// is read fresh here (once per menu open), so nothing polls while the menu is
    /// closed.
    private func watchdogMenuItem() -> NSMenuItem {
        let status = watchdog.status()
        watchdogStatus = status

        let item = NSMenuItem(title: "UA Watchdog", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.image = WatchdogIcon.image(for: status.state)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(infoItem(watchdogHeader(status), enabled: status.state != .disabled))

        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        if let kill = status.lastKill {
            let row = NSMenuItem()
            row.view = MenuBuilder.textView(
                "Last kill: \(kill.label) \(clockFormatter.string(from: kill.date))", font: mono
            )
            submenu.addItem(row)
        }
        let killsRow = NSMenuItem()
        killsRow.view = MenuBuilder.textView("Kills today: \(status.killsToday)", font: mono)
        submenu.addItem(killsRow)

        submenu.addItem(.separator())
        submenu.addItem(actionItem(status.isEnabled ? "Disable watchdog" : "Enable watchdog",
                                   #selector(toggleWatchdog)))
        submenu.addItem(actionItem("Show log…", #selector(showWatchdogLog)))

        item.submenu = submenu
        return item
    }

    private func watchdogHeader(_ status: WatchdogStatus) -> String {
        switch status.state {
        case .active:
            if let age = status.heartbeatAge { return "✓ UA Watchdog active · checked \(RelativeTime.short(age)) ago" }
            return "✓ UA Watchdog active"
        case .disabled:
            return "○ UA Watchdog disabled"
        case .problem(let reason):
            return "⚠ UA Watchdog: \(reason)"
        }
    }

    // MARK: - Menu selectors

    @objc private func toggleMute() { engine.setMuted(!engine.state.muted) }

    @objc private func toggleDim() { engine.setDimmed(!engine.state.dimmed) }

    @objc private func grantTrust() {
        tap.requestTrust()
        startTapIfPossible()
    }

    @objc private func toggleOverlay() {
        overlayPreference.isEnabled.toggle()
        // Switching it off while it happens to be on screen should take it down
        // now, not leave it sitting there for its remaining second.
        if !overlayPreference.isEnabled { hud.dismiss() }
    }

    @objc private func toggleWatchdog() {
        watchdog.setEnabled(!(watchdogStatus?.isEnabled ?? true))
    }

    @objc private func showWatchdogLog() {
        let path = WatchdogPaths.log(home: NSHomeDirectory())
        let url = FileManager.default.fileExists(atPath: path)
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLogin() { LoginItem.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Headless one-shot mode

/// `ApolloMonitor --step up|down` adjusts the level once and exits, without a
/// menu-bar item. Two uses: binding the hotkeys with an external tool (this path
/// needs no Accessibility permission, unlike the event tap), and exercising the
/// write path without a UI.
func runHeadlessStep(_ direction: StepDirection) {
    let engine = EngineClient()
    var stepped = false

    engine.onChange = { state in
        guard state.isLive, !stepped else { return }
        stepped = true
        engine.stepDb(direction)
        // Let the engine's echo land so the number printed is the level the
        // hardware actually settled on, not just what we asked for.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print(LevelDb.label(engine.state.db))
            exit(0)
        }
    }
    engine.start()

    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        FileHandle.standardError.write(Data("ApolloMonitor: engine not ready\n".utf8))
        exit(1)
    }

    // The run loop (not dispatchMain) so EngineClient's Timers fire too.
    RunLoop.main.run()
    exit(1)
}

// MARK: - Entry point

let arguments = CommandLine.arguments
if arguments.count >= 2, arguments[1] == "--step" {
    let direction: StepDirection = arguments.count > 2 && arguments[2] == "down" ? .down : .up
    runHeadlessStep(direction)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
