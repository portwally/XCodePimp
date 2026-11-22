import SwiftUI

@main
struct XCodePimpApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("XcodePimp", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Rescan") { Task { await model.scan() } }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
