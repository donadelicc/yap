import AppKit
import Core
import CoreGraphics

private let commandVPasteKeyCode: CGKeyCode = 0x09

public final class ClipboardTextInjector: TextInjecting {
    private let pasteboardBox: PasteboardBox
    private let isProcessTrusted: @Sendable () -> Bool
    private let eventFactory: @Sendable (CGKeyCode, Bool) -> CGEvent?
    private let eventPoster: @Sendable (CGEvent) -> Void
    private let restoreDelay: DispatchTimeInterval
    private let restoreQueue: DispatchQueue

    public init() {
        self.pasteboardBox = PasteboardBox(.general)
        self.isProcessTrusted = { AXIsProcessTrusted() }
        self.eventFactory = { keyCode, keyDown in
            CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
        }
        self.eventPoster = { event in
            event.post(tap: .cghidEventTap)
        }
        self.restoreDelay = .milliseconds(150)
        self.restoreQueue = DispatchQueue.global(qos: .userInitiated)
    }

    init(
        pasteboard: NSPasteboard = .general,
        isProcessTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        eventFactory: @escaping @Sendable (CGKeyCode, Bool) -> CGEvent? = { keyCode, keyDown in
            CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
        },
        eventPoster: @escaping @Sendable (CGEvent) -> Void = { event in
            event.post(tap: .cghidEventTap)
        },
        restoreDelay: DispatchTimeInterval = .milliseconds(150),
        restoreQueue: DispatchQueue = DispatchQueue.global(qos: .userInitiated)
    ) {
        self.pasteboardBox = PasteboardBox(pasteboard)
        self.isProcessTrusted = isProcessTrusted
        self.eventFactory = eventFactory
        self.eventPoster = eventPoster
        self.restoreDelay = restoreDelay
        self.restoreQueue = restoreQueue
    }

    public func paste(_ text: String) async throws {
        guard isProcessTrusted() else {
            throw AppError.permissionDenied(.accessibility)
        }

        let pasteboard = pasteboardBox.pasteboard
        let snapshot = PasteboardSnapshot(
            items: pasteboard.pasteboardItems?.map(Self.clonePasteboardItem) ?? []
        )

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard
            let keyDown = eventFactory(commandVPasteKeyCode, true),
            let keyUp = eventFactory(commandVPasteKeyCode, false)
        else {
            throw AppError.pasteFailed("CGEvent creation failed")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        eventPoster(keyDown)
        eventPoster(keyUp)

        restoreQueue.asyncAfter(deadline: .now() + restoreDelay) { [pasteboardBox, snapshot] in
            let pasteboard = pasteboardBox.pasteboard
            pasteboard.clearContents()
            snapshot.items.forEach { item in
                pasteboard.writeObjects([item])
            }
        }
    }

    private static func clonePasteboardItem(_ item: NSPasteboardItem) -> NSPasteboardItem {
        let clone = NSPasteboardItem()

        item.types.forEach { type in
            if let data = item.data(forType: type) {
                clone.setData(data, forType: type)
            }
        }

        return clone
    }
}

private final class PasteboardBox: @unchecked Sendable {
    let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }
}

private struct PasteboardSnapshot: @unchecked Sendable {
    let items: [NSPasteboardItem]
}
