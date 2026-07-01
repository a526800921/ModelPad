import SwiftUI
import Combine
import ModelPadCore

/// App 层核心 ViewModel，持有所有核心对象。
@MainActor
public final class AppViewModel: ObservableObject {

    // MARK: - 核心对象

    public let configStore: ConfigStore
    public let processManager: ModelProcessManager
    public let apiServer: APIServer

    // MARK: - 发布的状态

    @Published public var models: [ModelConfig] = []
    @Published public var selectedModelId: UUID?
    @Published public var editingModel: ModelConfig?
    @Published public var hasUnsavedChanges = false
    @Published public var statusMessages: [UUID: ModelStatus] = [:]
    @Published public var pids: [UUID: Int32?] = [:]

    // 日志定时刷新
    private var refreshTimer: Timer?

    // MARK: - 初始化

    public init(configStore: ConfigStore, processManager: ModelProcessManager, apiServer: APIServer) {
        self.configStore = configStore
        self.processManager = processManager
        self.apiServer = apiServer
        reloadModels()
        startStatusRefresh()
    }

    // MARK: - 配置管理

    public func reloadModels() {
        let config = (try? configStore.load()) ?? .default
        models = config.models
        refreshStatus()
    }

    public func selectModel(_ id: UUID?) {
        if hasUnsavedChanges, let current = editingModel {
            saveEditingModel(current)
        }
        selectedModelId = id
        if let id = id {
            editingModel = models.first(where: { $0.id == id })
        } else {
            editingModel = nil
        }
        hasUnsavedChanges = false
    }

    public func newModel() {
        if hasUnsavedChanges, let current = editingModel {
            saveEditingModel(current)
        }
        let model = ModelConfig(name: "新模型", engine: .custom, command: "")
        models.append(model)
        selectedModelId = model.id
        editingModel = model
        saveAllModels()
        hasUnsavedChanges = false
    }

    public func updateEditingModel(name: String? = nil, engine: Engine? = nil, command: String? = nil,
                                    workDir: String? = nil, env: [String: String]? = nil, port: Int? = nil) {
        guard var model = editingModel else { return }
        if let name = name { model.name = name }
        if let engine = engine { model.engine = engine }
        if let command = command { model.command = command }
        if let workDir = workDir { model.workDir = workDir.isEmpty ? nil : workDir }
        if let env = env { model.env = env }
        if let port = port { model.port = port }
        model.updatedAt = Date()
        editingModel = model

        if let idx = models.firstIndex(where: { $0.id == model.id }) {
            models[idx] = model
        }
        hasUnsavedChanges = true
    }

    public func saveEditingModel(_ model: ModelConfig) {
        guard let idx = models.firstIndex(where: { $0.id == model.id }) else { return }
        var m = model
        m.updatedAt = Date()
        models[idx] = m
        editingModel = m
        hasUnsavedChanges = false
        saveAllModels()
    }

    public func deleteModel(_ id: UUID) {
        // 如果模型正在运行，先停止
        let status = processManager.status(for: id)
        if status == .running || status == .starting {
            _ = processManager.stop(modelId: id)
        }

        models.removeAll(where: { $0.id == id })
        if selectedModelId == id {
            selectedModelId = models.first?.id
            editingModel = models.first
        }
        hasUnsavedChanges = false
        saveAllModels()
        refreshStatus()
    }

    public func autoSaveBeforeStart(for id: UUID) {
        if hasUnsavedChanges, let editing = editingModel, editing.id == id {
            saveEditingModel(editing)
        }
    }

    private func saveAllModels() {
        var config = (try? configStore.load()) ?? .default
        config.models = models
        try? configStore.save(config)
    }

    // MARK: - 进程控制

    public func startModel(_ id: UUID) {
        autoSaveBeforeStart(for: id)
        guard let config = models.first(where: { $0.id == id }) else { return }
        _ = try? processManager.start(config: config)
        refreshStatus()
    }

    public func stopModel(_ id: UUID) {
        _ = processManager.stop(modelId: id)
        refreshStatus()
    }

    public func restartModel(_ id: UUID) {
        autoSaveBeforeStart(for: id)
        guard let config = models.first(where: { $0.id == id }) else { return }
        _ = try? processManager.restart(modelId: id, config: config)
        refreshStatus()
    }

    public func startAllModels() {
        for model in models {
            let status = processManager.status(for: model.id)
            if status == .stopped || status == .error {
                _ = try? processManager.start(config: model)
            }
        }
        refreshStatus()
    }

    public func stopAllModels() {
        for model in models {
            let status = processManager.status(for: model.id)
            if status == .running || status == .starting {
                _ = processManager.stop(modelId: model.id)
            }
        }
        refreshStatus()
    }

    // MARK: - 日志

    public func logs(for id: UUID) -> [ModelLogEntry] {
        processManager.logs(for: id)
    }

    public func clearLogs(for id: UUID) {
        processManager.clearLogs(for: id)
    }

    // MARK: - 状态刷新

    public func refreshStatus() {
        var msgs: [UUID: ModelStatus] = [:]
        var ps: [UUID: Int32?] = [:]
        for model in models {
            msgs[model.id] = processManager.status(for: model.id)
            ps[model.id] = processManager.pid(for: model.id)
        }
        statusMessages = msgs
        pids = ps
    }

    private func startStatusRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }

    public func stopStatusRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - 生命周期

    public func shutdown() {
        stopStatusRefresh()
        stopAllRunningProcesses()
    }

    /// 停止所有运行中进程（主线程调用），不停止 API Server。
    public func stopAllRunningProcesses() {
        for model in models {
            let status = processManager.status(for: model.id)
            if status == .running || status == .starting {
                _ = processManager.stop(modelId: model.id)
            }
        }
    }
}
