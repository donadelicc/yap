import SwiftUI
import Core
import Settings
import Permissions
import ModelStore

public struct SettingsScene: Scene {
    private let settings: any SettingsService
    private let permissions: any PermissionsService
    private let modelStore: any ModelStoring

    public init(
        settings: any SettingsService,
        permissions: any PermissionsService,
        modelStore: any ModelStoring
    ) {
        self.settings = settings
        self.permissions = permissions
        self.modelStore = modelStore
    }

    public var body: some Scene {
        Settings {
            SettingsRootView(
                settings: settings,
                permissions: permissions,
                modelStore: modelStore
            )
        }
    }
}

struct SettingsRootView: View {
    let settings: any SettingsService
    let permissions: any PermissionsService
    let modelStore: any ModelStoring

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            HotkeyTab(settings: settings, permissions: permissions)
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }

            ModelsTab(settings: settings, modelStore: modelStore)
                .tabItem {
                    Label("Models", systemImage: "square.stack.3d.up")
                }

            PermissionsTab(permissions: permissions)
                .tabItem {
                    Label("Permissions", systemImage: "checkmark.shield")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 680, height: 480)
    }
}
