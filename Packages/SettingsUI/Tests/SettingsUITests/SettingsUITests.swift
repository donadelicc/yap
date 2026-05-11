import XCTest
import SwiftUI
import Core
import Settings
import Permissions
import ModelStore
@testable import SettingsUI

final class SettingsUITests: XCTestCase {
    func testGeneralTabInstantiates() {
        _ = GeneralTab(settings: MockSettingsService())
    }

    func testHotkeyTabInstantiates() {
        _ = HotkeyTab(settings: MockSettingsService(), permissions: MockPermissionsService())
    }

    func testModelsTabInstantiates() {
        _ = ModelsTab(settings: MockSettingsService(), modelStore: MockModelStore())
    }

    func testPermissionsTabInstantiates() {
        _ = PermissionsTab(permissions: MockPermissionsService())
    }

    func testAboutTabInstantiates() {
        _ = AboutTab(bundle: .main)
    }

    @MainActor
    func testModelButtonsForInstalledAndMissingSTTModels() async {
        let settings = MockSettingsService()
        let modelStore = MockModelStore()
        let model = ModelsSettingsModel(settings: settings, modelStore: modelStore)

        await model.refreshModels()

        XCTAssertEqual(model.sttModels.count, 2)
        XCTAssertEqual(model.actionLabels(for: model.sttModels[0]), ["Set Default", "Delete"])
        XCTAssertEqual(model.actionLabels(for: model.sttModels[1]), ["Download"])
    }
}

final class MockSettingsService: SettingsService, @unchecked Sendable {
    private(set) var current = AppSettings()

    var changes: AsyncStream<AppSettings> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func update(_ change: (inout AppSettings) -> Void) {
        change(&current)
    }
}

final class MockPermissionsService: PermissionsService, @unchecked Sendable {
    var changes: AsyncStream<(Permission, PermissionStatus)> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func status(for permission: Permission) -> PermissionStatus {
        .granted
    }

    func request(_ permission: Permission) async -> PermissionStatus {
        .granted
    }
}

final class MockModelStore: ModelStoring, @unchecked Sendable {
    private let installedSTT = ModelDescriptor(
        id: "installed-stt",
        kind: .stt,
        displayName: "Installed STT",
        sizeBytes: 1024,
        language: "en",
        installed: true
    )

    private let missingSTT = ModelDescriptor(
        id: "missing-stt",
        kind: .stt,
        displayName: "Missing STT",
        sizeBytes: 2048,
        language: "en",
        installed: false
    )

    func availableModels(kind: ModelKind) async -> [ModelDescriptor] {
        switch kind {
        case .stt:
            return [installedSTT, missingSTT]
        case .llm:
            return []
        }
    }

    func download(_ id: String) -> AsyncStream<DownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(
                DownloadProgress(
                    modelId: id,
                    bytesDownloaded: 1,
                    bytesTotal: 1
                )
            )
            continuation.finish()
        }
    }

    func path(for id: String) async throws -> URL {
        URL(fileURLWithPath: "/tmp/\(id)")
    }

    func delete(_ id: String) async throws {}
}
