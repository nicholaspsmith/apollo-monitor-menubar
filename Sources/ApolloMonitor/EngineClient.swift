import ApolloMonitorCore
import Foundation
import Network
import OSLog

/// A menu-bar app has nowhere to print, so connection and level changes go to
/// the unified log: `log stream --predicate 'subsystem == "com.nicholaspsmith.ApolloMonitor"'`
let log = Logger(subsystem: "com.nicholaspsmith.ApolloMonitor", category: "engine")

/// Everything the UI needs to render.
struct MonitorState: Equatable {
    var socketConnected = false
    var monitorResolved = false
    var deviceOnline = false
    var deviceName: String?
    /// Knob travel, 0...1, exactly as the engine reports it. Drives the slider and
    /// the menu-bar gauge; never quantised on the way in.
    var tapered = 0.0
    /// The precise level. Defaults to silence, never unity: if anything ever acts
    /// before the real value arrives, it must not step down from 0 dB.
    var db = LevelDb.minimum
    var muted = false
    var dimmed = false

    /// True when the level can actually be changed right now.
    var isLive: Bool { socketConnected && monitorResolved && deviceOnline }

    /// One line describing the connection, for the top menu row.
    var statusLine: String {
        guard socketConnected else { return "UA Mixer Engine not running" }
        guard monitorResolved else { return "No MONITOR output found" }
        let name = deviceName ?? "Apollo"
        return "\(name) · \(deviceOnline ? "Connected" : "Disconnected")"
    }
}

/// One long-lived connection to UA Mixer Engine.
///
/// Everything runs on the main queue: the messages are tiny and local, and
/// keeping a single thread removes any question of racing the menu code that
/// reads `state`.
final class EngineClient {
    private static let host = NWEndpoint.Host("127.0.0.1")
    private static let port = NWEndpoint.Port(rawValue: 4710)!
    private static let keepaliveInterval: TimeInterval = 3
    private static let minReconnectDelay: TimeInterval = 0.5
    private static let maxReconnectDelay: TimeInterval = 5

    private var connection: NWConnection?
    private var parser = FrameParser()
    private var keepaliveTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectDelay = EngineClient.minReconnectDelay

    private var deviceIndex = 0
    private var monitorOutput: Int?
    /// Output nodes we asked about while hunting for MONITOR.
    private var probedOutputs: Set<Int> = []

    private(set) var state = MonitorState()
    var onChange: ((MonitorState) -> Void)?

    // MARK: - Lifecycle

    func start() {
        guard connection == nil else { return }

        parser = FrameParser()
        monitorOutput = nil
        probedOutputs = []

        let connection = NWConnection(host: Self.host, port: Self.port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                log.notice("socket ready")
                self.reconnectDelay = Self.minReconnectDelay
                self.update { $0.socketConnected = true }
                self.receiveLoop()
                self.startKeepalive()
                self.discover()
            case .failed, .cancelled:
                self.teardownAndRetry()
            case .waiting:
                // Nothing is listening yet (Console/engine not up). NWConnection
                // stays in .waiting and retries on its own, but it never reports
                // .failed, so drive our own retry rather than hanging here.
                self.teardownAndRetry()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func teardownAndRetry() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        stopKeepalive()

        update {
            $0.socketConnected = false
            $0.monitorResolved = false
            $0.deviceOnline = false
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTimer == nil else { return }
        let delay = reconnectDelay
        reconnectDelay = min(Self.maxReconnectDelay, reconnectDelay * 2)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.reconnectTimer = nil
            self?.start()
        }
    }

    private func startKeepalive() {
        stopKeepalive()
        // UA's own clients write /Sleep every few seconds; without it the engine
        // is free to drop an idle socket.
        keepaliveTimer = Timer.scheduledTimer(
            withTimeInterval: Self.keepaliveInterval, repeats: true
        ) { [weak self] _ in
            self?.send(StateTreeCodec.set(Paths.sleep, false))
        }
    }

    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }

