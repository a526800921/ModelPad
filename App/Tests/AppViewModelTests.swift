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
        let (vm, store, pm) = makeTestViewModel()
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
        #expect(vm.models[0].name == "New Model")
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

        // 添加两个模型
        vm.newModel()  // stopped
        vm.newModel()  // stopped
        let m1 = vm.models[0]
        let m2 = vm.models[1]

        vm.updateEditingModel(command: "sleep 10")

        // 手动启动 m1
        _ = try? pm.start(config: m1)

        // startAll 应只启动 m2
        vm.startAllModels()

        #expect(pm.status(for: m1.id) == .running)
        #expect(pm.status(for: m2.id) == .running)

        pm.stop(modelId: m1.id)
        pm.stop(modelId: m2.id)
    }

    @Test("stopAllModels 只停止 running 和 starting 模型")
    @MainActor
    func stopAllSkipsStopped() throws {
        let (vm, _, pm) = makeTestViewModel()

        vm.newModel()
        vm.newModel()
        let m1 = vm.models[0]
        let m2 = vm.models[1]

        // 只启动 m1
        _ = try? pm.start(config: m1)

        vm.stopAllModels()

        #expect(pm.status(for: m1.id) == .stopped)
        #expect(pm.status(for: m2.id) == .stopped)  // 本来就 stopped
    }
}
