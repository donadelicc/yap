import XCTest
import AudioRecorder
import Core
import Hotkey
import LLMCleanup
import ModelStore
import Permissions
import Settings
import TextInjector
import Transcription
@testable import yap

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testHappyPathPressReleaseTranscribesCleansPastesAndReturnsIdle() async throws {
        let fixture = Fixture()
        fixture.audio.buffers = [.milliseconds(350)]
        fixture.transcriber.transcript = Transcript(text: "raw transcript", language: "en", durationMs: 350)
        fixture.cleaner.cleaned = "clean transcript"

        let coordinator = fixture.makeCoordinator()
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }
        fixture.hotkey.send(.released)

        await waitUntil { fixture.injector.pastedTexts == ["clean transcript"] && coordinator.state == .idle }
        XCTAssertEqual(fixture.transcriber.transcribeCallCount, 1)
        XCTAssertEqual(fixture.cleaner.cleanCallCount, 1)
    }

    func testShortRecordingReturnsIdleWithoutTranscribing() async throws {
        let fixture = Fixture()
        fixture.audio.buffers = [.milliseconds(150)]

        let coordinator = fixture.makeCoordinator()
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }
        fixture.hotkey.send(.released)

        await waitUntil { coordinator.state == .idle && fixture.audio.stopCallCount == 1 }
        XCTAssertEqual(fixture.transcriber.transcribeCallCount, 0)
        XCTAssertTrue(fixture.injector.pastedTexts.isEmpty)
    }

    func testLLMTimeoutPastesRawTranscript() async throws {
        let fixture = Fixture()
        fixture.audio.buffers = [.milliseconds(350)]
        fixture.transcriber.transcript = Transcript(text: "raw transcript", language: "en", durationMs: 350)
        fixture.cleaner.error = AppError.cleanupTimedOut

        let coordinator = fixture.makeCoordinator()
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }
        fixture.hotkey.send(.released)

        await waitUntil { fixture.injector.pastedTexts == ["raw transcript"] && coordinator.state == .idle }
        XCTAssertEqual(fixture.cleaner.cleanCallCount, 1)
    }

    func testLLMDisabledDoesNotCallCleanerAndPastesRawTranscript() async throws {
        let fixture = Fixture()
        fixture.settings.current.llmEnabled = false
        fixture.audio.buffers = [.milliseconds(350)]
        fixture.transcriber.transcript = Transcript(text: "raw transcript", language: "en", durationMs: 350)

        let coordinator = fixture.makeCoordinator()
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }
        fixture.hotkey.send(.released)

        await waitUntil { fixture.injector.pastedTexts == ["raw transcript"] && coordinator.state == .idle }
        XCTAssertEqual(fixture.cleaner.cleanCallCount, 0)
    }

    func testWhisperErrorEntersErrorThenRecoversToIdleWithoutPasting() async throws {
        let fixture = Fixture()
        fixture.audio.buffers = [.milliseconds(350)]
        fixture.transcriber.error = AppError.transcriptionFailed("whisper failed")

        let coordinator = fixture.makeCoordinator(errorRecoveryDelayNanoseconds: 50_000_000)
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }
        fixture.hotkey.send(.released)

        await waitUntil { coordinator.state == .error(.transcriptionFailed("whisper failed")) }
        XCTAssertEqual(coordinator.lastError, .transcriptionFailed("whisper failed"))
        XCTAssertTrue(fixture.injector.pastedTexts.isEmpty)
        await waitUntil { coordinator.state == .idle }
    }

    func testHotkeyPressWhileBusyIsDropped() async throws {
        let fixture = Fixture()
        fixture.audio.buffers = [.milliseconds(350)]

        let coordinator = fixture.makeCoordinator()
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }
        fixture.hotkey.send(.pressed)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(fixture.audio.startCallCount, 1)
        fixture.hotkey.send(.released)
        await waitUntil { coordinator.state == .idle && fixture.audio.stopCallCount == 1 }
    }

    func testPermissionDeniedOnPasteEntersAccessibilityError() async throws {
        let fixture = Fixture()
        fixture.audio.buffers = [.milliseconds(350)]
        fixture.transcriber.transcript = Transcript(text: "raw transcript", language: "en", durationMs: 350)
        fixture.cleaner.cleaned = "clean transcript"
        fixture.injector.error = AppError.permissionDenied(.accessibility)

        let coordinator = fixture.makeCoordinator(errorRecoveryDelayNanoseconds: 500_000_000)
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }
        fixture.hotkey.send(.released)

        await waitUntil { coordinator.state == .error(.permissionDenied(.accessibility)) }
        XCTAssertEqual(coordinator.lastError, .permissionDenied(.accessibility))
    }

    func testMaxRecordingMsAutoReleasesAtCap() async throws {
        let fixture = Fixture()
        fixture.settings.current.minRecordingMs = 0
        fixture.settings.current.maxRecordingMs = 50
        fixture.audio.buffers = [.milliseconds(350)]
        fixture.transcriber.transcript = Transcript(text: "raw transcript", language: "en", durationMs: 350)
        fixture.cleaner.cleaned = "clean transcript"

        let coordinator = fixture.makeCoordinator()
        try await coordinator.start()

        fixture.hotkey.send(.pressed)
        await waitUntil { coordinator.state == .recording }

        await waitUntil { fixture.audio.stopCallCount == 1 && fixture.injector.pastedTexts == ["clean transcript"] }
        XCTAssertEqual(coordinator.state, .idle)
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        if condition() { return }

        let expectation = expectation(description: "condition became true")
        let task = Task { @MainActor in
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: timeout + 0.2)
        task.cancel()

        if !condition() {
            XCTFail("Timed out waiting for condition", file: file, line: line)
        }
    }
}

