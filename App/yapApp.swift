import AppKit
import MenuBarUI
import SettingsUI
import SwiftUI

@main
struct yapApp: App {
    private let container: Container
    @StateObject private var coordinator: AppCoordinator

    @MainActor
    init() {
        let container = Container()
        self.container = container
        _coordinator = StateObject(wrappedValue: container.coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                state: coordinator.state,
                lastError: coordinator.lastError,
                onOpenSettings: openSettings,
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
            .task {
                do {
                    try await coordinator.start()
                } catch {
                }
            }
        } label: {
            MenuBarIcon(state: coordinator.state)
        }

        SettingsScene(
            settings: container.settings,
            permissions: container.permissions,
            modelStore: container.modelStore
        )
    }

    private func openSettings() {
        NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
    }
}
