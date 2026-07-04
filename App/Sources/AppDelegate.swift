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
        let readmePath: String? = {
            // 优先：Bundle 内嵌的 README（打包 .app 可用）
            if let path = Bundle.main.path(forResource: "README", ofType: "md") {
                return path
            }
            // 回退：开发模式下当前目录
            let path = FileManager.default.currentDirectoryPath + "/README.md"
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }()
        let api = APIServer(processManager: pm, configStore: store, readmePath: readmePath)
        self.viewModel = AppViewModel(configStore: store, processManager: pm, apiServer: api)
        super.init()
    }

    // MARK: - 应用生命周期

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动 API Server
        viewModel.apiServer.onModelStateChanged = { [weak viewModel] in
            DispatchQueue.main.async {
                viewModel?.refreshStatus()
            }
        }
        viewModel.apiServer.onConfigReloadRequested = { [weak viewModel] in
            DispatchQueue.main.async {
                viewModel?.reloadModels()
            }
        }
        do {
            try viewModel.apiServer.start()
        } catch {
            print("[ModelPad] API 服务启动失败：\(error)")
        }

        // 设置菜单栏
        menuBarController = MenuBarController(
            onShowPanel: { [weak self] in
                self?.showMainWindow()
            },
            appViewModel: viewModel
        )

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

        // WindowGroup 创建的窗口，首次显示时绑定 delegate 实现关闭隐藏
        if mainWindow == nil, let swiftUIWindow = NSApp.windows.first {
            swiftUIWindow.delegate = self
            swiftUIWindow.isReleasedWhenClosed = false
            mainWindow = swiftUIWindow
        }

        mainWindow?.makeKeyAndOrderFront(nil)
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
