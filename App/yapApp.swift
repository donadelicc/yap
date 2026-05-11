import AppKit
import MenuBarUI
import SettingsUI
import SwiftUI

@main
struct yapApp: App {
    private let container: Container
    @StateObject private var coordinator: AppCoordinator

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
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            MenuBarIcon(state: coordinator.state)
            .task {
                do {
                    try await coordinator.start()
                } catch {
                    // AppCoordinator publishes startup failures to drive the menu bar error state.
                }
            }
        }

        SettingsScene(
            settings: container.settings,
            permissions: container.permissions,
            modelStore: container.modelStore
        )
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
