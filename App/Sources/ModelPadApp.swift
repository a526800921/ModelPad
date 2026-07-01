import SwiftUI

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
            CommandGroup(replacing: .newItem) {} // 移除 New 菜单项
        }
    }
}
