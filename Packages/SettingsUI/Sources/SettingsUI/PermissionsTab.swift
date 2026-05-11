import AppKit
import SwiftUI
import Core
import Permissions

struct PermissionsTab: View {
    @StateObject private var model: PermissionsSettingsModel

    init(permissions: any PermissionsService) {
        _model = StateObject(wrappedValue: PermissionsSettingsModel(permissions: permissions))
    }

    var body: some View {
        Form {
            ForEach(Permission.settingsDisplayOrder, id: \.self) { permission in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(permission.displayName)
                        Text(model.status(for: permission).displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Open System Settings") {
                        Task {
                            await model.openAndPoll(permission)
                        }
                    }
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
private final class PermissionsSettingsModel: ObservableObject {
    @Published private var statuses: [Permission: PermissionStatus]
    private let permissions: any PermissionsService

    init(permissions: any PermissionsService) {
        self.permissions = permissions
        self.statuses = Dictionary(
            uniqueKeysWithValues: Permission.settingsDisplayOrder.map { ($0, permissions.status(for: $0)) }
        )
    }

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .undetermined
    }

    func observeChanges() async {
        for await change in permissions.changes {
            statuses[change.0] = change.1
        }
    }

    func openAndPoll(_ permission: Permission) async {
        openSystemSettings(for: permission)
        statuses[permission] = await permissions.request(permission)

        for _ in 0..<12 where !isGranted(statuses[permission]) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            statuses[permission] = permissions.status(for: permission)
        }
    }

    private func isGranted(_ status: PermissionStatus?) -> Bool {
        guard case .granted = status else {
            return false
        }
        return true
    }

    private func openSystemSettings(for permission: Permission) {
        guard let url = URL(string: permission.systemSettingsURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

extension Permission {
    static var settingsDisplayOrder: [Permission] {
        [.microphone, .accessibility, .inputMonitoring]
    }

    var displayName: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    var systemSettingsURL: String {
        switch self {
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }
}

extension PermissionStatus {
    var displayName: String {
        switch self {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .undetermined:
            return "Undetermined"
        }
    }
}