@MainActor
private final class Fixture {
    let settings = MockSettingsService()
    let permissions = MockPermissionsService()
    let modelStore = MockModelStore()
    let hotkey = MockHotkeyService()
    let audio = MockAudioRecording()
    let transcriber = MockTranscriber()
    let cleaner = MockTextCleaner()
    let injector = MockTextInjector()

    func makeCoordinator(errorRecoveryDelayNanoseconds: UInt64 = 4_000_000_000) -> AppCoordinator {
        AppCoordinator(
            settings: settings,
            permissions: permissions,
            modelStore: modelStore,
            hotkey: hotkey,
            audio: audio,
            transcriber: transcriber,
            cleaner: cleaner,
            injector: injector,
            errorRecoveryDelayNanoseconds: errorRecoveryDelayNanoseconds
        )
    }
}

private final class MockSettingsService: SettingsService, @unchecked Sendable {
    var current = AppSettings()
    let changes = AsyncStream<AppSettings> { $0.finish() }

    func update(_ change: (inout AppSettings) -> Void) {
        change(&current)
    }
}

private final class MockPermissionsService: PermissionsService, @unchecked Sendable {
    let changes = AsyncStream<(Permission, PermissionStatus)> { $0.finish() }

    func status(for: Permission) -> PermissionStatus {
        .granted
    }

    func request(_: Permission) async -> PermissionStatus {
        .granted
    }
}

private final class MockModelStore: ModelStoring, @unchecked Sendable {
    var pathErrors: [String: AppError] = [:]
    var requestedPaths: [String] = []

    func availableModels(kind: ModelKind) async -> [ModelDescriptor] {
        []
    }

    func download(_ id: String) -> AsyncStream<DownloadProgress> {
        AsyncStream { $0.finish() }
    }

    func path(for id: String) async throws -> URL {
        requestedPaths.append(id)
        if let error = pathErrors[id] {
            throw error
        }
        return URL(fileURLWithPath: "/tmp/\(id)")
    }

    func delete(_ id: String) async throws {}
}

private final class MockHotkeyService: HotkeyService, @unchecked Sendable {
    let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    var binding: HotkeyBinding?
    var startCallCount = 0

    init() {
        var continuation: AsyncStream<HotkeyEvent>.Continuation?
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation!
    }

    func setBinding(_ binding: HotkeyBinding) throws {
        self.binding = binding
    }

    func start() throws {
        startCallCount += 1
    }

    func stop() {
        continuation.finish()
    }

    func send(_ event: HotkeyEvent) {
        continuation.yield(event)
    }
}

private final class MockAudioRecording: AudioRecording, @unchecked Sendable {
    var buffers: [AudioBuffer] = []
    var startError: AppError?
    var startCallCount = 0
    var stopCallCount = 0

    func start() async throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stop() async -> AudioBuffer {
        stopCallCount += 1
        return buffers.isEmpty ? .milliseconds(0) : buffers.removeFirst()
    }
}

private final class MockTranscriber: Transcriber, @unchecked Sendable {
    var transcript = Transcript(text: "raw transcript", language: "en", durationMs: 300)
    var error: AppError?
    var loadedModelIds: [String] = []
    var transcribeCallCount = 0

    func load(modelId: String) async throws {
        loadedModelIds.append(modelId)
    }

    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> Transcript {
        transcribeCallCount += 1
        if let error {
            throw error
        }
        return transcript
    }
}

private final class MockTextCleaner: TextCleaner, @unchecked Sendable {
    var cleaned = "clean transcript"
    var error: AppError?
    var loadedModelIds: [String] = []
    var cleanCallCount = 0

    func load(modelId: String) async throws {
        loadedModelIds.append(modelId)
    }

    func clean(_ raw: String, timeout: TimeInterval) async throws -> String {
        cleanCallCount += 1
        if let error {
            throw error
        }
        return cleaned
    }
}

private final class MockTextInjector: TextInjecting, @unchecked Sendable {
    var pastedTexts: [String] = []
    var error: AppError?

    func paste(_ text: String) async throws {
        if let error {
            throw error
        }
        pastedTexts.append(text)
    }
}

private extension AudioBuffer {
    static func milliseconds(_ milliseconds: Int, sampleRate: Int = 16_000, channels: Int = 1) -> AudioBuffer {
        AudioBuffer(samples: Array(repeating: 0, count: sampleRate * channels * milliseconds / 1000), sampleRate: sampleRate, channels: channels)
    }
}
