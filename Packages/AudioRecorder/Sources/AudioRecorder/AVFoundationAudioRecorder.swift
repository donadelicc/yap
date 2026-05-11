import Foundation
import AVFoundation
import Core

public final class AVFoundationAudioRecorder: AudioRecording, @unchecked Sendable {
    private let engine: AudioEngine
    private let converter: AudioBufferConverting
    private let permissionProvider: MicrophonePermissionProviding
    private let sampleQueue = DispatchQueue(label: "yap.audio-recorder.samples")
    private let stateQueue = DispatchQueue(label: "yap.audio-recorder.state")
    private var samples: [Float] = []
    private var isRecording = false

    public init() {
        self.engine = AVAudioEngineAdapter()
        self.converter = AVAudioBufferConverter()
        self.permissionProvider = AVFoundationMicrophonePermissionProvider()
    }

    init(
        engine: AudioEngine,
        converter: AudioBufferConverting = AVAudioBufferConverter(),
        permissionProvider: MicrophonePermissionProviding = AllowingMicrophonePermissionProvider()
    ) {
        self.engine = engine
        self.converter = converter
        self.permissionProvider = permissionProvider
    }

    public func start() async throws {
        if stateQueue.sync(execute: { isRecording }) {
            return
        }

        let permission = await permissionProvider.microphonePermission()
        if permission == .denied {
            throw AppError.permissionDenied(.microphone)
        }

        do {
            try engine.installInputTap { [weak self] buffer in
                guard let self else { return }
                do {
                    let convertedSamples = try self.converter.convertTo16kMonoFloat(buffer)
                    self.sampleQueue.async {
                        self.samples.append(contentsOf: convertedSamples)
                    }
                } catch {
                    // AVAudioEngine tap callbacks cannot throw; start/stop surface engine lifecycle errors.
                }
            }
            try engine.start()
            stateQueue.sync {
                isRecording = true
            }
        } catch {
            engine.removeInputTap()
            throw AppError.audioRecordingFailed(String(describing: error))
        }
    }

    public func stop() async -> Core.AudioBuffer {
        let wasRecording = stateQueue.sync {
            let current = isRecording
            isRecording = false
            return current
        }

        if wasRecording {
            engine.stop()
            engine.removeInputTap()
        }

        let recordedSamples = sampleQueue.sync {
            let current = samples
            samples.removeAll(keepingCapacity: true)
            return current
        }

        return Core.AudioBuffer(samples: recordedSamples, sampleRate: 16_000, channels: 1)
    }
}

protocol AudioBufferConverting: Sendable {
    func convertTo16kMonoFloat(_ buffer: AVAudioPCMBuffer) throws -> [Float]
}

final class AVAudioBufferConverter: AudioBufferConverting {
    func convertTo16kMonoFloat(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        try AudioConversion.convertTo16kMonoFloat(buffer)
    }
}

enum AudioConversion {
    static let outputSampleRate = 16_000
    static let outputChannels: AVAudioChannelCount = 1

    static func convertTo16kMonoFloat(_ inputBuffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(outputSampleRate),
            channels: outputChannels,
            interleaved: false
        ) else {
            throw AppError.audioRecordingFailed("Failed to create output audio format")
        }

        guard let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
            throw AppError.audioRecordingFailed("Failed to create audio converter")
        }

        return try convert(inputBuffer, outputFormat: outputFormat, converter: converter)
    }

    static func extractMonoFloatSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            throw AppError.audioRecordingFailed("Converted audio buffer has no float channel data")
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return []
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    private static func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        outputFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) throws -> [Float] {
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = max(1, AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 16)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AppError.audioRecordingFailed("Failed to allocate output audio buffer")
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw AppError.audioRecordingFailed(conversionError.localizedDescription)
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return try extractMonoFloatSamples(from: outputBuffer)
        case .error:
            throw AppError.audioRecordingFailed("Audio conversion failed")
        @unknown default:
            throw AppError.audioRecordingFailed("Audio conversion returned an unknown status")
        }
    }
}

protocol AudioEngine: AnyObject, Sendable {
    func installInputTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func removeInputTap()
    func start() throws
    func stop()
}

final class AVAudioEngineAdapter: AudioEngine, @unchecked Sendable {
    private let engine = AVAudioEngine()

    func installInputTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            handler(buffer)
        }
    }

    func removeInputTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}

enum MicrophonePermission: Sendable {
    case allowed
    case denied
}

protocol MicrophonePermissionProviding: Sendable {
    func microphonePermission() async -> MicrophonePermission
}

final class AVFoundationMicrophonePermissionProvider: MicrophonePermissionProviding {
    func microphonePermission() async -> MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .allowed
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .allowed : .denied
        @unknown default:
            return .denied
        }
    }
}

final class AllowingMicrophonePermissionProvider: MicrophonePermissionProviding {
    func microphonePermission() async -> MicrophonePermission {
        .allowed
    }
}
