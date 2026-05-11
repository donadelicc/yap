import SwiftUI
import Core
import Settings
import ModelStore

struct ModelsTab: View {
    @StateObject private var model: ModelsSettingsModel

    init(settings: any SettingsService, modelStore: any ModelStoring) {
        _model = StateObject(wrappedValue: ModelsSettingsModel(settings: settings, modelStore: modelStore))
    }

    var body: some View {
        Form {
            modelSection(title: "STT", models: model.sttModels)
            modelSection(title: "LLM", models: model.llmModels)
        }
        .padding(24)
        .task {
            await model.observeSettings()
        }
        .task {
            await model.refreshModels()
        }
    }

    private func modelSection(title: String, models: [ModelDescriptor]) -> some View {
        Section(title) {
            if models.isEmpty {
                Text("No models available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(models) { descriptor in
                    ModelRow(
                        descriptor: descriptor,
                        isDefault: model.isDefault(descriptor),
                        progress: model.progressById[descriptor.id],
                        onSelectDefault: {
                            model.selectDefault(descriptor)
                        },
                        onDownload: {
                            Task {
                                await model.download(descriptor)
                            }
                        },
                        onDelete: {
                            Task {
                                await model.delete(descriptor)
                            }
                        }
                    )
                }
            }
        }
    }
}

struct ModelRow: View {
    let descriptor: ModelDescriptor
    let isDefault: Bool
    let progress: DownloadProgress?
    let onSelectDefault: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(descriptor.displayName)
                        .font(.body)
                    if isDefault {
                        Text("Default")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(descriptor.sizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let progress {
                ProgressView(value: progress.fraction)
                    .frame(width: 90)
                    .accessibilityIdentifier("download-progress-\(descriptor.id)")
            }

            if descriptor.installed {
                Button("Set Default", action: onSelectDefault)
                    .disabled(isDefault)
                Button("Delete", action: onDelete)
            } else {
                Button("Download", action: onDownload)
            }
        }
        .accessibilityIdentifier("model-row-\(descriptor.id)")
    }
}

@MainActor
final class ModelsSettingsModel: ObservableObject {
    @Published private(set) var current: AppSettings
    @Published private(set) var sttModels: [ModelDescriptor] = []
    @Published private(set) var llmModels: [ModelDescriptor] = []
    @Published private(set) var progressById: [String: DownloadProgress] = [:]

    private let settings: any SettingsService
    private let modelStore: any ModelStoring

    init(settings: any SettingsService, modelStore: any ModelStoring) {
        self.settings = settings
        self.modelStore = modelStore
        self.current = settings.current
    }

    func observeSettings() async {
        for await value in settings.changes {
            current = value
        }
    }

    func refreshModels() async {
        async let stt = modelStore.availableModels(kind: .stt)
        async let llm = modelStore.availableModels(kind: .llm)
        sttModels = await stt
        llmModels = await llm
    }

    func isDefault(_ descriptor: ModelDescriptor) -> Bool {
        switch descriptor.kind {
        case .stt:
            return current.sttModelId == descriptor.id
        case .llm:
            return current.llmModelId == descriptor.id
        }
    }

    func selectDefault(_ descriptor: ModelDescriptor) {
        settings.update { settings in
            switch descriptor.kind {
            case .stt:
                settings.sttModelId = descriptor.id
            case .llm:
                settings.llmModelId = descriptor.id
            }
        }
        current = settings.current
    }

    func download(_ descriptor: ModelDescriptor) async {
        for await progress in modelStore.download(descriptor.id) {
            progressById[descriptor.id] = progress
        }
        progressById[descriptor.id] = nil
        await refreshModels()
    }

    func delete(_ descriptor: ModelDescriptor) async {
        try? await modelStore.delete(descriptor.id)
        await refreshModels()
    }

    func actionLabels(for descriptor: ModelDescriptor) -> [String] {
        descriptor.installed ? ["Set Default", "Delete"] : ["Download"]
    }
}

extension ModelDescriptor {
    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}
