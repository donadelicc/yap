import Core
@testable import ModelStore
import XCTest

final class FileSystemModelStoreTests: XCTestCase {
    func testAvailableSTTModelsReturnsCatalogEntriesNotInstalled() async throws {
        let rootURL = try makeTemporaryDirectory()
        let store = FileSystemModelStore(rootURL: rootURL)

        let models = await store.availableModels(kind: .stt)

        XCTAssertEqual(models.map(\.id), [
            "openai_whisper-tiny.en",
            "openai_whisper-base.en",
            "openai_whisper-small.en"
        ])
        XCTAssertEqual(models.map(\.displayName), [
            "Whisper Tiny (English)",
            "Whisper Base (English)",
            "Whisper Small (English)"
        ])
        XCTAssertTrue(models.allSatisfy { !$0.installed })
    }

    func testPathThrowsModelMissingWhenDirectoryDoesNotExist() async throws {
        let rootURL = try makeTemporaryDirectory()
        let store = FileSystemModelStore(
            rootURL: rootURL,
            downloader: MockDownloader(),
            catalogLoader: { testCatalog }
        )

        do {
            _ = try await store.path(for: "openai_whisper-tiny.en")
            XCTFail("Expected path(for:) to throw")
        } catch AppError.modelMissing(let kind) {
            XCTAssertEqual(kind, .stt)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeleteRemovesModelDirectory() async throws {
        let rootURL = try makeTemporaryDirectory()
        let store = FileSystemModelStore(
            rootURL: rootURL,
            downloader: MockDownloader(),
            catalogLoader: { testCatalog }
        )
        let directory = rootURL.appendingPathComponent("openai_whisper-tiny.en", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try await store.delete("openai_whisper-tiny.en")

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDownloadEmitsMockedProgressEvents() async throws {
        let rootURL = try makeTemporaryDirectory()
        let downloader = MockDownloader()
        downloader.dataByURL[URL(string: "https://huggingface.co/api/models/mlx-community/Qwen2.5-0.5B-Instruct-4bit")!] =
            """
            {
              "siblings": [
                { "rfilename": "config.json", "size": 10 },
                { "rfilename": "weights/model.safetensors", "size": 20 }
              ]
            }
            """.data(using: .utf8)!
        downloader.progressByLastPathComponent = [
            "config.json": [(4, 10), (10, 10)],
            "model.safetensors": [(8, 20), (20, 20)]
        ]

        let store = FileSystemModelStore(
            rootURL: rootURL,
            downloader: downloader,
            catalogLoader: { testCatalog }
        )

        var events: [DownloadProgress] = []
        for await event in store.download("mlx-community/Qwen2.5-0.5B-Instruct-4bit") {
            events.append(event)
        }

        XCTAssertEqual(events.map(\.bytesDownloaded), [4, 10, 18, 30, 30])
        XCTAssertEqual(events.map(\.bytesTotal), [30, 30, 30, 30, 30])
        XCTAssertEqual(events.last?.fraction, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootURL
                    .appendingPathComponent("mlx-community__Qwen2.5-0.5B-Instruct-4bit")
                    .appendingPathComponent("weights/model.safetensors")
                    .path
            )
        )
    }

    func testIdSanitizationResolvesDirectoryForSlashedModelId() async throws {
        let rootURL = try makeTemporaryDirectory()
        let store = FileSystemModelStore(
            rootURL: rootURL,
            downloader: MockDownloader(),
            catalogLoader: { testCatalog }
        )
        let directory = rootURL.appendingPathComponent("mlx-community__Qwen2.5-0.5B-Instruct-4bit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let resolved = try await store.path(for: "mlx-community/Qwen2.5-0.5B-Instruct-4bit")

        XCTAssertEqual(resolved.lastPathComponent, "mlx-community__Qwen2.5-0.5B-Instruct-4bit")
        XCTAssertEqual(FileSystemModelStore.sanitizedModelId("mlx-community/Qwen2.5-0.5B-Instruct-4bit"), resolved.lastPathComponent)
    }
}

private let testCatalog = Catalog(models: [
    CatalogEntry(
        id: "openai_whisper-tiny.en",
        kind: .stt,
        displayName: "Whisper Tiny (English)",
        sizeBytes: 77_000_000,
        language: "en",
        downloadURL: URL(string: "https://example.com/openai_whisper-tiny.en.zip")!
    ),
    CatalogEntry(
        id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
        kind: .llm,
        displayName: "Qwen 2.5 0.5B (Q4)",
        sizeBytes: 30,
        language: nil,
        downloadURL: nil
    )
])

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class MockDownloader: ModelDownloading, @unchecked Sendable {
    var dataByURL: [URL: Data] = [:]
    var progressByLastPathComponent: [String: [(Int, Int)]] = [:]

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let data = dataByURL[url] ?? Data()
        let response = URLResponse(
            url: url,
            mimeType: "application/json",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        return (data, response)
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (_ bytesDownloaded: Int, _ bytesTotal: Int) -> Void
    ) async throws -> URL {
        for event in progressByLastPathComponent[url.lastPathComponent, default: [(1, 1)]] {
            progress(event.0, event.1)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data(url.lastPathComponent.utf8).write(to: fileURL)
        return fileURL
    }
}
