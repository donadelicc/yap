import AppKit
import AudioRecorder
import Core
import Hotkey
import MenuBarUI
import ModelStore
import Permissions
import Settings
import SettingsUI
import SwiftUI
import TextInjector
import Transcription

@main
struct yapApp: App {
    private let settings: UserDefaultsSettingsService
    private let permissions: SystemPermissionsService
    private let modelStore: FileSystemModelStore

    @StateObject private var coordinator: AppCoordinator

    init() {
        let settings = UserDefaultsSettingsService()
        let permissions = SystemPermissionsService()
        let modelStore = FileSystemModelStore()
        let coordinator = AppCoordinator(
            settings: settings,
            permissions: permissions,
            modelStore: modelStore,
            hotkey: CGEventTapHotkeyService(),
            audioRecorder: AVFoundationAudioRecorder(),
            transcriber: WhisperKitTranscriber(modelStore: modelStore),
            injector: ClipboardTextInjector()
        )

        self.settings = settings
        self.permissions = permissions
        self.modelStore = modelStore
        _coordinator = StateObject(wrappedValue: coordinator)

        Task {
            await coordinator.start()
        }
    }

    var body: some Scene {
        MenuBarExtra("yap", systemImage: "mic") {
            MenuBarContent(
                state: coordinator.state,
                lastError: coordinator.lastError,
                onOpenSettings: {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )

            Divider()

            Button("Set Up yap…") {
                coordinator.showOnboarding()
            }

            Button("Quit yap") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        SettingsScene(
            settings: settings,
            permissions: permissions,
            modelStore: modelStore
        )
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var lastError: AppError?

    private let settings: any SettingsService
    private let permissions: any PermissionsService
    private let modelStore: any ModelStoring
    private let hotkey: any HotkeyService
    private let audioRecorder: any AudioRecording
    private let transcriber: any Transcriber
    private let injector: any TextInjecting

    private var hotkeyTask: Task<Void, Never>?
    private var maxRecordingTask: Task<Void, Never>?
    private var onboardingWindowController: OnboardingWindowController?
    private var hotkeyListenerStarted = false

    init(
        settings: any SettingsService,
        permissions: any PermissionsService,
        modelStore: any ModelStoring,
        hotkey: any HotkeyService,
        audioRecorder: any AudioRecording,
        transcriber: any Transcriber,
        injector: any TextInjecting
    ) {
        self.settings = settings
        self.permissions = permissions
        self.modelStore = modelStore
        self.hotkey = hotkey
        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.injector = injector
    }

    func start() async {
        if await needsOnboarding() {
            showOnboarding()
        } else {
            await startHotkeyListener()
        }
    }

    func showOnboarding() {
        if let window = onboardingWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let controller = OnboardingWindowController(
            settings: settings,
            permissions: permissions,
            modelStore: modelStore,
            onComplete: { [weak self] in
                guard let self else { return }
                self.onboardingWindowController?.close()
                self.onboardingWindowController = nil
                Task {
                    await self.startHotkeyListener()
                }
            }
        )

        onboardingWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    private func needsOnboarding() async -> Bool {
        for permission in requiredPermissions where permissions.status(for: permission) != .granted {
            return true
        }

        let current = settings.current
        if await modelIsMissing(current.sttModelId) {
            return true
        }

        return await modelIsMissing(current.llmModelId)
    }

    private func modelIsMissing(_ id: String) async -> Bool {
        do {
            _ = try await modelStore.path(for: id)
            return false
        } catch AppError.modelMissing {
            return true
        } catch {
            return false
        }
    }

    private func startHotkeyListener() async {
        guard !hotkeyListenerStarted else { return }

        do {
            let current = settings.current
            try await loadModels(current)
            try hotkey.setBinding(current.hotkeyBinding)
            try hotkey.start()
            hotkeyListenerStarted = true
            observeHotkeyEvents()
            state = .idle
            lastError = nil
        } catch AppError.modelMissing {
            showOnboarding()
        } catch let error as AppError {
            setError(error)
        } catch {
            setError(.pasteFailed(error.localizedDescription))
        }
    }

    private func loadModels(_ current: AppSettings) async throws {
        try await transcriber.load(modelId: current.sttModelId)
    }

    private func observeHotkeyEvents() {
        hotkeyTask?.cancel()
        hotkeyTask = Task { [weak self] in
            guard let self else { return }

            for await event in hotkey.events {
                switch event {
                case .pressed:
                    await self.beginRecording()
                case .released:
                    await self.finishRecording()
                }
            }
        }
    }

    private func beginRecording() async {
        guard state == .idle else { return }

        do {
            try await audioRecorder.start()
            state = .recording
            lastError = nil
            scheduleMaxRecordingStop(milliseconds: settings.current.maxRecordingMs)
        } catch let error as AppError {
            setError(error)
        } catch {
            setError(.audioRecordingFailed(error.localizedDescription))
        }
    }

    private func finishRecording() async {
        guard state == .recording else { return }

        maxRecordingTask?.cancel()
        maxRecordingTask = nil
        state = .transcribing

        let audio = await audioRecorder.stop()
        let current = settings.current

        guard audio.durationMs >= current.minRecordingMs else {
            state = .idle
            return
        }

        do {
            let transcript = try await transcriber.transcribe(audio, language: current.language)
            let rawText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !rawText.isEmpty else {
                state = .idle
                return
            }

            state = .pasting
            try await injector.paste(rawText)
            state = .idle
        } catch let error as AppError {
            setError(error)
        } catch {
            setError(.transcriptionFailed(error.localizedDescription))
        }
    }

    private func scheduleMaxRecordingStop(milliseconds: Int) {
        maxRecordingTask?.cancel()
        maxRecordingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(max(0, milliseconds)))
            await self?.finishRecording()
        }
    }

    private func setError(_ error: AppError) {
        state = .error(error)
        lastError = error

        switch error {
        case .modelMissing, .permissionDenied:
            showOnboarding()
        default:
            break
        }
    }

    private let requiredPermissions: [Permission] = [
        .microphone,
        .accessibility,
        .inputMonitoring
    ]
}
