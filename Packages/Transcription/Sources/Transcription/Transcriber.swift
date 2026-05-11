import Core
import ModelStore

public protocol Transcriber: Sendable {
    func load(modelId: String) async throws
    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> Transcript
}
