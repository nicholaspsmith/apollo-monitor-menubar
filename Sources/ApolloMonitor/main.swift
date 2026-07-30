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
    }

    /// NX media-key codes, from `IOKit/hidsystem/ev_keymap.h`.
    private enum MediaKey {
        static let soundUp: Int32 = 0    // NX_KEYTYPE_SOUND_UP
        static let soundDown: Int32 = 1  // NX_KEYTYPE_SOUND_DOWN
    }

    private var status: StatusItemController!
    private let engine = EngineClient()
    private let output = DefaultOutputWatcher()
    private var tap: HotkeyTap!
    private var trustTimer: Timer?

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

        engine.onChange = { [weak self] state in
            guard let self else { return }
            self.refreshIcon()
            self.sliderView?.apply(index: state.index, isLive: state.isLive)
        }
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
        let direction: StepDirection
        switch token {
        case Token.up: direction = .up
        case Token.down: direction = .down
        default: return false
        }

        guard output.isUniversalAudio, engine.state.isLive else { return false }
        engine.step(direction)
        return true
    }

    // MARK: - Icon + menu

    private func refreshIcon() {
        let state = engine.state
        let fraction = CGFloat(VolumeStep.tapered(index: state.index))
        let live = state.isLive && !state.muted && tap?.isRunning == true

        let icon: NSImage
        if live {
            // Match the default menu-bar glyph colour: a template image is tinted
            // by the system, and inverted when the menu is open. The level reads
            // from the needle angle.
            icon = MeterIcon.gauge(fraction: fraction, color: .black)
            icon.isTemplate = true
        } else {
            // Can't control the level right now — engine down, Apollo offline,
            // muted, or Accessibility not yet granted. The menu says which.
            icon = MeterIcon.gauge(fraction: fraction, color: .systemGray)
        }
        status.setIcon(icon)
    }

    private func buildMenu(_ menu: NSMenu) {
        let state = engine.state

        menu.addItem(disabledItem(state.statusLine))

        let sliderItem = NSMenuItem()
        let slider = VolumeSliderView(index: state.index, isLive: state.isLive)
        slider.onIndexChange = { [weak self] index in self?.engine.setIndex(index) }
        sliderItem.view = slider
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
            menu.addItem(disabledItem("Volume keys: system output isn't the Apollo"))
        }

        menu.addItem(.separator())

        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(actionItem("Quit Apollo Monitor", #selector(quit), key: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Menu selectors

    @objc private func toggleMute() { engine.setMuted(!engine.state.muted) }

    @objc private func toggleDim() { engine.setDimmed(!engine.state.dimmed) }

    @objc private func grantTrust() {
        tap.requestTrust()
        startTapIfPossible()
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
        engine.step(direction)
        // Let the engine's echo land so the number printed is the level the
        // hardware actually settled on, not just what we asked for.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("\(VolumeStep.percent(index: engine.state.index))%")
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
