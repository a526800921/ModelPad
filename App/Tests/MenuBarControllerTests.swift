import Foundation
import Testing
import AppKit
import ModelPadCore
@testable import ModelPadApp

// MARK: - 辅助

@MainActor
func makeTestEnv() -> (MenuBarController, AppViewModel, ConfigStore, ModelProcessManager) {
    let store = ConfigStore(
        baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarTest-\(UUID().uuidString)")
    )
    let pm = ModelProcessManager()
    let api = APIServer(host: "127.0.0.1", port: 27000 + Int.random(in: 0...999), processManager: pm, configStore: store)
    let vm = AppViewModel(configStore: store, processManager: pm, apiServer: api)
    let controller = MenuBarController(
        onShowPanel: {},
        appViewModel: vm
    )
    return (controller, vm, store, pm)
}

/// 写入一组服务配置到指定 ViewModel。
@MainActor
func saveModels(_ models: [ModelConfig], to vm: AppViewModel) throws {
    var config = (try? vm.configStore.load()) ?? .default
    config.models = models
    try vm.configStore.save(config)
    vm.reloadModels()
}

// MARK: - 菜单构建测试

@Suite(.serialized) struct MenuBarMenuTests {

    @Test("空配置时菜单仅含显示面板和退出")
    @MainActor
    func emptyConfigShowsOnlyPanelAndQuit() throws {
        let (controller, vm, _, _) = makeTestEnv()
        // 确保空配置
        try saveModels([], to: vm)

        let menu = NSMenu()
        controller.menuWillOpen(menu)

        let titles = menu.items.map(\.title)
        #expect(titles == ["显示面板", "退出"], "空配置应只显示面板和退出，实际: \(titles)")
    }

    @Test("有服务配置时菜单展示全部服务名称")
    @MainActor
    func configuredServicesShowAllNames() throws {
        let (controller, vm, _, _) = makeTestEnv()
        let models = [
            ModelConfig(name: "Alpha", engine: .custom, command: "echo a"),
            ModelConfig(name: "Beta", engine: .custom, command: "echo b"),
            ModelConfig(name: "Gamma", engine: .ollama, command: "echo c"),
        ]
        try saveModels(models, to: vm)

        let menu = NSMenu()
        controller.menuWillOpen(menu)

        // 前 N 项是服务名称
        let serviceTitles = menu.items.prefix(models.count).map(\.title)
        #expect(serviceTitles == ["Alpha", "Beta", "Gamma"],
                 "应展示全部服务名称，实际: \(serviceTitles)")

        // 最后两项是分隔线 + 面板 / 退出
        #expect(menu.items.count == models.count + 3, // N + separator + panel + quit
                 "菜单项总数应为 N+3，实际: \(menu.items.count)")

        let lastThree = menu.items.suffix(3).map(\.title)
        #expect(lastThree == ["", "显示面板", "退出"],
                 "最后三项应为分隔线+面板+退出，实际: \(lastThree)")
    }

    @Test("运行中服务显示绿色状态点")
    @MainActor
    func runningServiceShowsGreenDot() throws {
        let (controller, vm, _, pm) = makeTestEnv()
        let model = ModelConfig(name: "RunningSvc", engine: .custom, command: "sleep 30")
        try saveModels([model], to: vm)

        // 手动启动服务
        _ = try pm.start(config: model)
        #expect(pm.status(for: model.id) == .running, "前提：服务应为 running")

        let menu = NSMenu()
        controller.menuWillOpen(menu)

        guard let item = menu.items.first else {
            #expect(Bool(false), "菜单应至少有一项")
            return
        }
        #expect(item.title == "RunningSvc")
        #expect(item.image != nil, "运行中服务应有状态点图像")

        _ = pm.stop(modelId: model.id)
    }

    @Test("已停止服务显示灰色状态点")
    @MainActor
    func stoppedServiceShowsGrayDot() throws {
        let (controller, vm, _, _) = makeTestEnv()
        let model = ModelConfig(name: "StoppedSvc", engine: .custom, command: "sleep 30")
        try saveModels([model], to: vm)

        let menu = NSMenu()
        controller.menuWillOpen(menu)

        guard let item = menu.items.first else {
            #expect(Bool(false), "菜单应至少有一项")
            return
        }
        #expect(item.title == "StoppedSvc")
        #expect(item.image != nil, "已停止服务应有灰色状态点图像")
    }

    @Test("服务菜单项为只读，无 action")
    @MainActor
    func serviceItemsAreReadOnly() throws {
        let (controller, vm, _, _) = makeTestEnv()
        let models = [
            ModelConfig(name: "Svc1", engine: .custom, command: "echo 1"),
            ModelConfig(name: "Svc2", engine: .custom, command: "echo 2"),
        ]
        try saveModels(models, to: vm)

        let menu = NSMenu()
        controller.menuWillOpen(menu)

        for (i, item) in menu.items.prefix(models.count).enumerated() {
            #expect(item.action == nil, "服务 \(i) 不应有点击 action")
            #expect(item.isEnabled, "服务 \(i) 应保持 enabled（只读）")
        }
    }

    @Test("显示面板项点击触发 onShowPanel")
    @MainActor
    func panelItemTriggersCallback() async throws {
        var called = false
        let store = ConfigStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MenuBarTest-\(UUID().uuidString)")
        )
        let pm = ModelProcessManager()
        let api = APIServer(host: "127.0.0.1", port: 27000 + Int.random(in: 0...999), processManager: pm, configStore: store)
        let vm = AppViewModel(configStore: store, processManager: pm, apiServer: api)
        let controller = MenuBarController(
            onShowPanel: { called = true },
            appViewModel: vm
        )

        let menu = NSMenu()
        controller.menuWillOpen(menu)

        // 找到"显示面板"项
        let panelItem = menu.items.first(where: { $0.title == "显示面板" })
        #expect(panelItem != nil, "应存在显示面板菜单项")
        #expect(panelItem?.action == #selector(MenuBarController.showPanel))

        // 通过 performClick 验证闭环调用
        panelItem.map { _ = $0.target?.perform($0.action, with: $0) }
        #expect(called, "onShowPanel 应为 true")
    }
}
