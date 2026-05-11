import Core
import CoreGraphics
import IOKit.hidsystem

public enum HotkeyEvent: Sendable {
    case pressed
    case released
}

public protocol HotkeyService: Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    func setBinding(_ binding: HotkeyBinding) throws
    func start() throws
    func stop()
}

struct HotkeyDecodeResult: Equatable {
    let event: HotkeyEvent?
    let isPressed: Bool
}

enum HotkeyEventDecoder {
    static func decode(binding: HotkeyBinding, flagsRawValue: UInt64, previousIsPressed: Bool) -> HotkeyDecodeResult {
        decode(isPressed: isPressed(binding: binding, flagsRawValue: flagsRawValue), previousIsPressed: previousIsPressed)
    }

    static func decode(isPressed: Bool, previousIsPressed: Bool) -> HotkeyDecodeResult {
        switch (previousIsPressed, isPressed) {
        case (false, true):
            HotkeyDecodeResult(event: .pressed, isPressed: true)
        case (true, false):
            HotkeyDecodeResult(event: .released, isPressed: false)
        default:
            HotkeyDecodeResult(event: nil, isPressed: isPressed)
        }
    }

    static func isPressed(binding: HotkeyBinding, flagsRawValue: UInt64) -> Bool {
        guard let mask = DeviceModifierMask(binding: binding) else {
            return false
        }

        return flagsRawValue & mask.rawValue != 0
    }
}

struct DeviceModifierMask: Equatable {
    let rawValue: UInt64

    init?(binding: HotkeyBinding) {
        switch binding {
        case .rightOption:
            rawValue = UInt64(NX_DEVICERALTKEYMASK)
        case .rightCommand:
            rawValue = UInt64(NX_DEVICERCMDKEYMASK)
        case .rightControl:
            rawValue = UInt64(NX_DEVICERCTLKEYMASK)
        case .fn:
            return nil
        }
    }
}

protocol HotkeyEventListening: Sendable {
    func start(_ handler: @escaping @Sendable (HotkeyEvent) -> Void) throws
    func stop()
}
