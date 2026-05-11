import AppKit
import Core
import ModelStore
import Permissions
import Settings
import SwiftUI

final class OnboardingWindowController: NSWindowController {
    init(
        settings: any SettingsService,
        permissions: any PermissionsService,
        modelStore: any ModelStoring,
        onComplete: @escaping @MainActor () -> Void
    ) {
        let view = OnboardingView(
            model: OnboardingViewModel(
                settings: settings,
                permissions: permissions,
                modelStore: modelStore,
                onComplete: onComplete
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up yap"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

struct OnboardingView: View {
    @StateObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        }
        .task {
            await model.load()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases) { step in
                Circle()
                    .fill(step.rawValue <= model.step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(step.title)
            }

            Text(model.step.title)
                .font(.headline)
                .padding(.leading, 6)

            Spacer()
        }
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            welcome
        case .microphone:
            permissionStep(
                permission: .microphone,
                title: "Microphone",
                message: "Allow microphone access so yap can record your voice while the hotkey is held.",
                buttonTitle: "Grant"
            )
        case .accessibility:
            permissionStep(
                permission: .accessibility,
                title: "Accessibility",
                message: "Allow Accessibility so yap can paste dictated text into the focused app.",
                buttonTitle: "Open System Settings"
            )
        case .inputMonitoring:
            permissionStep(
                permission: .inputMonitoring,
                title: "Input Monitoring",
                message: "Allow Input Monitoring so yap can listen for the global dictation hotkey.",
                buttonTitle: "Open System Settings"
            )
        case .models:
            models
        case .done:
            done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("yap is a local voice dictation tool. We need three permissions and one or two model downloads.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button("Continue") {
                    model.advanceFromWelcome()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func permissionStep(
        permission: Permission,
        title: String,
        message: String,
        buttonTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                statusPill(model.status(for: permission))
                Text(title)
                    .font(.body)

                Spacer()

                Button(buttonTitle) {
                    Task {
                        await model.request(permission)
                    }
                }
                .disabled(model.status(for: permission) == .granted)
            }

            Spacer()
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose the first speech-to-text and cleanup models. Downloads stay on this Mac.")
                .foregroundStyle(.secondary)

            modelPicker(
                title: "Speech-to-text",
                selection: $model.selectedSTTModelId,
                models: model.sttModels
            )

            modelPicker(
                title: "Cleanup LLM",
                selection: $model.selectedLLMModelId,
                models: model.llmModels
            )

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    private func modelPicker(
        title: String,
        selection: Binding<String>,
        models: [ModelDescriptor]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Picker(title, selection: selection) {
                ForEach(models) { descriptor in
                    Text("\(descriptor.displayName) (\(descriptor.onboardingSizeDescription))")
                        .tag(descriptor.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)
            .onChange(of: selection.wrappedValue) { _ in
                model.saveSelections()
            }

            if let descriptor = models.first(where: { $0.id == selection.wrappedValue }) {
                HStack(spacing: 12) {
                    statusPill(descriptor.installed ? .granted : .undetermined)

                    if let progress = model.progressById[descriptor.id] {
                        ProgressView(value: progress.fraction)
                            .frame(width: 180)
                    }

                    Spacer()

                    Button("Download") {
                        Task {
                            await model.download(descriptor)
                        }
                    }
                    .disabled(descriptor.installed || model.progressById[descriptor.id] != nil)
                }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("You're set. Hold right-option to dictate.")
                .font(.title3)

            Spacer()

            HStack {
                Spacer()
                Button("Start Dictating") {
                    model.complete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func statusPill(_ status: PermissionStatus) -> some View {
        Text(status.label)
            .font(.caption)
            .foregroundStyle(status == .granted ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(status == .granted ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
            )
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var statuses: [Permission: PermissionStatus] = [:]
    @Published var sttModels: [ModelDescriptor] = []
    @Published var llmModels: [ModelDescriptor] = []
    @Published var selectedSTTModelId: String
    @Published var selectedLLMModelId: String
    @Published var progressById: [String: DownloadProgress] = [:]
    @Published var errorMessage: String?

    private let settings: any SettingsService
    private let permissions: any PermissionsService
    private let modelStore: any ModelStoring
    private let onComplete: @MainActor () -> Void
    private var pollingTask: Task<Void, Never>?

    init(
        settings: any SettingsService,
        permissions: any PermissionsService,
        modelStore: any ModelStoring,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.permissions = permissions
        self.modelStore = modelStore
        self.onComplete = onComplete
        self.selectedSTTModelId = settings.current.sttModelId
        self.selectedLLMModelId = settings.current.llmModelId
    }

    deinit {
        pollingTask?.cancel()
    }

    func load() async {
        await refreshPermissions()
        await refreshModels()
        saveSelections()
        advancePastCompletedSteps()
        startPolling()
    }

    func advanceFromWelcome() {
        step = .microphone
        advancePastCompletedSteps()
    }

    func request(_ permission: Permission) async {
        statuses[permission] = await permissions.request(permission)
        advancePastCompletedSteps()
    }

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? permissions.status(for: permission)
    }

    func saveSelections() {
        settings.update { settings in
            settings.sttModelId = selectedSTTModelId
            settings.llmModelId = selectedLLMModelId
        }
    }

    func download(_ descriptor: ModelDescriptor) async {
        errorMessage = nil
        saveSelections()

        for await progress in modelStore.download(descriptor.id) {
            progressById[descriptor.id] = progress
        }

        progressById[descriptor.id] = nil
        await refreshModels()
        await advanceIfSelectedModelsInstalled()
    }

    func complete() {
        onComplete()
    }

    private func refreshPermissions() async {
        for permission in Self.requiredPermissions {
            statuses[permission] = permissions.status(for: permission)
        }
    }

    private func refreshModels() async {
        async let stt = modelStore.availableModels(kind: .stt)
        async let llm = modelStore.availableModels(kind: .llm)
        sttModels = await stt
        llmModels = await llm

        if !sttModels.contains(where: { $0.id == selectedSTTModelId }),
           let defaultSTT = sttModels.first(where: { $0.id == "openai_whisper-small.en" }) ?? sttModels.first {
            selectedSTTModelId = defaultSTT.id
        }

        if !llmModels.contains(where: { $0.id == selectedLLMModelId }),
           let defaultLLM = llmModels.first(where: { $0.id == "mlx-community/Qwen2.5-1.5B-Instruct-4bit" }) ?? llmModels.first {
            selectedLLMModelId = defaultLLM.id
        }
    }

    private func startPolling() {
        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.refreshPermissions()
                await self?.advanceIfSelectedModelsInstalled()
                self?.advancePastCompletedSteps()
            }
        }
    }

    private func advancePastCompletedSteps() {
        switch step {
        case .welcome:
            break
        case .microphone where status(for: .microphone) == .granted:
            step = .accessibility
            advancePastCompletedSteps()
        case .accessibility where status(for: .accessibility) == .granted:
            step = .inputMonitoring
            advancePastCompletedSteps()
        case .inputMonitoring where status(for: .inputMonitoring) == .granted:
            step = .models
            Task {
                await advanceIfSelectedModelsInstalled()
            }
        default:
            break
        }
    }

    private func advanceIfSelectedModelsInstalled() async {
        guard step == .models else { return }

        do {
            _ = try await modelStore.path(for: selectedSTTModelId)
            _ = try await modelStore.path(for: selectedLLMModelId)
            step = .done
        } catch AppError.modelMissing {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let requiredPermissions: [Permission] = [
        .microphone,
        .accessibility,
        .inputMonitoring
    ]
}

private extension PermissionStatus {
    var label: String {
        switch self {
        case .granted:
            "Granted"
        case .denied:
            "Not Granted"
        case .undetermined:
            "Not Asked"
        }
    }
}

private extension ModelDescriptor {
    var onboardingSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}
