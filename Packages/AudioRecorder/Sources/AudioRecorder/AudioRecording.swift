import Core

public protocol AudioRecording: Sendable {
    func start() async throws
    func stop() async -> AudioBuffer
}
