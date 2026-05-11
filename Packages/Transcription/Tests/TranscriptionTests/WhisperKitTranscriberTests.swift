import Core
import Foundation
import ModelStore
@testable import Transcription
import XCTest

final class WhisperKitTranscriberTests: XCTestCase {
    func testTranscribeRejectsNon16kHzAudio() async throws {
        let transcriber = WhisperKitTranscriber(
            modelStore: MockModelStore(pathResult: .success(URL(fileURLWithPath: "/tmp/model"))),
            factory: MockEngineFactory()
        )
        try await transcriber.load(modelId: "tiny")

        let audio = AudioBuffer(samples: [0.0, 0.1], sampleRate: 44_100, channels: 1)

        do {
            _ = try await transcriber.transcribe(audio, language: nil)
            XCTFail("Expected invalid format error")
        } catch AppError.transcriptionFailed(let message) {
            XCTAssertEqual(message, "invalid format")
        } catch {
            XCTFail("Expected transcriptionFailed(\"invalid format\"), got \(error)")
        }
    }

    func testLoadPropagatesModelMissing() async throws {
        let transcriber = WhisperKitTranscriber(
            modelStore: MockModelStore(pathResult: .failure(AppError.modelMissing(kind: .stt))),
            factory: MockEngineFactory()
        )

        do {
            try await transcriber.load(modelId: "missing")
            XCTFail("Expected model missing error")
        } catch AppError.modelMissing(let kind) {
            XCTAssertEqual(kind, .stt)
        } catch {
            XCTFail("Expected modelMissing(kind: .stt), got \(error)")
        }
    }
}

private struct MockModelStore: ModelStoring {
    let pathResult: Result<URL, Error>

    func availableModels(kind: ModelKind) async -> [ModelDescriptor] { [] }

    func download(_ id: String) -> AsyncStream<DownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func path(for id: String) async throws -> URL {
        try pathResult.get()
    }

    func delete(_ id: String) async throws {}
}

private struct MockEngineFactory: WhisperKitEngineCreating {
    func makeEngine(modelFolder: String) async throws -> any WhisperKitEngining {
        MockEngine()
    }
}

private struct MockEngine: WhisperKitEngining {
    func transcribe(samples: [Float], language: String?) async throws -> WhisperKitTranscriptResult {
        WhisperKitTranscriptResult(text: "hello world", language: language)
    }
}