    // MARK: - I/O

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                for message in self.parser.append(data) { self.handle(message) }
            }
            if isComplete || error != nil {
                self.teardownAndRetry()
                return
            }
            self.receiveLoop()
        }
    }

    // MARK: - Discovery

    /// Walk /devices → outputs → the output named MONITOR, then subscribe.
    /// The output index is not hardcoded: it is 4 on this Twin MkII but that is
    /// a property of the device's channel layout, not of the protocol.
    private func discover() {
        send(StateTreeCodec.get(Paths.devices))
    }

    private func handleDevicesReply(_ message: StateTreeMessage) {
        let children = message.value?[Paths.Key.children]?.objectKeys ?? []
        let indices = children.compactMap(Int.init).sorted()
        guard let first = indices.first else { return }

        deviceIndex = first
        send(StateTreeCodec.get(Paths.deviceName(deviceIndex)))
        send(StateTreeCodec.subscribe(Paths.deviceOnline(deviceIndex)))
        send(StateTreeCodec.get(Paths.outputs(deviceIndex)))
    }

    private func handleOutputsReply(_ message: StateTreeMessage) {
        let children = message.value?[Paths.Key.children]?.objectKeys ?? []
        for output in children.compactMap(Int.init).sorted() {
            probedOutputs.insert(output)
            send(StateTreeCodec.get(Paths.output(device: deviceIndex, output: output)))
        }
    }

    private func handleOutputNodeReply(_ message: StateTreeMessage, output: Int) {
        let properties = message.value?[Paths.Key.properties]
        let name = properties?[Paths.Key.name]?[Paths.Key.value]?.stringValue
        guard name == Paths.monitorOutputName else { return }

        // The node reply already carries the current level, and it must be
        // applied in the SAME update that flips `monitorResolved`: observers act
        // the moment the state goes live, so publishing "resolved" while `index`
        // is still the default 0 makes the first step run from the wrong value.
        guard
            let tapered = properties?[Paths.Key.monitorLevelTapered]?[Paths.Key.value]?.doubleValue,
            let db = properties?[Paths.Key.monitorLevelDb]?[Paths.Key.value]?.doubleValue
        else {
            log.error("output \(output, privacy: .public) is named MONITOR but has no level properties")
            return
        }

        log.notice("MONITOR resolved to output \(output, privacy: .public) on device \(self.deviceIndex, privacy: .public)")
        monitorOutput = output
        update {
            $0.monitorResolved = true
            $0.tapered = KnobPosition.clampTapered(tapered)
            $0.db = LevelDb.clamp(db)
        }

        send(StateTreeCodec.subscribe(Paths.monitorLevelTapered(device: deviceIndex, output: output)))
        send(StateTreeCodec.subscribe(Paths.monitorLevelDb(device: deviceIndex, output: output)))
        send(StateTreeCodec.subscribe(Paths.mute(device: deviceIndex, output: output)))
        send(StateTreeCodec.subscribe(Paths.dimOn(device: deviceIndex, output: output)))
    }

    // MARK: - Dispatch

    private func handle(_ message: StateTreeMessage) {
        if message.isError {
            log.error("\(message.path, privacy: .public) -> \(message.error ?? "?", privacy: .public)")
            return
        }

        if message.path == Paths.devices {
            handleDevicesReply(message)
            return
        }
        if message.path == Paths.outputs(deviceIndex) {
            handleOutputsReply(message)
            return
        }
        if message.path == Paths.deviceName(deviceIndex) {
            let name = message.value?.stringValue
            update { $0.deviceName = name }
            return
        }
        if message.path == Paths.deviceOnline(deviceIndex) {
            let online = message.value?.boolValue ?? false
            update { $0.deviceOnline = online }
            return
        }

        // An output node we probed during discovery.
        for output in probedOutputs
        where message.path == Paths.output(device: deviceIndex, output: output) {
            handleOutputNodeReply(message, output: output)
            return
        }

        guard let output = monitorOutput else { return }

        if message.path == Paths.monitorLevelTapered(device: deviceIndex, output: output) {
            // Pushes arrive for our own writes and for the hardware knob alike;
            // both map back through the same rounding, so neither needs special
            // handling.
            if let tapered = message.value?.doubleValue {
                update { $0.tapered = KnobPosition.clampTapered(tapered) }
            }
        } else if message.path == Paths.monitorLevelDb(device: deviceIndex, output: output) {
            if let db = message.value?.doubleValue {
                update { $0.db = LevelDb.clamp(db) }
            }
        } else if message.path == Paths.mute(device: deviceIndex, output: output) {
            if let muted = message.value?.boolValue { update { $0.muted = muted } }
        } else if message.path == Paths.dimOn(device: deviceIndex, output: output) {
            if let dimmed = message.value?.boolValue { update { $0.dimmed = dimmed } }
        }
    }

    private func update(_ mutate: (inout MonitorState) -> Void) {
        var copy = state
        mutate(&copy)
        guard copy != state else { return }

        if copy.db != state.db || copy.tapered != state.tapered {
            log.notice("level \(LevelDb.label(copy.db), privacy: .public) (\(KnobPosition.percent(tapered: copy.tapered), privacy: .public)%)")
        }
        if copy.deviceOnline != state.deviceOnline || copy.deviceName != state.deviceName {
            log.notice("device \(copy.deviceName ?? "?", privacy: .public) online=\(copy.deviceOnline, privacy: .public)")
        }
        if copy.socketConnected != state.socketConnected, !copy.socketConnected {
            log.notice("socket lost; reconnecting")
        }

        state = copy
        onChange?(copy)
    }

    // MARK: - Commands

    /// Write a knob position as a whole percent. The engine snaps it to its own
    /// 1/54 grid and pushes back the real position, which is what gets displayed.
    func setPercent(_ percent: Int) {
        guard let output = monitorOutput, state.isLive else { return }
        let tapered = KnobPosition.tapered(percent: percent)

        // Move the UI now rather than waiting for the echo, so dragging feels
        // immediate; the echo corrects it to the snapped value milliseconds later.
        update { $0.tapered = tapered }
        send(StateTreeCodec.set(
            Paths.monitorLevelTapered(device: deviceIndex, output: output), tapered
        ))
    }

    /// Write a precise level in dB. This is the fine path — `CRMonitorLevel` holds
    /// arbitrary values, unlike the tapered property's 1/54 grid.
    func setDb(_ db: Double) {
        guard let output = monitorOutput, state.isLive else { return }
        let clamped = LevelDb.clamp(db)

        // Optimistic, so key repeats compound from the value just written rather
        // than racing the echo. The tapered index follows when the echo lands.
        update { $0.db = clamped }
        send(StateTreeCodec.set(
            Paths.monitorLevelDb(device: deviceIndex, output: output), clamped
        ))
    }

    /// One step of `step` dB — what a volume key press does. Held keys pass a
    /// larger step (see `StepAcceleration`).
    func stepDb(_ direction: StepDirection, step: Double = LevelDb.defaultStep) {
        setDb(LevelDb.next(db: state.db, direction, step: step))
    }

    func setMuted(_ muted: Bool) {
        guard let output = monitorOutput, state.isLive else { return }
        send(StateTreeCodec.set(Paths.mute(device: deviceIndex, output: output), muted))
    }

    func setDimmed(_ dimmed: Bool) {
        guard let output = monitorOutput, state.isLive else { return }
        send(StateTreeCodec.set(Paths.dimOn(device: deviceIndex, output: output), dimmed))
    }
}
