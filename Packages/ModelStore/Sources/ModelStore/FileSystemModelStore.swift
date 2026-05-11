import Core
import Foundation

public final class FileSystemModelStore: ModelStoring, @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let downloader: ModelDownloading
    private let catalogLoader: @Sendable () throws -> Catalog

    public convenience init(rootURL: URL? = nil) {
        self.init(
            rootURL: rootURL,
            fileManager: .default,
            downloader: URLSessionModelDownloader(),
            catalogLoader: {
                guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
                    throw ModelStoreError.catalogMissing
                }
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(Catalog.self, from: data)
            }
        )
    }

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        downloader: ModelDownloading,
        catalogLoader: @escaping @Sendable () throws -> Catalog
    ) {
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        self.fileManager = fileManager
        self.downloader = downloader
        self.catalogLoader = catalogLoader
    }

    public func availableModels(kind: ModelKind) async -> [ModelDescriptor] {
        guard let catalog = try? catalogLoader() else { return [] }

        return catalog.models
            .filter { $0.kind == kind }
            .map { entry in
                ModelDescriptor(
                    id: entry.id,
                    kind: entry.kind,
                    displayName: entry.displayName,
                    sizeBytes: entry.sizeBytes,
                    language: entry.language,
                    installed: fileManager.fileExists(atPath: directoryURL(for: entry.id).path)
                )
            }
    }

    public func download(_ id: String) -> AsyncStream<DownloadProgress> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await performDownload(id: id, continuation: continuation)
                } catch {
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func path(for id: String) async throws -> URL {
        let directory = directoryURL(for: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw AppError.modelMissing(kind: kind(for: id))
        }
        return directory
    }

    public func delete(_ id: String) async throws {
        let directory = directoryURL(for: id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}

extension FileSystemModelStore {
    static func sanitizedModelId(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "__")
    }

    static func defaultRootURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("yap", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func directoryURL(for id: String) -> URL {
        rootURL.appendingPathComponent(Self.sanitizedModelId(id), isDirectory: true)
    }
}

private extension FileSystemModelStore {
    func performDownload(id: String, continuation: AsyncStream<DownloadProgress>.Continuation) async throws {
        let catalog = try catalogLoader()
        guard let entry = catalog.models.first(where: { $0.id == id }) else {
            continuation.finish()
            return
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let destination = directoryURL(for: id)
        let temporaryDirectory = rootURL
            .appendingPathComponent(".\(Self.sanitizedModelId(id)).\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            switch entry.kind {
            case .stt:
                try await downloadSTTModel(entry, to: temporaryDirectory, continuation: continuation)
            case .llm:
                try await downloadLLMModel(entry, to: temporaryDirectory, continuation: continuation)
            }

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryDirectory, to: destination)
            continuation.yield(
                DownloadProgress(
                    modelId: id,
                    bytesDownloaded: entry.sizeBytes,
                    bytesTotal: entry.sizeBytes
                )
            )
            continuation.finish()
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    func downloadSTTModel(
        _ entry: CatalogEntry,
        to temporaryDirectory: URL,
        continuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws {
        guard let downloadURL = entry.downloadURL else {
            throw ModelStoreError.downloadURLMissing(entry.id)
        }

        let zipURL = try await downloader.download(from: downloadURL) { bytesDownloaded, bytesTotal in
            continuation.yield(
                DownloadProgress(
                    modelId: entry.id,
                    bytesDownloaded: bytesDownloaded,
                    bytesTotal: bytesTotal > 0 ? bytesTotal : entry.sizeBytes
                )
            )
        }

        try unzip(zipURL, to: temporaryDirectory)
    }

    func downloadLLMModel(
        _ entry: CatalogEntry,
        to temporaryDirectory: URL,
        continuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws {
        let apiURL = URL(string: "https://huggingface.co/api/models/\(entry.id)")!
        let (data, _) = try await downloader.data(from: apiURL)
        let repo = try JSONDecoder().decode(HuggingFaceModelResponse.self, from: data)
        let files = repo.siblings.filter { !$0.rfilename.hasSuffix("/") }
        let expectedTotal = files.reduce(0) { $0 + ($1.size ?? 0) }
        let total = expectedTotal > 0 ? expectedTotal : entry.sizeBytes
        var completedBytes = 0

        for file in files {
            try Task.checkCancellation()
            let fileURL = resolveURL(modelId: entry.id, filename: file.rfilename)
            let targetURL = temporaryDirectory.appendingPathComponent(file.rfilename)
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let baseCompletedBytes = completedBytes
            let downloadedURL = try await downloader.download(from: fileURL) { bytesDownloaded, bytesTotal in
                let denominator = expectedTotal > 0 ? total : max(total, baseCompletedBytes + max(bytesTotal, bytesDownloaded))
                continuation.yield(
                    DownloadProgress(
                        modelId: entry.id,
                        bytesDownloaded: baseCompletedBytes + bytesDownloaded,
                        bytesTotal: denominator
                    )
                )
            }

            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: downloadedURL, to: targetURL)
            completedBytes += file.size ?? fileManager.fileSize(at: targetURL)
        }
    }

    func unzip(_ zipURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zipURL.path, "-d", destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ModelStoreError.unzipFailed
        }
    }

    func kind(for id: String) -> ModelKind {
        guard let catalog = try? catalogLoader(),
              let kind = catalog.models.first(where: { $0.id == id })?.kind else {
            return .stt
        }
        return kind
    }

    func resolveURL(modelId: String, filename: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.percentEncodedPath = "/" + percentEncodedPath(modelId) + "/resolve/main/" + percentEncodedPath(filename)
        return components.url!
    }

    func percentEncodedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }
}

private extension FileManager {
    func fileSize(at url: URL) -> Int {
        guard let attributes = try? attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.intValue
    }
}

struct Catalog: Decodable, Sendable {
    let models: [CatalogEntry]
}

struct CatalogEntry: Decodable, Sendable {
    let id: String
    let kind: ModelKind
    let displayName: String
    let sizeBytes: Int
    let language: String?
    let downloadURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName
        case sizeBytes
        case language
        case downloadURL
    }

    init(
        id: String,
        kind: ModelKind,
        displayName: String,
        sizeBytes: Int,
        language: String?,
        downloadURL: URL?
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.language = language
        self.downloadURL = downloadURL
    }

    init(from decoder: Decoder) throws {
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
        self.downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
    }
}

struct HuggingFaceModelResponse: Decodable {
    let siblings: [HuggingFaceSibling]
}

struct HuggingFaceSibling: Decodable {
    let rfilename: String
    let size: Int?
}

enum ModelStoreError: Error {
    case catalogMissing
    case downloadURLMissing(String)
    case unzipFailed
}

protocol ModelDownloading: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func download(
        from url: URL,
        progress: @escaping @Sendable (_ bytesDownloaded: Int, _ bytesTotal: Int) -> Void
    ) async throws -> URL
}

