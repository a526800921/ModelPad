import Foundation
import Testing
import ModelPadCore
@testable import ModelPadApp

// MARK: - 辅助

@MainActor
func makeTestStoreAndPM() -> (ConfigStore, ModelProcessManager) {
    let store = ConfigStore(
        baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelPadVMTest-\(UUID().uuidString)")
    )
    let pm = ModelProcessManager()
    return (store, pm)
}

@MainActor
func makeTestViewModel() -> (AppViewModel, ConfigStore, ModelProcessManager) {
    let (store, pm) = makeTestStoreAndPM()
    let api = APIServer(host: "127.0.0.1", port: 27000 + Int.random(in: 0...999), processManager: pm, configStore: store)
    let vm = AppViewModel(configStore: store, processManager: pm, apiServer: api)
    return (vm, store, pm)
}

// MARK: - 装配测试

@Suite(.serialized) struct AppAssemblyTests {

    @Test("ConfigStore + ProcessManager + APIServer 装配成功")
    @MainActor
    func appAssemblyCreatesCoreObjects() {
        let (vm, _, _) = makeTestViewModel()
        // 初始状态：空模型列表
        #expect(vm.models.isEmpty)
        #expect(vm.selectedModelId == nil)

        // 不做额外操作就清理
        vm.stopAllRunningProcesses()
    }
}

// MARK: - 模型 CRUD

@Suite(.serialized) struct ModelCRUDTests {

    @Test("newModel 添加模型并保存到配置")
    @MainActor
    func newModelAddsAndPersists() throws {
        let (vm, store, _) = makeTestViewModel()

        vm.newModel()
        #expect(vm.models.count == 1)
        #expect(vm.models[0].name == "新模型")
        #expect(vm.hasUnsavedChanges == false, "newModel 应自动保存")

        // 验证持久化
        let saved = try store.load()
        #expect(saved.models.count == 1)
    }

    @Test("编辑模型后 hasUnsavedChanges 为 true")
    @MainActor
    func editSetsUnsaved() {
        let (vm, _, _) = makeTestViewModel()
        vm.newModel()

        vm.selectModel(vm.models[0].id)
        vm.updateEditingModel(name: "Renamed")
        #expect(vm.hasUnsavedChanges == true)
    }

    @Test("saveEditingModel 写入配置并清除未保存标记")
    @MainActor
    func savePersistsAndClearsUnsaved() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.selectModel(vm.models[0].id)
        vm.updateEditingModel(name: "SavedName")

        guard let editing = vm.editingModel else {
            #expect(Bool(false), "应有 editingModel")
            return
        }
        vm.saveEditingModel(editing)
        #expect(vm.hasUnsavedChanges == false)

        let saved = try store.load()
        #expect(saved.models[0].name == "SavedName")
    }

    @Test("deleteModel 从配置中移除模型")
    @MainActor
    func deleteModelRemovesFromConfig() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        let id = vm.models[0].id

        vm.deleteModel(id)
        #expect(vm.models.isEmpty)

        let saved = try store.load()
        #expect(saved.models.isEmpty)
    }

    @Test("deleteModel 对运行中模型先停止再删除")
    @MainActor
    func deleteRunningModelStopsFirst() throws {
        let (vm, _, pm) = makeTestViewModel()
        // 用 echo 命令（快速完成、无残留）
        vm.newModel()
        let id = vm.models[0].id
        vm.updateEditingModel(command: "sleep 30")

        // 手动启动模型
        guard let config = vm.models.first else { return }
        _ = try pm.start(config: config)
        #expect(pm.status(for: id) == .running)

        // 删除（应触发先停止）
        vm.deleteModel(id)
        #expect(vm.models.isEmpty)
        #expect(pm.status(for: id) == .stopped)
    }

    @Test("删除未运行模型不会调用 stop")
    @MainActor
    func deleteStoppedModelDoesNotStop() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        let id = vm.models[0].id

        // 模型是 stopped 状态
        vm.deleteModel(id)
        #expect(vm.models.isEmpty)

        let saved = try store.load()
        #expect(saved.models.isEmpty)
    }
}

// MARK: - 自动保存

@Suite(.serialized) struct AutoSaveTests {

    @Test("autoSaveBeforeStart 将未保存配置写入磁盘")
    @MainActor
    func autoSaveBeforeStartPersists() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        let id = vm.models[0].id
        vm.selectModel(id)
        vm.updateEditingModel(name: "BeforeStart")

        #expect(vm.hasUnsavedChanges == true)
        vm.autoSaveBeforeStart(for: id)
        #expect(vm.hasUnsavedChanges == false)

