import XCTest
@testable import ApolloMonitorCore

final class StateTreeCodecTests: XCTestCase {
    func testFramesAreNulTerminated() {
        let data = StateTreeCodec.get("/devices/0/DeviceName/value")
        XCTAssertEqual(data.last, 0x00)
        XCTAssertEqual(
            String(decoding: data.dropLast()),
            "get /devices/0/DeviceName/value"
        )
    }

    func testSetFormatsFloatWithoutExponentOrLocale() {
        // The engine parses neither "1e-07" nor a comma decimal separator.
        XCTAssertEqual(
            String(decoding: StateTreeCodec.set("/p", 0.35).dropLast()),
            "set /p 0.350000"
        )

        // Interpolating the Double directly would emit "1e-07" here, which is
        // why the codec goes through String(format:).
        XCTAssertTrue("\(0.0000001)".contains("e-"))
        let tiny = String(decoding: StateTreeCodec.set("/p", 0.0000001).dropLast())
        XCTAssertEqual(tiny, "set /p 0.000000")
        XCTAssertFalse(tiny.contains("e-"))

        XCTAssertFalse(
            String(decoding: StateTreeCodec.set("/p", 0.5).dropLast()).contains(",")
        )
    }

    func testSetFormatsBoolAsLowercaseLiteral() {
        XCTAssertEqual(String(decoding: StateTreeCodec.set("/p", true).dropLast()), "set /p true")
        XCTAssertEqual(String(decoding: StateTreeCodec.set("/p", false).dropLast()), "set /p false")
    }

    func testSubscribeAndUnsubscribeVerbs() {
        XCTAssertEqual(String(decoding: StateTreeCodec.subscribe("/p").dropLast()), "subscribe /p")
        XCTAssertEqual(String(decoding: StateTreeCodec.unsubscribe("/p").dropLast()), "unsubscribe /p")
    }

