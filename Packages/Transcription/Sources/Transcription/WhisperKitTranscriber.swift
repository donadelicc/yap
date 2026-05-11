import Core
import Foundation
import ModelStore
@preconcurrency import WhisperKit

public final class WhisperKitTranscriber: Transcriber {
    private let modelStore: any ModelStoring
    private let session: WhisperKitSession

    public init(modelStore: ModelStoring) {
        self.modelStore = modelStore
        self.session = WhisperKitSession(factory: WhisperKitEngineFactory())
    }

    init(modelStore: any ModelStoring, factory: any WhisperKitEngineCreating) {
        self.modelStore = modelStore
        self.session = WhisperKitSession(factory: factory)
    }

    public func load(modelId: String) async throws {
        let modelURL = try await modelStore.path(for: modelId)
        try await session.load(modelFolder: modelURL.path)
    }

    public func transcribe(_ audio: AudioBuffer, language: String?) async throws -> Transcript {
        guard audio.sampleRate == 16_000, audio.channels == 1 else {
            throw AppError.transcriptionFailed("invalid format")
        }

        do {
            let result = try await session.transcribe(samples: audio.samples, language: language)
            return Transcript(text: result.text, language: result.language, durationMs: audio.durationMs)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.transcriptionFailed(error.localizedDescription)
        }
    }
}

private actor WhisperKitSession {
    private let factory: any WhisperKitEngineCreating
    private var engine: (any WhisperKitEngining)?

    init(factory: any WhisperKitEngineCreating) {
        self.factory = factory
    }

    func load(modelFolder: String) async throws {
        engine = try await factory.makeEngine(modelFolder: modelFolder)
    }

    func transcribe(samples: [Float], language: String?) async throws -> WhisperKitTranscriptResult {
        guard let engine else {
            throw AppError.transcriptionFailed("model not loaded")
        }

        return try await engine.transcribe(samples: samples, language: language)
    }
}

struct WhisperKitTranscriptResult: Sendable, Equatable {
    let text: String
    let language: String?
}

protocol WhisperKitEngining: Sendable {
    func transcribe(samples: [Float], language: String?) async throws -> WhisperKitTranscriptResult
}

protocol WhisperKitEngineCreating: Sendable {
    func makeEngine(modelFolder: String) async throws -> any WhisperKitEngining
}

private struct WhisperKitEngineFactory: WhisperKitEngineCreating {
    func makeEngine(modelFolder: String) async throws -> any WhisperKitEngining {
        let whisperKit = try await WhisperKit(
            modelFolder: modelFolder,
            verbose: false,
            load: true,
            download: false
        )
        return WhisperKitEngine(whisperKit: whisperKit)
    }
}

private struct WhisperKitEngine: WhisperKitEngining {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    func transcribe(samples: [Float], language: String?) async throws -> WhisperKitTranscriptResult {
        let options = DecodingOptions(language: language)
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = results.first?.language ?? language
        return WhisperKitTranscriptResult(text: text, language: detectedLanguage)
    }
}
