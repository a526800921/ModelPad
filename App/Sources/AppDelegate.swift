import SwiftUI
import AppKit
import ModelPadCore

/// NSApplicationDelegate：生命周期、窗口控制、菜单栏。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    public let viewModel: AppViewModel
    private var menuBarController: MenuBarController?
    private var mainWindow: NSWindow?
    private var isTerminating = false

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
            print("[ModelPad] API 服务启动失败：\(error)")
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

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else {
            return .terminateNow
        }
        isTerminating = true

        viewModel.stopStatusRefresh()

        // 所有阻塞清理全放后台线程，30s 超时兜底确保一定 reply
        let pm = viewModel.processManager
        let models = viewModel.models
        let api = viewModel.apiServer

        DispatchQueue.global().async {
            // 停止所有托管进程（后台线程，逐个停止）
            for model in models {
                let status = pm.status(for: model.id)
                if status == .running || status == .starting {
                    _ = pm.stop(modelId: model.id)
                }
            }

            // 停止 API Server（可能阻塞）
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                try? api.stop()
                group.leave()
            }

            // 30s 总超时兜底
            _ = group.wait(timeout: .now() + 30)

            // 确保一定会 reply
            DispatchQueue.main.async {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }

        return .terminateLater
    }

    // MARK: - 窗口控制

    public func showMainWindow() {
        viewModel.isWindowVisible = true
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
        // 关闭只隐藏，暂停状态刷新
        viewModel.isWindowVisible = false
        sender.orderOut(nil)
        return false
    }
}
