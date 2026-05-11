import Core

public struct AppSettings: Codable, Equatable, Sendable {
    public var hotkeyBinding: HotkeyBinding = .rightOption
    public var sttModelId: String = "openai_whisper-small.en"
    public var llmModelId: String = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    public var llmEnabled: Bool = true
    public var language: String? = "en"
    public var soundEffectsEnabled: Bool = false
    public var minRecordingMs: Int = 200
    public var maxRecordingMs: Int = 60_000

    public init() {}
}
