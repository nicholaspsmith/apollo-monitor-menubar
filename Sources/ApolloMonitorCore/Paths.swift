/// StateTree paths.
///
/// Leaf reads and writes address `<node>/value`; asking for the node itself
/// returns its type descriptor and children instead, which is how the MONITOR
/// output is discovered.
public enum Paths {
    public static let devices = "/devices"

    /// Per-connection keepalive. UA's own clients write this every few seconds.
    public static let sleep = "/Sleep"

    public static func device(_ index: Int) -> String { "\(devices)/\(index)" }

    public static func deviceName(_ index: Int) -> String { "\(device(index))/DeviceName/value" }

    public static func deviceOnline(_ index: Int) -> String { "\(device(index))/DeviceOnline/value" }

    public static func outputs(_ index: Int) -> String { "\(device(index))/outputs" }

    public static func output(device: Int, output: Int) -> String {
        "\(outputs(device))/\(output)"
    }

    public static func outputName(device: Int, output: Int) -> String {
        "\(Self.output(device: device, output: output))/Name/value"
    }

    /// Knob position, 0.0...1.0 — what the app reads and writes.
    public static func monitorLevelTapered(device: Int, output: Int) -> String {
        "\(Self.output(device: device, output: output))/CRMonitorLevelTapered/value"
    }

    /// Level in dB, −96.0...0.0 — display only.
    public static func monitorLevelDb(device: Int, output: Int) -> String {
        "\(Self.output(device: device, output: output))/CRMonitorLevel/value"
    }

    public static func mute(device: Int, output: Int) -> String {
        "\(Self.output(device: device, output: output))/Mute/value"
    }

    public static func dimOn(device: Int, output: Int) -> String {
        "\(Self.output(device: device, output: output))/DimOn/value"
    }

    /// Property and node keys as they appear in a node reply.
    public enum Key {
        public static let name = "Name"
        public static let monitorLevelTapered = "CRMonitorLevelTapered"
        public static let monitorLevelDb = "CRMonitorLevel"
        public static let value = "value"
        public static let children = "children"
        public static let properties = "properties"
    }

    /// `Name` of the output carrying the monitor (control-room) level.
    public static let monitorOutputName = "MONITOR"
}
