import XCTest
import AVFoundation
import Core
@testable import AudioRecorder

final class AudioRecorderTests: XCTestCase {
    func testStopWithoutStartReturnsEmpty16kMonoBuffer() async {
        let recorder = AVFoundationAudioRecorder(engine: MockAudioEngine())

        let buffer = await recorder.stop()

        XCTAssertEqual(buffer.samples, [])
        XCTAssertEqual(buffer.sampleRate, 16_000)
        XCTAssertEqual(buffer.channels, 1)
    }

    func testStartWhileAlreadyStartedIsNoOp() async throws {
        let engine = MockAudioEngine()
        let recorder = AVFoundationAudioRecorder(engine: engine)

        try await recorder.start()
        try await recorder.start()

        XCTAssertEqual(engine.installInputTapCallCount, 1)
        XCTAssertEqual(engine.startCallCount, 1)
    }

    func testConversionExtracts16kMonoFloatOutputSamples() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        input.frameLength = 3
        input.floatChannelData?[0][0] = 0.25
        input.floatChannelData?[0][1] = -0.5
        input.floatChannelData?[0][2] = 1.0

        let samples = try AudioConversion.convertTo16kMonoFloat(input)

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(samples[1], -0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 1.0, accuracy: 0.0001)
    }

    func testRecorderAccumulatesMocked16kMonoFloatConverterOutput() async throws {
        let engine = MockAudioEngine()
        let converter = MockAudioBufferConverter(output: [0.125, -0.25, 0.5])
        let recorder = AVFoundationAudioRecorder(engine: engine, converter: converter)
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 8))
        input.frameLength = 8

        try await recorder.start()
        engine.emit(input)
        let buffer = await recorder.stop()

        XCTAssertEqual(converter.receivedSampleRate, 48_000)
        XCTAssertEqual(converter.receivedChannels, 2)
        XCTAssertEqual(buffer.samples, [0.125, -0.25, 0.5])
        XCTAssertEqual(buffer.sampleRate, 16_000)
        XCTAssertEqual(buffer.channels, 1)
    }

    func testSlowRealEngineRecordsAbout100msOfAudio() async throws {
        try XCTSkipUnless(Self.slowTestsEnabled, "Pass --enable-slow-tests or set ENABLE_SLOW_TESTS=1 to run")

        let recorder = AVFoundationAudioRecorder()
        try await recorder.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        let buffer = await recorder.stop()

        XCTAssertEqual(buffer.sampleRate, 16_000)
        XCTAssertEqual(buffer.channels, 1)
        XCTAssertEqual(buffer.samples.count, 1_600, accuracy: 200)
    }

    private static var slowTestsEnabled: Bool {
        CommandLine.arguments.contains("--enable-slow-tests")
            || ProcessInfo.processInfo.environment["ENABLE_SLOW_TESTS"] == "1"
    }
}

private final class MockAudioEngine: AudioEngine, @unchecked Sendable {
    private(set) var installInputTapCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var removeInputTapCallCount = 0
    private var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func installInputTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        installInputTapCallCount += 1
        self.handler = handler
    }

    func removeInputTap() {
        removeInputTapCallCount += 1
    }

    func start() throws {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func emit(_ buffer: AVAudioPCMBuffer) {
        handler?(buffer)
    }
}

private final class MockAudioBufferConverter: AudioBufferConverting, @unchecked Sendable {
    private let output: [Float]
    private(set) var receivedSampleRate: Double?
    private(set) var receivedChannels: AVAudioChannelCount?

    init(output: [Float]) {
        self.output = output
    }

    func convertTo16kMonoFloat(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        receivedSampleRate = buffer.format.sampleRate
        receivedChannels = buffer.format.channelCount
        return output
    }
}
