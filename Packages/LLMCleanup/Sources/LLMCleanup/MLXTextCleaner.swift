import Core
import Foundation
import MLXLLM
import MLXLMCommon
import ModelStore

public final class MLXTextCleaner: TextCleaner {
    private let modelStore: ModelStoring
    private let loader: TextCleaningModelLoading
    private let state = TextCleanerState()

    public init(modelStore: ModelStoring) {
        self.modelStore = modelStore
        self.loader = MLXTextCleaningModelLoader()
    }

    init(modelStore: ModelStoring, loader: TextCleaningModelLoading) {
        self.modelStore = modelStore
        self.loader = loader
    }

    public func load(modelId: String) async throws {
        do {
            let modelURL = try await modelStore.path(for: modelId)
            let model = try await loader.loadModel(at: modelURL)
            await state.setModel(model)
        } catch AppError.modelMissing {
            throw AppError.modelMissing(kind: .llm)
        }
    }

    public func clean(_ raw: String, timeout: TimeInterval) async throws -> String {
        guard let model = await state.model else {
            throw AppError.modelMissing(kind: .llm)
        }

        let tokenCount = try await model.tokenCount(for: raw)
        let maxTokens = max(64, tokenCount * 2)
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await model.generate(
                    system: cleanupSystemInstructions,
                    user: raw,
                    maxTokens: maxTokens,
                    temperature: 0.1
                )
            }

            group.addTask {
                try await Task.sleep(for: .seconds(max(0, timeout)))
                throw AppError.cleanupTimedOut
            }

            do {
                guard let first = try await group.next() else {
                    throw AppError.cleanupTimedOut
                }
                group.cancelAll()
                return stripLeakedSpecialTokens(from: first)
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}

private actor TextCleanerState {
    var model: TextCleaningModel?

    func setModel(_ model: TextCleaningModel) {
        self.model = model
    }
}

protocol TextCleaningModelLoading: Sendable {
    func loadModel(at url: URL) async throws -> TextCleaningModel
}

protocol TextCleaningModel: Sendable {
    func tokenCount(for text: String) async throws -> Int
    func generate(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> String
}

struct MLXTextCleaningModelLoader: TextCleaningModelLoading {
    func loadModel(at url: URL) async throws -> TextCleaningModel {
        let container = try await loadModelContainer(directory: url)
        return MLXTextCleaningModel(container: container)
    }
}

actor MLXTextCleaningModel: TextCleaningModel {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func tokenCount(for text: String) async throws -> Int {
        await container.perform { context in
            context.tokenizer.encode(text: text).count
        }
    }

    func generate(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> String {
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: temperature)
        let session = ChatSession(container, instructions: system, generateParameters: parameters)
        return try await session.respond(to: user)
    }
}
