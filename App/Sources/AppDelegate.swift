import SwiftUI
import AppKit
import ModelPadCore

/// NSApplicationDelegate：生命周期、窗口控制、菜单栏。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    public let viewModel: AppViewModel
    private var menuBarController: MenuBarController?
    private var mainWindow: NSWindow?

    public override init() {
        let store = ConfigStore.shared
        let pm = ModelProcessManager()
        let api = APIServer(processManager: pm, configStore: store)
        self.viewModel = AppViewModel(configStore: store, processManager: pm, apiServer: api)
        super.init()
    }

    // MARK: - 应用生命周期

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动 API Server
        do {
            try viewModel.apiServer.start()
        } catch {
            print("[ModelPad] API Server start failed: \(error)")
        }

        // 设置菜单栏
        menuBarController = MenuBarController { [weak self] in
            self?.showMainWindow()
        }

        // 显示主窗口
        showMainWindow()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 关闭窗口不退出
    }

    public func applicationWillTerminate(_ notification: Notification) {
        viewModel.shutdown()
    }

    // MARK: - 窗口控制

    public func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ModelPad"
            window.center()
            window.contentView = NSHostingView(
                rootView: MainWindow().environmentObject(viewModel)
            )
            window.isReleasedWhenClosed = false
            window.delegate = self
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 关闭只隐藏
        sender.orderOut(nil)
        return false
    }
}
