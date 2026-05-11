import Core
import SwiftUI
import AppKit

public struct MenuBarContent: View {
    private let state: RecordingState
    private let lastError: AppError?
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    public init(
        state: RecordingState,
        lastError: AppError?,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.state = state
        self.lastError = lastError
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        Text(statusText)
        Divider()
        Button("Open Settings…", action: onOpenSettings)
        Button("Quit yap", action: onQuit)
    }

    private var statusText: String {
        switch state {
        case .idle:
            "Idle"
        case .recording:
            "Recording…"
        case .transcribing, .cleaning, .pasting:
            "Processing…"
        case .error(let error):
            errorText(for: error)
        }
    }

    private func errorText(for error: AppError) -> String {
        switch error {
        case .modelMissing(let kind):
            "\(modelName(for: kind)) model missing"
        case .permissionDenied(let permission):
            "\(permissionName(for: permission)) permission denied"
        case .transcriptionFailed(let reason):
            "Transcription failed: \(reason)"
        case .cleanupTimedOut:
            "Cleanup timed out"
        case .audioRecordingFailed(let reason):
            "Recording failed: \(reason)"
        case .pasteFailed(let reason):
            "Paste failed: \(reason)"
        }
    }

    private func modelName(for kind: ModelKind) -> String {
        switch kind {
        case .stt:
            "Speech-to-text"
        case .llm:
            "Cleanup"
        }
    }

    private func permissionName(for permission: Permission) -> String {
        switch permission {
        case .microphone:
            "Microphone"
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input monitoring"
        }
    }
}
