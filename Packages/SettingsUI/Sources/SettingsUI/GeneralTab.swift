import SwiftUI
import Core
import Settings

struct GeneralTab: View {
    @StateObject private var model: GeneralSettingsModel

    init(settings: any SettingsService) {
        _model = StateObject(wrappedValue: GeneralSettingsModel(settings: settings))
    }

    var body: some View {
        Form {
            Toggle("Sound effects", isOn: model.soundEffectsBinding)
            Toggle("LLM cleanup", isOn: model.llmEnabledBinding)

            Section("Recording length") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Minimum: \(model.minRecordingMs) ms")
                    Slider(value: model.minRecordingBinding, in: 0...5_000, step: 50)
                        .accessibilityIdentifier("minimum-recording-slider")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Maximum: \(model.maxRecordingSeconds) s")
                    Slider(value: model.maxRecordingBinding, in: 5_000...120_000, step: 1_000)
                        .accessibilityIdentifier("maximum-recording-slider")
                }
            }
        }
        .padding(24)
        .task {
            await model.observeChanges()
        }
    }
}

@MainActor
private final class GeneralSettingsModel: ObservableObject {
    @Published private(set) var current: AppSettings
    private let settings: any SettingsService

    init(settings: any SettingsService) {
        self.settings = settings
        self.current = settings.current
    }

    var minRecordingMs: Int { current.minRecordingMs }
    var maxRecordingSeconds: Int { current.maxRecordingMs / 1_000 }

    var soundEffectsBinding: Binding<Bool> {
        Binding(
            get: { self.current.soundEffectsEnabled },
            set: { value in
                self.update { $0.soundEffectsEnabled = value }
            }
        )
    }

    var llmEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.current.llmEnabled },
            set: { value in
                self.update { $0.llmEnabled = value }
            }
        )
    }

    var minRecordingBinding: Binding<Double> {
        Binding(
            get: { Double(self.current.minRecordingMs) },
            set: { value in
                self.update {
                    $0.minRecordingMs = min(Int(value), max(0, $0.maxRecordingMs))
                }
            }
        )
    }

    var maxRecordingBinding: Binding<Double> {
        Binding(
            get: { Double(self.current.maxRecordingMs) },
            set: { value in
                self.update {
                    $0.maxRecordingMs = max(Int(value), $0.minRecordingMs)
                }
            }
        )
    }

    func observeChanges() async {
        for await value in settings.changes {
            current = value
        }
    }

    private func update(_ change: @escaping (inout AppSettings) -> Void) {
        settings.update(change)
        current = settings.current
    }
}
