import Core
import Foundation

public struct ModelDescriptor: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let kind: ModelKind
    public let displayName: String
    public let sizeBytes: Int
    public let language: String?
    public var installed: Bool

    public init(
        id: String,
        kind: ModelKind,
        displayName: String,
        sizeBytes: Int,
        language: String?,
        installed: Bool
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.language = language
        self.installed = installed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName
        case sizeBytes
        case language
        case installed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindRawValue = try container.decode(String.self, forKey: .kind)
        guard let kind = ModelKind(rawValue: kindRawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown model kind: \(kindRawValue)"
            )
        }

        self.id = try container.decode(String.self, forKey: .id)
        self.kind = kind
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.sizeBytes = try container.decode(Int.self, forKey: .sizeBytes)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encode(installed, forKey: .installed)
    }
}

public struct DownloadProgress: Sendable {
    public let modelId: String
    public let bytesDownloaded: Int
    public let bytesTotal: Int
    public var fraction: Double { bytesTotal == 0 ? 0 : Double(bytesDownloaded) / Double(bytesTotal) }

    public init(modelId: String, bytesDownloaded: Int, bytesTotal: Int) {
        self.modelId = modelId
        self.bytesDownloaded = bytesDownloaded
        self.bytesTotal = bytesTotal
    }
}

public protocol ModelStoring: Sendable {
    func availableModels(kind: ModelKind) async -> [ModelDescriptor]
    func download(_ id: String) -> AsyncStream<DownloadProgress>
    func path(for id: String) async throws -> URL
    func delete(_ id: String) async throws
}
