import AppKit
import AudioRecorder
import Combine
import Core
import Hotkey
import LLMCleanup
import ModelStore
import Permissions
import Settings
import TextInjector
import Transcription

@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var lastError: AppError?

    private let settings: any SettingsService
    private let permissions: any PermissionsService
    private let modelStore: any ModelStoring
    private let hotkey: any HotkeyService
    private let audio: any AudioRecording
    private let transcriber: any Transcriber
    private let cleaner: any TextCleaner
    private let injector: any TextInjecting
    private let errorRecoveryDelayNanoseconds: UInt64

    private var eventsTask: Task<Void, Never>?
    private var maxRecordingTask: Task<Void, Never>?
    private var errorRecoveryTask: Task<Void, Never>?
    private var loadedSTTModelId: String?
    private var loadedLLMModelId: String?

    public init(
        settings: any SettingsService,
        permissions: any PermissionsService,
        modelStore: any ModelStoring,
        hotkey: any HotkeyService,
        audio: any AudioRecording,
        transcriber: any Transcriber,
        cleaner: any TextCleaner,
        injector: any TextInjecting
    ) {
        self.settings = settings
        self.permissions = permissions
        self.modelStore = modelStore
        self.hotkey = hotkey
        self.audio = audio
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.errorRecoveryDelayNanoseconds = 4_000_000_000
    }

    init(
        settings: any SettingsService,
        permissions: any PermissionsService,
        modelStore: any ModelStoring,
        hotkey: any HotkeyService,
        audio: any AudioRecording,
        transcriber: any Transcriber,
        cleaner: any TextCleaner,
        injector: any TextInjecting,
        errorRecoveryDelayNanoseconds: UInt64
    ) {
        self.settings = settings
        self.permissions = permissions
        self.modelStore = modelStore
        self.hotkey = hotkey
        self.audio = audio
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.errorRecoveryDelayNanoseconds = errorRecoveryDelayNanoseconds
    }

    deinit {
        eventsTask?.cancel()
        maxRecordingTask?.cancel()
        errorRecoveryTask?.cancel()
        hotkey.stop()
    }

    public func start() async throws {
        do {
            let currentSettings = settings.current
            try hotkey.setBinding(currentSettings.hotkeyBinding)
            try hotkey.start()
            subscribeToHotkeyEventsIfNeeded()
            try await loadModelsIfNeeded(currentSettings)
        } catch {
            let appError = asAppError(error)
            enterError(appError)
            throw appError
        }
    }

    private func subscribeToHotkeyEventsIfNeeded() {
        guard eventsTask == nil else { return }

        let events = hotkey.events
        eventsTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    private func loadModelsIfNeeded(_ currentSettings: AppSettings) async throws {
        if loadedSTTModelId != currentSettings.sttModelId {
            _ = try await modelStore.path(for: currentSettings.sttModelId)
            try await transcriber.load(modelId: currentSettings.sttModelId)
            loadedSTTModelId = currentSettings.sttModelId
        }

        guard currentSettings.llmEnabled else { return }

        if loadedLLMModelId != currentSettings.llmModelId {
            _ = try await modelStore.path(for: currentSettings.llmModelId)
            try await cleaner.load(modelId: currentSettings.llmModelId)
            loadedLLMModelId = currentSettings.llmModelId
        }
    }

    private func handle(_ event: HotkeyEvent) async {
        switch event {
        case .pressed:
            await handlePressed()
        case .released:
            await handleReleased()
        }
    }

    private func handlePressed() async {
        guard state == .idle else {
            if settings.current.soundEffectsEnabled {
                NSSound.beep()
            }
            return
        }

        state = .recording
        scheduleMaxRecordingTimer(milliseconds: settings.current.maxRecordingMs)

        do {
            try await audio.start()
        } catch {
            cancelMaxRecordingTimer()
            enterError(asAppError(error))
        }
    }

    private func handleReleased() async {
        guard state == .recording else { return }

        cancelMaxRecordingTimer()
        let currentSettings = settings.current
        let buffer = await audio.stop()

        guard buffer.durationMs >= currentSettings.minRecordingMs else {
            state = .idle
            return
        }

        do {
            state = .transcribing
            let transcript = try await transcriber.transcribe(buffer, language: currentSettings.language)
            guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                return
            }

            state = .cleaning
            let cleaned: String
            if currentSettings.llmEnabled {
                cleaned = (try? await cleaner.clean(transcript.text, timeout: 3.0)) ?? transcript.text
            } else {
                cleaned = transcript.text
            }

            state = .pasting
            try await injector.paste(cleaned)
            state = .idle
        } catch {
            enterError(asAppError(error))
        }
    }

    private func scheduleMaxRecordingTimer(milliseconds: Int) {
        cancelMaxRecordingTimer()
        guard milliseconds > 0 else { return }

        let nanoseconds = UInt64(milliseconds) * 1_000_000
        maxRecordingTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            await self?.handleReleased()
        }
    }

    private func cancelMaxRecordingTimer() {
        maxRecordingTask?.cancel()
        maxRecordingTask = nil
    }

    private func enterError(_ error: AppError) {
        cancelMaxRecordingTimer()
        state = .error(error)
        lastError = error
        scheduleErrorRecovery(for: error)
    }

    private func scheduleErrorRecovery(for error: AppError) {
        errorRecoveryTask?.cancel()
        let delay = errorRecoveryDelayNanoseconds
        errorRecoveryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            await MainActor.run {
                guard let self, self.state == .error(error) else { return }
                self.state = .idle
            }
        }
    }

    private func asAppError(_ error: any Error) -> AppError {
        error as? AppError ?? .transcriptionFailed("\(error)")
    }
}