        let saved = try store.load()
        #expect(saved.models[0].name == "BeforeStart")
    }
}

// MARK: - 全部启停

@Suite(.serialized) struct AllStartStopTests {

    @Test("startAllModels 只启动 stopped 和 error 模型")
    @MainActor
    func startAllSkipsRunning() throws {
        let (vm, _, pm) = makeTestViewModel()

        // 添加两个模型，各自设置有效命令
        vm.newModel()
        vm.selectModel(vm.models[0].id)
        vm.updateEditingModel(name: "M1", command: "sleep 10")
        vm.saveEditingModel(vm.models[0])

        vm.newModel()
        vm.selectModel(vm.models[1].id)
        vm.updateEditingModel(name: "M2", command: "sleep 10")
        vm.saveEditingModel(vm.models[1])

        let m1 = vm.models[0]
        let m2 = vm.models[1]

        // 手动启动 m1
        _ = try? pm.start(config: m1)

        // startAll 应只启动 m2（dispatch 到后台，等待完成）
        vm.startAllModels()
        Thread.sleep(forTimeInterval: 0.5)

        #expect(pm.status(for: m1.id) == .running)
        #expect(pm.status(for: m2.id) == .running)

        _ = pm.stop(modelId: m1.id)
        _ = pm.stop(modelId: m2.id)
    }

    @Test("stopAllModels 只停止 running 和 starting 模型")
    @MainActor
    func stopAllSkipsStopped() throws {
        let (vm, _, pm) = makeTestViewModel()

        vm.newModel()
        vm.selectModel(vm.models[0].id)
        vm.updateEditingModel(name: "M1", command: "sleep 30")
        vm.saveEditingModel(vm.models[0])

        vm.newModel()
        vm.selectModel(vm.models[1].id)
        vm.updateEditingModel(name: "M2", command: "sleep 30")
        vm.saveEditingModel(vm.models[1])

        let m1 = vm.models[0]
        let m2 = vm.models[1]

        // 只启动 m1
        _ = try? pm.start(config: m1)

        vm.stopAllModels()
        Thread.sleep(forTimeInterval: 0.5)

        #expect(pm.status(for: m1.id) == .stopped)
        #expect(pm.status(for: m2.id) == .stopped)  // 本来就 stopped
    }
}

// MARK: - 配置刷新（reloadModels）

@Suite(.serialized) struct ConfigReloadTests {

    @Test("reloadModels 从磁盘重新读取新模型")
    @MainActor
    func reloadModelsPicksUpNewModel() throws {
        let (vm, store, _) = makeTestViewModel()

        // 初始为空
        #expect(vm.models.isEmpty)

        // 绕过 ViewModel 直接写入配置
        let newModel = ModelConfig(name: "外部添加", engine: .custom, command: "echo hi")
        var config = try store.load()
        config.models.append(newModel)
        try store.save(config)

        // 刷新
        vm.reloadModels()

        #expect(vm.models.count == 1)
        #expect(vm.models[0].name == "外部添加")
    }

    @Test("reloadModels 刷新前自动保存未保存编辑")
    @MainActor
    func reloadModelsSavesUnsavedEditsFirst() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.selectModel(vm.models[0].id)
        vm.updateEditingModel(name: "已改名")

        #expect(vm.hasUnsavedChanges == true)

        vm.reloadModels()

        // 刷新后未保存变更已持久化
        let saved = try store.load()
        #expect(saved.models[0].name == "已改名")
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("reloadModels 当前选中模型仍存在时保持选中")
    @MainActor
    func reloadModelsPreservesSelection() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.newModel()
        let m1Id = vm.models[0].id

        vm.selectModel(m1Id)
        #expect(vm.selectedModelId == m1Id)

        // 绕过 ViewModel 更新配置（保留两个模型）
        var config = try store.load()
        config.models[0].name = "M1-renamed"
        try store.save(config)

        vm.reloadModels()

