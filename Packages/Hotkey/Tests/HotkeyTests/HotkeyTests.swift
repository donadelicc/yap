import Core
import IOKit.hidsystem
import XCTest
@testable import Hotkey

final class HotkeyTests: XCTestCase {
    func testRightOptionDecoderEmitsPressedThenReleased() {
        var result = HotkeyEventDecoder.decode(
            binding: .rightOption,
            flagsRawValue: UInt64(NX_DEVICERALTKEYMASK),
            previousIsPressed: false
        )
        XCTAssertEqual(result.event, .pressed)
        XCTAssertTrue(result.isPressed)

        result = HotkeyEventDecoder.decode(
            binding: .rightOption,
            flagsRawValue: 0,
            previousIsPressed: result.isPressed
        )
        XCTAssertEqual(result.event, .released)
        XCTAssertFalse(result.isPressed)
    }

    func testDecoderIgnoresLeftOptionForRightOptionBinding() {
        let result = HotkeyEventDecoder.decode(
            binding: .rightOption,
            flagsRawValue: UInt64(NX_DEVICELALTKEYMASK),
            previousIsPressed: false
        )

        XCTAssertNil(result.event)
        XCTAssertFalse(result.isPressed)
    }

    func testDecoderSupportsRightCommandAndRightControl() {
        let command = HotkeyEventDecoder.decode(
            binding: .rightCommand,
            flagsRawValue: UInt64(NX_DEVICERCMDKEYMASK),
            previousIsPressed: false
        )
        let control = HotkeyEventDecoder.decode(
            binding: .rightControl,
            flagsRawValue: UInt64(NX_DEVICERCTLKEYMASK),
            previousIsPressed: false
        )

        XCTAssertEqual(command.event, .pressed)
        XCTAssertEqual(control.event, .pressed)
    }

    func testDecoderDedupesSameModifierState() {
        let first = HotkeyEventDecoder.decode(isPressed: true, previousIsPressed: false)
        let second = HotkeyEventDecoder.decode(isPressed: true, previousIsPressed: first.isPressed)

        XCTAssertEqual(first.event, .pressed)
        XCTAssertNil(second.event)
        XCTAssertTrue(second.isPressed)
    }

    func testSetBindingWhileStartedRestartsListener() throws {
        let factory = MockListenerFactory()
        let service = CGEventTapHotkeyService { binding, fallback in
            factory.makeListener(binding: binding, fallback: fallback)
        }

        try service.start()
        try service.setBinding(.rightCommand)

        XCTAssertEqual(factory.bindings, [.rightOption, .rightCommand])
        XCTAssertEqual(factory.listeners.map(\.startCount), [1, 1])
        XCTAssertEqual(factory.listeners.map(\.stopCount), [1, 0])
    }
}

private final class MockListenerFactory: @unchecked Sendable {
    private(set) var bindings: [HotkeyBinding] = []
    private(set) var listeners: [MockListener] = []

    func makeListener(binding: HotkeyBinding, fallback: @escaping @Sendable () -> Void) -> HotkeyEventListening {
        _ = fallback
        let listener = MockListener()
        bindings.append(binding)
        listeners.append(listener)
        return listener
    }
}

private final class MockListener: HotkeyEventListening, @unchecked Sendable {
    private var handler: (@Sendable (HotkeyEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(_ handler: @escaping @Sendable (HotkeyEvent) -> Void) throws {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }
}
