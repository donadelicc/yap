import Core
@testable import LLMCleanup
import ModelStore
import XCTest

final class LLMCleanupTests: XCTestCase {
    func testFormatPrompt() {
        let prompt = formatPrompt(transcript: "um so like, hello world")

        XCTAssertEqual(
            prompt,
            """
            System:
            You clean up speech transcripts. Rules:
            - Fix punctuation and capitalization.
            - Remove filler words: um, uh, like, you know.
            - Do NOT paraphrase. Do NOT add or remove content.
            - Output ONLY the cleaned text, no preamble.

            User:
            um so like, hello world
            """
        )
    }

    func testMissingLoadedModelThrowsModelMissing() async {
        let cleaner = MLXTextCleaner(modelStore: StubModelStore(pathResult: .success(URL(fileURLWithPath: "/tmp/model"))))

        do {
            _ = try await cleaner.clean("hello", timeout: 0.1)
            XCTFail("Expected modelMissing")
        } catch AppError.modelMissing(kind: .llm) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadMapsMissingModelToLLMKind() async {
        let cleaner = MLXTextCleaner(
            modelStore: StubModelStore(pathResult: .failure(AppError.modelMissing(kind: .stt))),
            loader: StubLoader(model: StubModel())
        )

        do {
            try await cleaner.load(modelId: "missing")
            XCTFail("Expected modelMissing")
        } catch AppError.modelMissing(kind: .llm) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTimeoutCancelsSlowGeneration() async throws {
        let model = SlowModel()
        let cleaner = MLXTextCleaner(
            modelStore: StubModelStore(pathResult: .success(URL(fileURLWithPath: "/tmp/model"))),
            loader: StubLoader(model: model)
        )
        try await cleaner.load(modelId: "slow")

        let started = Date()
        do {
            _ = try await cleaner.clean("hello world", timeout: 0.05)
            XCTFail("Expected cleanupTimedOut")
        } catch AppError.cleanupTimedOut {
            XCTAssertLessThan(Date().timeIntervalSince(started), 0.25)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let wasCancelled = await model.wasCancelled
        XCTAssertTrue(wasCancelled)
    }

    func testSlowRealModelCleanupContainsHelloWorld() async throws {
        guard let modelId = ProcessInfo.processInfo.environment["YAP_LLM_TEST_MODEL_ID"] else {
            throw XCTSkip("Set YAP_LLM_TEST_MODEL_ID to run the gated real-model LLMCleanup test.")
        }

        let rootURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["YAP_LLM_TEST_MODEL_ROOT"] ?? "")
        let cleaner = MLXTextCleaner(
            modelStore: StubModelStore(pathResult: .success(rootURL.appendingPathComponent(modelId)))
        )

        try await cleaner.load(modelId: modelId)
        let cleaned = try await cleaner.clean("um so like, hello world", timeout: 10)
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("hello world"))
    }
}

private struct StubModelStore: ModelStoring {
    let pathResult: Result<URL, Error>

    func availableModels(kind: ModelKind) async -> [ModelDescriptor] {
        []
    }

    func download(_ id: String) -> AsyncStream<DownloadProgress> {
        AsyncStream { $0.finish() }
    }

    func path(for id: String) async throws -> URL {
        try pathResult.get()
    }

    func delete(_ id: String) async throws {}
}

private struct StubLoader: TextCleaningModelLoading {
    let model: TextCleaningModel

    func loadModel(at url: URL) async throws -> TextCleaningModel {
        model
    }
}

private struct StubModel: TextCleaningModel {
    func tokenCount(for text: String) async throws -> Int {
        text.split(separator: " ").count
    }

    func generate(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> String {
        "Hello world"
    }
}

private actor SlowModel: TextCleaningModel {
    private(set) var wasCancelled = false

    func tokenCount(for text: String) async throws -> Int {
        2
    }

    func generate(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> String {
        do {
            while true {
                try await Task.sleep(for: .seconds(60))
            }
        } catch is CancellationError {
            wasCancelled = true
            throw AppError.cleanupTimedOut
        }
    }
}
