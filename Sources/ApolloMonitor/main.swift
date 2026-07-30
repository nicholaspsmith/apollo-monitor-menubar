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

    /// Arrow keycodes (`kVK_UpArrow` / `kVK_DownArrow`).
    private enum KeyCode {
        static let up: CGKeyCode = 126
        static let down: CGKeyCode = 125
    }

    private var status: StatusItemController!
    private let engine = EngineClient()
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

        tap = HotkeyTap(
            bindings: [
                Binding(token: Token.up, trigger: .key(KeyCode.up, [.command, .option])),
                Binding(token: Token.down, trigger: .key(KeyCode.down, [.command, .option])),
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

    /// Returns true to swallow the key, so ⌘⌥↑/↓ never also reach the focused
    /// app. Unhandled tokens pass through.
    private func handle(token: String) -> Bool {
        switch token {
        case Token.up: engine.step(.up)
        case Token.down: engine.step(.down)
        default: return false
        }
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
