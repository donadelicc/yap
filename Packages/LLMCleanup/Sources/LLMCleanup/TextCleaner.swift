import Core
import Foundation
import ModelStore

public protocol TextCleaner: Sendable {
    func load(modelId: String) async throws
    func clean(_ raw: String, timeout: TimeInterval) async throws -> String
}
