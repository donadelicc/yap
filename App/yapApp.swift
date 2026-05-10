import SwiftUI
import AppKit

@main
struct yapApp: App {
    var body: some Scene {
        MenuBarExtra("yap", systemImage: "mic") {
            Button("Quit yap") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
