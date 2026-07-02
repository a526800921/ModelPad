import SwiftUI
import AppKit

@main
struct ModelPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // 窗口由 AppDelegate 统一管理，避免 WindowGroup + 手动 NSWindow 双窗口造成重复视图树和 timer。
        WindowGroup {
            EmptyView()
                .hidden()
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
