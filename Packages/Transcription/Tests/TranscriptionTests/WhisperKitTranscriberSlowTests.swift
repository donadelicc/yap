// Slow smoke test:
// 1. Download a tiny English WhisperKit model locally.
// 2. Put a 16 kHz mono 1 second "hello world" WAV fixture path in
//    `YAP_SLOW_STT_FIXTURE_WAV` and the model directory in `YAP_SLOW_STT_MODEL_PATH`.
// 3. Run:
//    YAP_ENABLE_SLOW_TESTS=1 YAP_SLOW_STT_MODEL_ID=openai_whisper-tiny.en \
//    YAP_SLOW_STT_MODEL_PATH=/absolute/path/to/model \
//    YAP_SLOW_STT_FIXTURE_WAV=/absolute/path/hello-world.wav swift test
import Core
import Foundation
import ModelStore
import XCTest

@testable import Transcription

final class WhisperKitTranscriberSlowTests: XCTestCase {
    func testRealWhisperKitTinyEnglishModelTranscribesHelloWorld() async throws {
        guard ProcessInfo.processInfo.environment["YAP_ENABLE_SLOW_TESTS"] == "1" else {
            throw XCTSkip("Set YAP_ENABLE_SLOW_TESTS=1 to run the real WhisperKit smoke test.")
        }

        guard let modelId = ProcessInfo.processInfo.environment["YAP_SLOW_STT_MODEL_ID"],
              let fixturePath = ProcessInfo.processInfo.environment["YAP_SLOW_STT_FIXTURE_WAV"],
              ProcessInfo.processInfo.environment["YAP_SLOW_STT_MODEL_PATH"] != nil else {
            throw XCTSkip("Set YAP_SLOW_STT_MODEL_ID, YAP_SLOW_STT_MODEL_PATH, and YAP_SLOW_STT_FIXTURE_WAV.")
        }

        let transcriber = WhisperKitTranscriber(modelStore: EnvironmentModelStore())
        try await transcriber.load(modelId: modelId)

        let audio = try WAVFixture.loadFloat32Mono16kHz(path: fixturePath)
        let transcript = try await transcriber.transcribe(audio, language: "en")

        XCTAssertTrue(
            transcript.text.localizedCaseInsensitiveContains("hello"),
            "Expected transcript to contain 'hello', got: \(transcript.text)"
        )
    }
}

private struct EnvironmentModelStore: ModelStoring {
    func availableModels(kind: ModelKind) async -> [ModelDescriptor] { [] }

    func download(_ id: String) -> AsyncStream<DownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func path(for id: String) async throws -> URL {
        guard let modelPath = ProcessInfo.processInfo.environment["YAP_SLOW_STT_MODEL_PATH"] else {
            throw AppError.modelMissing(kind: .stt)
        }

        return URL(fileURLWithPath: modelPath)
    }

    func delete(_ id: String) async throws {}
}

private enum WAVFixture {
    static func loadFloat32Mono16kHz(path: String) throws -> AudioBuffer {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let parser = WAVParser(data: data)
        return try parser.audioBuffer()
    }
}

private struct WAVParser {
    let data: Data

    func audioBuffer() throws -> AudioBuffer {
        guard string(at: 0, count: 4) == "RIFF", string(at: 8, count: 4) == "WAVE" else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var offset = 12
        var format: WAVFormat?
        var sampleData: Data?

        while offset + 8 <= data.count {
            let chunkId = string(at: offset, count: 4)
            let chunkSize = Int(try uint32(at: offset + 4))
            let chunkStart = offset + 8
            let nextOffset = chunkStart + chunkSize + (chunkSize % 2)

            guard chunkStart + chunkSize <= data.count else {
                throw CocoaError(.fileReadCorruptFile)
            }

            if chunkId == "fmt " {
                format = try readFormat(at: chunkStart, size: chunkSize)
            } else if chunkId == "data" {
                sampleData = data.subdata(in: chunkStart..<(chunkStart + chunkSize))
            }

            offset = nextOffset
        }

        guard let format, let sampleData else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard format.sampleRate == 16_000, format.channels == 1 else {
            throw AppError.transcriptionFailed("invalid format")
        }

        return AudioBuffer(
            samples: try samples(from: sampleData, format: format),
            sampleRate: Int(format.sampleRate),
            channels: Int(format.channels)
        )
    }

    private func readFormat(at offset: Int, size: Int) throws -> WAVFormat {
        guard size >= 16 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return WAVFormat(
            audioFormat: try uint16(at: offset),
            channels: try uint16(at: offset + 2),
            sampleRate: try uint32(at: offset + 4),
            bitsPerSample: try uint16(at: offset + 14)
        )
    }

    private func samples(from data: Data, format: WAVFormat) throws -> [Float] {
        switch (format.audioFormat, format.bitsPerSample) {
        case (1, 16):
            return stride(from: 0, to: data.count, by: 2).map { index in
                Float(Int16(bitPattern: data.uint16LittleEndian(at: index))) / Float(Int16.max)
            }
        case (3, 32):
            return stride(from: 0, to: data.count, by: 4).map { index in
                data.float32LittleEndian(at: index)
            }
        default:
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    private func string(at offset: Int, count: Int) -> String? {
        guard offset + count <= data.count else { return nil }
        return String(data: data.subdata(in: offset..<(offset + count)), encoding: .ascii)
    }

    private func uint16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
        return data.uint16LittleEndian(at: offset)
    }

    private func uint32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
        return data.uint32LittleEndian(at: offset)
    }
}

private struct WAVFormat {
    let audioFormat: UInt16
    let channels: UInt16
    let sampleRate: UInt32
    let bitsPerSample: UInt16
}

private extension Data {
    func uint16LittleEndian(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LittleEndian(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func float32LittleEndian(at offset: Int) -> Float {
        Float(bitPattern: uint32LittleEndian(at: offset))
    }
}
