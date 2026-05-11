import Carbon
import Core
import CoreGraphics
import IOKit
import IOKit.hid

public final class CGEventTapHotkeyService: HotkeyService, @unchecked Sendable {
    public let events: AsyncStream<HotkeyEvent>

    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let listenerFactory: @Sendable (HotkeyBinding, @escaping @Sendable () -> Void) -> HotkeyEventListening
    private var binding: HotkeyBinding = .rightOption
    private var listener: HotkeyEventListening?
    private var isStarted = false

    public convenience init() {
        self.init { binding, fallback in
            switch binding {
            case .fn:
                FnHotkeyEventListener(fallbackToRightOption: fallback)
            case .rightOption, .rightCommand, .rightControl:
                CGEventTapModifierListener(binding: binding)
            }
        }
    }

    init(listenerFactory: @escaping @Sendable (HotkeyBinding, @escaping @Sendable () -> Void) -> HotkeyEventListening) {
        var continuation: AsyncStream<HotkeyEvent>.Continuation?
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(16)) {
            continuation = $0
        }
        self.continuation = continuation!
        self.listenerFactory = listenerFactory
    }

    public func setBinding(_ binding: HotkeyBinding) throws {
        self.binding = binding
        guard isStarted else {
            return
        }

        stopLocked()
        try startLocked()
    }

    public func start() throws {
        guard !isStarted else {
            return
        }

        try startLocked()
    }

    public func stop() {
        stopLocked()
    }

    private func startLocked() throws {
        let activeBinding = binding
        let listener = listenerFactory(activeBinding) { [weak self] in
            self?.fallbackFromFnToRightOption()
        }

        self.listener = listener
        isStarted = true

        do {
            try listener.start { [weak self] event in
                self?.continuation.yield(event)
            }
        } catch {
            listener.stop()
            self.listener = nil
            isStarted = false
            throw error
        }
    }

    private func stopLocked() {
        listener?.stop()
        listener = nil
        isStarted = false
    }

    private func fallbackFromFnToRightOption() {
        guard isStarted, binding == .fn else {
            return
        }

        print("warning: fn hotkey did not report through IOHIDManager; falling back to right-option")
        binding = .rightOption
        stopLocked()
        do {
            try startLocked()
        } catch {
            print("warning: right-option hotkey fallback failed: \(error)")
        }
    }
}

private final class CGEventTapModifierListener: HotkeyEventListening, @unchecked Sendable {
    private let binding: HotkeyBinding
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var handler: (@Sendable (HotkeyEvent) -> Void)?

    init(binding: HotkeyBinding) {
        self.binding = binding
    }

    func start(_ handler: @escaping @Sendable (HotkeyEvent) -> Void) throws {
        self.handler = handler

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: CGEventTapModifierListener.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.handler = nil
            throw AppError.permissionDenied(.inputMonitoring)
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            self.handler = nil
            throw AppError.permissionDenied(.inputMonitoring)
        }

        self.eventTap = eventTap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        handler = nil
        isPressed = false
    }

    private func handle(flagsRawValue: UInt64) {
        let result = HotkeyEventDecoder.decode(
            binding: binding,
            flagsRawValue: flagsRawValue,
            previousIsPressed: isPressed
        )
        isPressed = result.isPressed

        if let event = result.event {
            handler?(event)
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard type == .flagsChanged, let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let listener = Unmanaged<CGEventTapModifierListener>.fromOpaque(userInfo).takeUnretainedValue()
        listener.handle(flagsRawValue: event.flags.rawValue)
        return Unmanaged.passUnretained(event)
    }
}

private final class FnHotkeyEventListener: HotkeyEventListening, @unchecked Sendable {
    private static let functionKeyUsagePage = 0xFF03
    private static let functionKeyUsage = 0x0003

    private let fallbackToRightOption: @Sendable () -> Void
    private var manager: IOHIDManager?
    private var handler: (@Sendable (HotkeyEvent) -> Void)?
    private var isPressed = false
    private var didReceiveFunctionKeyReport = false
    private var generation = 0

    init(fallbackToRightOption: @escaping @Sendable () -> Void) {
        self.fallbackToRightOption = fallbackToRightOption
    }

    func start(_ handler: @escaping @Sendable (HotkeyEvent) -> Void) throws {
        self.handler = handler
        generation += 1
        didReceiveFunctionKeyReport = false
        isPressed = false

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: CFDictionary = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ] as CFDictionary

        IOHIDManagerSetDeviceMatching(manager, matching)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            FnHotkeyEventListener.inputValueCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            print("warning: IOHIDManager open failed for fn hotkey; falling back to right-option")
            fallbackToRightOption()
            return
        }

        self.manager = manager
        scheduleNoReportFallback()
    }

    func stop() {
        generation += 1
        handler = nil
        isPressed = false
        didReceiveFunctionKeyReport = false
        let manager = self.manager
        self.manager = nil

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func scheduleNoReportFallback() {
        let currentGeneration = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else {
                return
            }

            let shouldFallback = self.generation == currentGeneration && !self.didReceiveFunctionKeyReport
            if shouldFallback {
                self.fallbackToRightOption()
            }
        }
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard usagePage == Self.functionKeyUsagePage, usage == Self.functionKeyUsage else {
            return
        }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        didReceiveFunctionKeyReport = true
        let result = HotkeyEventDecoder.decode(isPressed: isDown, previousIsPressed: isPressed)
        isPressed = result.isPressed

        if let event = result.event {
            handler?(event)
        }
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else {
            return
        }

        let listener = Unmanaged<FnHotkeyEventListener>.fromOpaque(context).takeUnretainedValue()
        listener.handle(value: value)
    }
}
