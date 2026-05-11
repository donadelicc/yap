import XCTest
import Core
import SwiftUI
@testable import MenuBarUI

final class MenuBarUITests: XCTestCase {
    func testRecordingIconBodyDoesNotCrash() {
        let icon = MenuBarIcon(state: .recording)
        _ = icon.body
    }

    func testMenuBarContentBodyDoesNotCrashForEveryRecordingState() {
        let states: [RecordingState] = [
            .idle,
            .recording,
            .transcribing,
            .cleaning,
            .pasting,
            .error(.pasteFailed("Target app rejected paste"))
        ]

        for state in states {
            let content = MenuBarContent(
                state: state,
                lastError: nil,
                onOpenSettings: {},
                onQuit: {}
            )

            _ = content.body
        }
    }
}