final class URLSessionModelDownloader: NSObject, ModelDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [Int: DownloadState] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (_ bytesDownloaded: Int, _ bytesTotal: Int) -> Void
    ) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: url)
                lock.withLock {
                    states[task.taskIdentifier] = DownloadState(
                        continuation: continuation,
                        progress: progress
                    )
                }
                task.resume()
            }
        } onCancel: {
            session.getAllTasks { tasks in
                tasks.first { $0.originalRequest?.url == url }?.cancel()
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let state = lock.withLock { states[downloadTask.taskIdentifier] }
        state?.progress(
            Int(totalBytesWritten),
            totalBytesExpectedToWrite > 0 ? Int(totalBytesExpectedToWrite) : 0
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let state = lock.withLock { states.removeValue(forKey: downloadTask.taskIdentifier) }
        guard let state else { return }

        do {
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: temporaryURL)
            state.continuation.resume(returning: temporaryURL)
        } catch {
            state.continuation.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let state = lock.withLock { states.removeValue(forKey: task.taskIdentifier) }
        state?.continuation.resume(throwing: error)
    }
}

private struct DownloadState {
    let continuation: CheckedContinuation<URL, Error>
    let progress: @Sendable (_ bytesDownloaded: Int, _ bytesTotal: Int) -> Void
}

private extension NSLock {
    func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try work()
    }
}
