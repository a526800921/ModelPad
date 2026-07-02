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
        // 后台执行阻塞操作（TCP 健康检查等），UI 保持响应
        let pm = processManager
        DispatchQueue.global().async { [weak self] in
            _ = try? pm.start(config: config)
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    public func stopModel(_ id: UUID) {
        let pm = processManager
        DispatchQueue.global().async { [weak self] in
            _ = pm.stop(modelId: id)
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    public func restartModel(_ id: UUID) {
        autoSaveBeforeStart(for: id)
        guard let config = models.first(where: { $0.id == id }) else { return }
        let pm = processManager
        DispatchQueue.global().async { [weak self] in
            _ = try? pm.restart(modelId: id, config: config)
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    public func startAllModels() {
        let pm = processManager
        let modelsCopy = models
        DispatchQueue.global().async { [weak self] in
            for model in modelsCopy {
                let status = pm.status(for: model.id)
                if status == .stopped || status == .error {
                    _ = try? pm.start(config: model)
                }
            }
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    public func stopAllModels() {
        let pm = processManager
        let modelsCopy = models
        DispatchQueue.global().async { [weak self] in
            for model in modelsCopy {
                let status = pm.status(for: model.id)
                if status == .running || status == .starting {
                    _ = pm.stop(modelId: model.id)
                }
            }
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    // MARK: - 日志

    public func logs(for id: UUID) -> [ModelLogEntry] {
        processManager.logs(for: id)
    }

    public func clearLogs(for id: UUID) {
        processManager.clearLogs(for: id)
    }

    // MARK: - 状态刷新

    /// 窗口是否可见。隐藏时暂停刷新。
    public var isWindowVisible = true {
        didSet {
            if isWindowVisible != oldValue {
                updateRefreshTimer()
            }
        }
    }

    public func refreshStatus() {
        var msgs: [UUID: ModelStatus] = [:]
        var ps: [UUID: Int32?] = [:]
        for model in models {
            msgs[model.id] = processManager.status(for: model.id)
            ps[model.id] = processManager.pid(for: model.id)
        }
        statusMessages = msgs
        pids = ps
        // 模型状态变化后自适应调整轮询频率
        updateRefreshTimer()
    }

    /// 是否有模型正在运行或启动中。
    private var hasActiveModels: Bool {
        models.contains { model in
            let s = processManager.status(for: model.id)
            return s == .running || s == .starting
        }
    }

    private func startStatusRefresh() {
        updateRefreshTimer()
    }

    private func updateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        // 窗口隐藏时完全暂停轮询
        guard isWindowVisible else { return }

        // 无运行模型时降频到 10s，有运行模型时 2s
        let interval: TimeInterval = hasActiveModels ? 2.0 : 10.0
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