        #expect(vm.selectedModelId == m1Id)
        #expect(vm.editingModel?.name == "M1-renamed")
    }

    @Test("reloadModels 当前选中模型已删除时选择第一个")
    @MainActor
    func reloadModelsFallsBackToFirstWhenSelectedGone() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.newModel()
        let m1Id = vm.models[0].id
        let m2Id = vm.models[1].id

        vm.selectModel(m1Id)

        // 绕过 ViewModel 删除 m1
        var config = try store.load()
        config.models.removeAll(where: { $0.id == m1Id })
        try store.save(config)

        vm.reloadModels()

        #expect(vm.selectedModelId == m2Id)
        #expect(vm.editingModel?.id == m2Id)
    }

    @Test("reloadModels 列表为空时清空选中和编辑态")
    @MainActor
    func reloadModelsClearsSelectionWhenEmpty() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.selectModel(vm.models[0].id)

        // 绕过 ViewModel 清空配置
        var config = try store.load()
        config.models = []
        try store.save(config)

        vm.reloadModels()

        #expect(vm.models.isEmpty)
        #expect(vm.selectedModelId == nil)
        #expect(vm.editingModel == nil)
    }

    @Test("reloadModels 不启动任何模型")
    @MainActor
    func reloadModelsDoesNotStartModels() throws {
        let (vm, store, pm) = makeTestViewModel()

        // 写入一个带有效命令的模型
        let model = ModelConfig(name: "NotStarted", engine: .custom, command: "sleep 10")
        var config = try store.load()
        config.models.append(model)
        try store.save(config)

        vm.reloadModels()

        #expect(vm.models.count == 1)
        #expect(pm.status(for: vm.models[0].id) == .stopped)
    }

    @Test("reloadModels 不停止运行中模型")
    @MainActor
    func reloadModelsDoesNotStopRunningModels() throws {
        let (vm, store, pm) = makeTestViewModel()
        vm.newModel()
        let id = vm.models[0].id
        vm.selectModel(id)
        vm.updateEditingModel(command: "sleep 60")
        vm.saveEditingModel(vm.models[0])

        // 启动模型
        _ = try pm.start(config: vm.models[0])
        #expect(pm.status(for: id) == .running)

        // 写入新模型但保留运行中的
        let newModel = ModelConfig(name: "新增", engine: .custom, command: "echo hi")
        var config = try store.load()
        config.models.append(newModel)
        try store.save(config)

        vm.reloadModels()

        #expect(vm.models.count == 2)
        #expect(pm.status(for: id) == .running, "刷新不应停止运行中模型")

        _ = pm.stop(modelId: id)
    }

    @Test("reloadModels 配置损坏时保留旧列表")
    @MainActor
    func reloadModelsPreservesStateOnCorruptedConfig() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.selectModel(vm.models[0].id)
        let originalCount = vm.models.count
        let originalId = vm.selectedModelId

        // 破坏 config.json
        let fileURL = store.baseDirectory.appendingPathComponent("config.json")
        try "{ bad json".write(to: fileURL, atomically: true, encoding: .utf8)

        vm.reloadModels()

        // 应保留旧状态
        #expect(vm.models.count == originalCount, "损坏时保留旧模型列表")
        #expect(vm.selectedModelId == originalId, "损坏时保留旧选中项")
    }

    @Test("reloadModels 存在未保存编辑且配置损坏时，保存操作会覆盖损坏文件并成功刷新")
    @MainActor
    func reloadModelsUnsavedChangesSavedBeforeCorruptionCheck() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.selectModel(vm.models[0].id)
        vm.updateEditingModel(name: "未保存")

        #expect(vm.hasUnsavedChanges == true)

        // 破坏 config.json
        let fileURL = store.baseDirectory.appendingPathComponent("config.json")
        try "{ corrupt".write(to: fileURL, atomically: true, encoding: .utf8)

        vm.reloadModels()

        // 由于 saveEditingModel 先于损坏检测执行，保存会覆盖损坏文件并成功刷新
        #expect(vm.hasUnsavedChanges == false, "保存操作覆盖损坏文件，刷新成功")

        // 验证未保存编辑已持久化
        let saved = try store.load()
        #expect(saved.models.count == 1)
        #expect(saved.models[0].name == "未保存")
    }

    @Test("reloadModels 从配置中删除的模型不在列表中显示")
    @MainActor
    func reloadModelsRemovesDeletedModelFromList() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.newModel()
        let m1Id = vm.models[0].id

        // 绕过 ViewModel 删除 m1
        var config = try store.load()
        config.models.removeAll(where: { $0.id == m1Id })
        try store.save(config)

        vm.reloadModels()

        #expect(vm.models.count == 1)
        #expect(!vm.models.contains(where: { $0.id == m1Id }))
    }

    @Test("reloadModels hasUnsavedChanges 刷新后为 false")
    @MainActor
    func reloadModelsClearsUnsavedChanges() throws {
        let (vm, store, _) = makeTestViewModel()
        vm.newModel()
        vm.selectModel(vm.models[0].id)
        vm.updateEditingModel(name: "改名")

        #expect(vm.hasUnsavedChanges == true)

        vm.reloadModels()

        #expect(vm.hasUnsavedChanges == false)

        // 编辑内容已保存
        let saved = try store.load()
        #expect(saved.models[0].name == "改名")
    }
}
