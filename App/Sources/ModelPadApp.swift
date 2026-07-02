import SwiftUI
import AppKit

@main
struct ModelPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(delegate.viewModel)
                .frame(minWidth: 800, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appTermination) {
                Button("退出 ModelPad") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
