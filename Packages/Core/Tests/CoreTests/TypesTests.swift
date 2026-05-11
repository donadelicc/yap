import XCTest
@testable import Core

final class TypesTests: XCTestCase {
    func testAudioBufferDurationMs() {
        XCTAssertEqual(AudioBuffer(samples: []).durationMs, 0)
        XCTAssertEqual(AudioBuffer(samples: Array(repeating: 0, count: 16_000)).durationMs, 1_000)
        XCTAssertEqual(AudioBuffer(samples: Array(repeating: 0, count: 8_000)).durationMs, 500)
    }

    func testRecordingStateEquality() {
        XCTAssertEqual(RecordingState.idle, .idle)
        XCTAssertNotEqual(RecordingState.recording, .idle)
        XCTAssertEqual(
            RecordingState.error(.cleanupTimedOut),
            .error(.cleanupTimedOut)
        )
        XCTAssertNotEqual(
            RecordingState.error(.cleanupTimedOut),
            .error(.transcriptionFailed("x"))
        )
    }

    func testHotkeyBindingAllCasesCount() {
        XCTAssertEqual(HotkeyBinding.allCases.count, 4)
    }
}
