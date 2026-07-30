import Foundation

/// A value decoded from a StateTree reply's `data` field.
public enum StateTreeValue: Equatable, Sendable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case object([String: StateTreeValue])
    case array([StateTreeValue])
    case null

    /// Recursively wrap the output of `JSONSerialization`.
    public init(json: Any) {
        switch json {
        case let n as NSNumber:
            // JSONSerialization returns NSNumber for both booleans and numbers;
            // only the CFType tells them apart.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let s as String:
            self = .string(s)
        case let d as [String: Any]:
            self = .object(d.mapValues { StateTreeValue(json: $0) })
        case let a as [Any]:
            self = .array(a.map { StateTreeValue(json: $0) })
        default:
            self = .null
        }
    }

    public var doubleValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public subscript(key: String) -> StateTreeValue? {
        if case .object(let d) = self { return d[key] }
        return nil
    }

    /// Keys of an object value, in no particular order (used to enumerate
    /// `children` of a node).
    public var objectKeys: [String] {
        if case .object(let d) = self { return Array(d.keys) }
        return []
    }
}

/// One decoded reply or push from UA Mixer Engine.
public struct StateTreeMessage: Equatable, Sendable {
    public let path: String
    public let value: StateTreeValue?
    public let error: String?

    public init(path: String, value: StateTreeValue?, error: String? = nil) {
        self.path = path
        self.value = value
        self.error = error
    }

    public var isError: Bool { error != nil }
}

/// Builds and decodes UA Mixer Engine's wire format: `<verb> <path> [value]`
/// terminated by a NUL byte. A newline terminator is silently ignored by the
/// engine, which makes the socket look dead — the NUL is not optional.
public enum StateTreeCodec {
    public static let terminator: UInt8 = 0x00

    public static func frame(_ command: String) -> Data {
        var data = Data(command.utf8)
        data.append(terminator)
        return data
    }

    public static func get(_ path: String) -> Data { frame("get \(path)") }
    public static func subscribe(_ path: String) -> Data { frame("subscribe \(path)") }
    public static func unsubscribe(_ path: String) -> Data { frame("unsubscribe \(path)") }

    public static func set(_ path: String, _ value: Double) -> Data {
        // Fixed notation, no locale: the engine parses neither "3.5e-01" nor
        // a comma decimal separator. String(format:) with no locale is POSIX.
        frame("set \(path) \(String(format: "%.6f", value))")
    }

    public static func set(_ path: String, _ value: Bool) -> Data {
        frame("set \(path) \(value ? "true" : "false")")
    }

    /// Decode a single frame's payload (no terminator).
    public static func decode(frame: Data) -> StateTreeMessage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: frame),
            let dict = object as? [String: Any],
            let path = dict["path"] as? String
        else { return nil }

        if let error = dict["error"] as? String {
            return StateTreeMessage(path: path, value: nil, error: error)
        }
        guard let data = dict["data"] else {
            return StateTreeMessage(path: path, value: nil, error: nil)
        }
        return StateTreeMessage(path: path, value: StateTreeValue(json: data), error: nil)
    }
}

/// Accumulates bytes off the socket and yields whole messages.
///
/// TCP gives no framing guarantees: one `receive` can deliver half a message,
/// or five of them at once. Everything downstream assumes whole messages, so
/// this is the one place that has to get it right.
public struct FrameParser {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [StateTreeMessage] {
        buffer.append(data)
        var messages: [StateTreeMessage] = []

        while let index = buffer.firstIndex(of: StateTreeCodec.terminator) {
            let frame = Data(buffer[buffer.startIndex..<index])
            // Re-base rather than keeping a slice: Data slices carry a non-zero
            // startIndex, and mixing that with later absolute indices is a
            // reliable way to write an off-by-one.
            buffer = Data(buffer[buffer.index(after: index)...])
            if frame.isEmpty { continue }
            if let message = StateTreeCodec.decode(frame: frame) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Bytes held back waiting for a terminator (diagnostics and tests).
    public var pendingByteCount: Int { buffer.count }
}
