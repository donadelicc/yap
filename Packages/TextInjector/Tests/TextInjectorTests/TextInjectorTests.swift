import AppKit
import Core
import CoreGraphics
@testable import TextInjector
import XCTest

final class TextInjectorTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("TextInjectorTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.clearContents()
        pasteboard = nil
        super.tearDown()
    }

    func testPasteWritesTextBeforeRestore() async throws {
        pasteboard.setString("original", forType: .string)
        let injector = makeInjector(restoreDelay: .seconds(1))

        try await injector.paste("replacement")

        XCTAssertEqual(pasteboard.string(forType: .string), "replacement")
    }

    func testPasteRestoresOriginalPasteboardContentsAfterDelay() async throws {
        let originalItem = NSPasteboardItem()
        originalItem.setString("original", forType: .string)
        originalItem.setString("<b>original</b>", forType: .html)
        pasteboard.writeObjects([originalItem])

        let injector = makeInjector(restoreDelay: .milliseconds(20))

        try await injector.paste("replacement")
        XCTAssertEqual(pasteboard.string(forType: .string), "replacement")

        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(
            pasteboard.pasteboardItems?.first?.string(forType: .html),
            "<b>original</b>"
        )
    }

    func testPasteThrowsPermissionDeniedWhenAccessibilityCheckFails() async throws {
        let injector = makeInjector(isProcessTrusted: false)

        do {
            try await injector.paste("replacement")
            XCTFail("Expected paste to throw")
        } catch AppError.permissionDenied(.accessibility) {
        } catch {
            XCTFail("Expected accessibility permission error, got \(error)")
        }
    }

    private func makeInjector(
        isProcessTrusted: Bool = true,
        restoreDelay: DispatchTimeInterval = .seconds(1)
    ) -> ClipboardTextInjector {
        ClipboardTextInjector(
            pasteboard: pasteboard,
            isProcessTrusted: { isProcessTrusted },
            eventFactory: { keyCode, keyDown in
                CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
            },
            eventPoster: { _ in },
            restoreDelay: restoreDelay,
            restoreQueue: DispatchQueue(label: "TextInjectorTests.restore")
        )
    }
}
