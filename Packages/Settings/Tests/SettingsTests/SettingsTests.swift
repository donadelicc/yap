import Core
import Foundation
import Settings
import XCTest

final class SettingsTests: XCTestCase {
    func testRoundTripPersistsSettingsAcrossServiceInstances() {
        let suiteName = makeSuiteName()
        defer { removeSuite(named: suiteName) }

        let service = UserDefaultsSettingsService(suiteName: suiteName)
        service.update {
            $0.hotkeyBinding = .rightCommand
            $0.sttModelId = "custom-stt"
            $0.llmModelId = "custom-llm"
            $0.llmEnabled = false
            $0.language = nil
            $0.soundEffectsEnabled = true
            $0.minRecordingMs = 350
            $0.maxRecordingMs = 12_000
        }

        let restored = UserDefaultsSettingsService(suiteName: suiteName)

        XCTAssertEqual(restored.current, service.current)
    }

    func testUpdateModifiesValueAndBroadcastsChanges() async {
        let suiteName = makeSuiteName()
        defer { removeSuite(named: suiteName) }

        let service = UserDefaultsSettingsService(suiteName: suiteName)
        var iterator = service.changes.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial, AppSettings())

        service.update {
            $0.soundEffectsEnabled = true
            $0.language = "nb"
        }

        let changed = await iterator.next()
        XCTAssertEqual(changed?.soundEffectsEnabled, true)
        XCTAssertEqual(changed?.language, "nb")
        XCTAssertEqual(service.current.soundEffectsEnabled, true)
        XCTAssertEqual(service.current.language, "nb")
    }

    func testDefaultsAreCorrectWhenNothingIsStored() {
        let suiteName = makeSuiteName()
        defer { removeSuite(named: suiteName) }

        let service = UserDefaultsSettingsService(suiteName: suiteName)

        XCTAssertEqual(service.current.hotkeyBinding, .rightOption)
        XCTAssertEqual(service.current.sttModelId, "openai_whisper-small.en")
        XCTAssertEqual(service.current.llmModelId, "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
        XCTAssertEqual(service.current.llmEnabled, true)
        XCTAssertEqual(service.current.language, "en")
        XCTAssertEqual(service.current.soundEffectsEnabled, false)
        XCTAssertEqual(service.current.minRecordingMs, 200)
        XCTAssertEqual(service.current.maxRecordingMs, 60_000)
    }

    func testConcurrentUpdatesDoNotLoseWrites() async {
        let suiteName = makeSuiteName()
        defer { removeSuite(named: suiteName) }

        let service = UserDefaultsSettingsService(suiteName: suiteName)
        let taskCount = 50

        await withTaskGroup(of: Void.self) { group in
            for value in 1...taskCount {
                group.addTask {
                    service.update {
                        $0.minRecordingMs = value
                    }
                }
            }
        }

        XCTAssertTrue((1...taskCount).contains(service.current.minRecordingMs))

        let restored = UserDefaultsSettingsService(suiteName: suiteName)
        XCTAssertEqual(restored.current.minRecordingMs, service.current.minRecordingMs)
    }

    private func makeSuiteName() -> String {
        "com.donadelicc.yap.settings-tests.\(UUID().uuidString)"
    }

    private func removeSuite(named suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}