    func testDecodeNumericPayload() {
        let message = StateTreeCodec.decode(
            frame: Data(#"{"path": "/p", "data": -22.0}"#.utf8)
        )
        XCTAssertEqual(message?.path, "/p")
        XCTAssertEqual(message?.value?.doubleValue, -22.0)
        XCTAssertFalse(message?.isError ?? true)
    }

    /// JSONSerialization hands back NSNumber for both booleans and numbers, so
    /// `true` must not decode as 1.
    func testDecodeBoolPayloadIsNotANumber() {
        let message = StateTreeCodec.decode(frame: Data(#"{"path": "/p", "data": true}"#.utf8))
        XCTAssertEqual(message?.value?.boolValue, true)
        XCTAssertNil(message?.value?.doubleValue)

        let one = StateTreeCodec.decode(frame: Data(#"{"path": "/p", "data": 1}"#.utf8))
        XCTAssertEqual(one?.value?.doubleValue, 1)
        XCTAssertNil(one?.value?.boolValue)
    }

    func testDecodeStringPayload() {
        let message = StateTreeCodec.decode(
            frame: Data(#"{"path": "/p", "data": "Apollo Twin MkII"}"#.utf8)
        )
        XCTAssertEqual(message?.value?.stringValue, "Apollo Twin MkII")
    }

    func testDecodeErrorPayload() {
        let message = StateTreeCodec.decode(
            frame: Data(#"{"path": "/p", "error": "Unable to resolve path for get."}"#.utf8)
        )
        XCTAssertTrue(message?.isError ?? false)
        XCTAssertEqual(message?.error, "Unable to resolve path for get.")
        XCTAssertNil(message?.value)
    }

    /// Verbatim reply shape from `get /devices/0/outputs/4`, which is how the
    /// MONITOR output gets discovered.
    func testDecodeOutputNodeReply() {
        let json = """
        {"path": "/devices/0/outputs/4", "data": {"properties": \
        {"Name": {"type": "string", "value": "MONITOR"}, \
        "CRMonitorLevelTapered": {"type": "float", "value": 0.3148148059844971}}, \
        "children": {}}}
        """
        let message = StateTreeCodec.decode(frame: Data(json.utf8))
        let properties = message?.value?[Paths.Key.properties]
        XCTAssertEqual(properties?[Paths.Key.name]?[Paths.Key.value]?.stringValue, "MONITOR")
        XCTAssertEqual(
            properties?[Paths.Key.monitorLevelTapered]?[Paths.Key.value]?.doubleValue,
            0.3148148059844971
        )
    }

    func testDecodeDevicesReplyChildKeys() {
        let json = #"{"path": "/devices", "data": {"properties": {}, "children": {"0": {}}}}"#
        let message = StateTreeCodec.decode(frame: Data(json.utf8))
        XCTAssertEqual(message?.value?[Paths.Key.children]?.objectKeys, ["0"])
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(StateTreeCodec.decode(frame: Data("not json".utf8)))
        XCTAssertNil(StateTreeCodec.decode(frame: Data(#"{"no":"path"}"#.utf8)))
    }
}

final class FrameParserTests: XCTestCase {
    private func frame(_ path: String, _ value: String) -> Data {
        StateTreeCodec.frame(#"{"path": "\#(path)", "data": \#(value)}"#)
    }

    func testParsesSingleFrame() {
        var parser = FrameParser()
        let messages = parser.append(frame("/a", "1"))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.path, "/a")
        XCTAssertEqual(parser.pendingByteCount, 0)
    }

    /// One receive can carry several messages — a subscribe burst does exactly
    /// this on connect.
    func testParsesSeveralFramesFromOneRead() {
        var parser = FrameParser()
        var batch = Data()
        batch.append(frame("/a", "1"))
        batch.append(frame("/b", "2"))
        batch.append(frame("/c", "3"))

        let messages = parser.append(batch)
        XCTAssertEqual(messages.map(\.path), ["/a", "/b", "/c"])
        XCTAssertEqual(parser.pendingByteCount, 0)
    }

    /// TCP gives no framing guarantees: a message can arrive split anywhere,
    /// including mid-UTF8 and mid-number.
    func testReassemblesFrameSplitAcrossReads() {
        let whole = frame("/devices/0/DeviceName/value", #""Apollo Twin MkII""#)

        for splitPoint in 1..<whole.count {
            var parser = FrameParser()
            let first = parser.append(whole.prefix(splitPoint))
            XCTAssertTrue(first.isEmpty, "emitted early at split \(splitPoint)")

            let second = parser.append(whole.suffix(from: splitPoint))
            XCTAssertEqual(second.count, 1, "lost message at split \(splitPoint)")
            XCTAssertEqual(second.first?.value?.stringValue, "Apollo Twin MkII")
            XCTAssertEqual(parser.pendingByteCount, 0)
        }
    }

    func testHoldsIncompleteTailUntilTerminatorArrives() {
        var parser = FrameParser()
        var batch = frame("/a", "1")
        batch.append(Data(#"{"path": "/b", "data""#.utf8))  // no terminator

        let messages = parser.append(batch)
        XCTAssertEqual(messages.map(\.path), ["/a"])
        XCTAssertGreaterThan(parser.pendingByteCount, 0)

        let rest = parser.append(Data(#": 2}"#.utf8) + Data([StateTreeCodec.terminator]))
        XCTAssertEqual(rest.map(\.path), ["/b"])
        XCTAssertEqual(parser.pendingByteCount, 0)
    }

    func testSkipsEmptyFramesAndUndecodableOnes() {
        var parser = FrameParser()
        var batch = Data([StateTreeCodec.terminator])          // empty frame
        batch.append(StateTreeCodec.frame("garbage"))          // not JSON
        batch.append(frame("/a", "1"))                         // good

        XCTAssertEqual(parser.append(batch).map(\.path), ["/a"])
    }
}

private extension String {
    /// Decode a byte slice for assertions.
    init(decoding bytes: some Sequence<UInt8>) {
        self = String(decoding: Data(bytes), as: UTF8.self)
    }
}
