import SwiftUI
import Core
import Settings
import Permissions

struct HotkeyTab: View {
    @StateObject private var model: HotkeySettingsModel

    init(settings: any SettingsService, permissions: any PermissionsService) {
        _model = StateObject(wrappedValue: HotkeySettingsModel(settings: settings, permissions: permissions))
    }

    var body: some View {
        Form {
            Picker("Hotkey", selection: model.hotkeyBinding) {
                ForEach(HotkeyBinding.allCases, id: \.self) { binding in
                    Text(binding.displayName).tag(binding)
                }
            }
            .pickerStyle(.segmented)

            Text("fn capture available: \(model.fnCaptureAvailable ? "yes" : "no")")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .task {
            await model.observeSettings()
        }
        .task {
            await model.observePermissions()
        }
    }
}

@MainActor
private final class HotkeySettingsModel: ObservableObject {
    @Published private(set) var current: AppSettings
    @Published private(set) var fnCaptureAvailable: Bool

    private let settings: any SettingsService
    private let permissions: any PermissionsService

    init(settings: any SettingsService, permissions: any PermissionsService) {
        self.settings = settings
        self.permissions = permissions
        self.current = settings.current
        self.fnCaptureAvailable = permissions.status(for: .inputMonitoring) == .granted
    }

    var hotkeyBinding: Binding<HotkeyBinding> {
        Binding(
            get: { self.current.hotkeyBinding },
            set: { value in
                self.settings.update { $0.hotkeyBinding = value }
                self.current = self.settings.current
            }
        )
    }

    func observeSettings() async {
        for await value in settings.changes {
            current = value
        }
    }

    func observePermissions() async {
        for await change in permissions.changes {
            if change.0 == .inputMonitoring {
                fnCaptureAvailable = change.1 == .granted
            }
        }
    }
}

extension HotkeyBinding {
    var displayName: String {
        switch self {
        case .fn:
            return "fn"
        case .rightOption:
            return "Right Option"
        case .rightCommand:
            return "Right Command"
        case .rightControl:
            return "Right Control"
        }
    }
}
