import AudioRecorder
import Hotkey
import LLMCleanup
import ModelStore
import Permissions
import Settings
import TextInjector
import Transcription

@MainActor
final class Container {
    let settings: UserDefaultsSettingsService
    let permissions: SystemPermissionsService
    let modelStore: FileSystemModelStore
    let hotkey: CGEventTapHotkeyService
    let audio: AVFoundationAudioRecorder
    let transcriber: WhisperKitTranscriber
    let cleaner: MLXTextCleaner
    let injector: ClipboardTextInjector
    let coordinator: AppCoordinator

    init() {
        settings = UserDefaultsSettingsService()
        permissions = SystemPermissionsService()
        modelStore = FileSystemModelStore()
        hotkey = CGEventTapHotkeyService()
        audio = AVFoundationAudioRecorder()
        transcriber = WhisperKitTranscriber(modelStore: modelStore)
        cleaner = MLXTextCleaner(modelStore: modelStore)
        injector = ClipboardTextInjector()
        coordinator = AppCoordinator(
            settings: settings,
            permissions: permissions,
            modelStore: modelStore,
            hotkey: hotkey,
            audio: audio,
            transcriber: transcriber,
            cleaner: cleaner,
            injector: injector
        )
    }
}
