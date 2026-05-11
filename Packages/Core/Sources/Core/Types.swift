import Foundation

public struct AudioBuffer: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public let channels: Int
    public var durationMs: Int { (samples.count * 1000) / (sampleRate * channels) }

    public init(samples: [Float], sampleRate: Int = 16_000, channels: Int = 1) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

public struct Transcript: Sendable {
    public let text: String
    public let language: String?
    public let durationMs: Int

    public init(text: String, language: String?, durationMs: Int) {
        self.text = text
        self.language = language
        self.durationMs = durationMs
    }
}

public enum AppError: Error, Sendable, Equatable {
    case modelMissing(kind: ModelKind)
    case permissionDenied(Permission)
    case transcriptionFailed(String)
    case cleanupTimedOut
    case audioRecordingFailed(String)
    case pasteFailed(String)
}

public enum ModelKind: String, Sendable, Codable { case stt, llm }
public enum Permission: String, Sendable, Codable { case microphone, accessibility, inputMonitoring }

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case cleaning
    case pasting
    case error(AppError)
}

public enum HotkeyBinding: String, Codable, Sendable, CaseIterable {
    case fn
    case rightOption
    case rightCommand
    case rightControl
}
