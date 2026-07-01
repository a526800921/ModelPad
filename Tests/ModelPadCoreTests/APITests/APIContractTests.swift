import Foundation
import Testing

@testable import ModelPadCore

// MARK: - 辅助

/// 创建测试用 API Server（使用临时目录和随机端口）。
func makeTestServer() throws -> (APIServer, ConfigStore, ModelProcessManager, Int) {
    let store = ConfigStore(
        baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelPadAPITest-\(UUID().uuidString)")
    )
    let pm = ModelProcessManager()
    let port = 21000 + Int.random(in: 0...999)
    let server = APIServer(host: "127.0.0.1", port: port, processManager: pm, configStore: store)
    return (server, store, pm, port)
}

/// 向 API 发送请求的辅助函数。
func apiRequest(
    method: String,
    path: String,
    port: Int,
    body: Data? = nil
) async throws -> (Int, [String: Any]) {
    let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    request.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: request)
    let statusCode = (response as! HTTPURLResponse).statusCode
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    return (statusCode, json)
}

// 保存测试模型配置
func saveTestModel(named name: String, command: String, port: Int? = nil, to store: ConfigStore) throws -> ModelConfig {
    let config = ModelConfig(name: name, engine: .custom, command: command, port: port)
    var appConfig = try store.load()
    appConfig.models.append(config)
    try store.save(appConfig)
    return config
}

// MARK: - GET /api/health

@Test("GET /api/health 返回 ok:true")
func healthEndpoint() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(method: "GET", path: "/api/health", port: port)
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
}

// MARK: - GET /api/models

@Test("GET /api/models 返回模型摘要列表")
func listModelsEndpoint() async throws {
    let (server, store, _, port) = try makeTestServer()
    let model = try saveTestModel(named: "TestModel", command: "echo hi", to: store)
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(method: "GET", path: "/api/models", port: port)
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)

    let models = json["models"] as? [[String: Any]]
    #expect(models?.count == 1)
    #expect(models?[0]["name"] as? String == "TestModel")
    #expect(models?[0]["engine"] as? String == "custom")
    #expect(models?[0]["id"] as? String == model.id.uuidString)
}

@Test("GET /api/models 空模型列表返回空数组")
func listModelsEmpty() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(method: "GET", path: "/api/models", port: port)
    #expect(status == 200)
    let models = json["models"] as? [[String: Any]]
    #expect(models?.isEmpty == true)
}

// MARK: - GET /api/models/:id

@Test("GET /api/models/:id 返回单个模型摘要")
func getModelEndpoint() async throws {
    let (server, store, _, port) = try makeTestServer()
    let model = try saveTestModel(named: "Single", command: "echo test", port: 9999, to: store)
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(method: "GET", path: "/api/models/\(model.id.uuidString)", port: port)
    #expect(status == 200)

    let m = json["model"] as? [String: Any]
    #expect(m?["name"] as? String == "Single")
    #expect(m?["port"] as? Int == 9999)
    #expect(m?["status"] as? String == "stopped")
}

@Test("GET /api/models/:id 未知模型返回 model_not_found")
func getModelNotFound() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "GET",
        path: "/api/models/00000000-0000-0000-0000-000000000000",
        port: port
    )
    #expect(status == 404)
    #expect(json["ok"] as? Bool == false)
    let error = json["error"] as? [String: Any]
    #expect(error?["code"] as? String == "model_not_found")
}

// MARK: - 敏感字段不泄露

@Test("模型摘要不包含 command")
func modelSummaryExcludesCommand() async throws {
    let (server, store, _, port) = try makeTestServer()
    let model = try saveTestModel(named: "Safe", command: "secret-command", to: store)
    try server.start()
    defer { try? server.stop() }

    let (_, json) = try await apiRequest(method: "GET", path: "/api/models/\(model.id.uuidString)", port: port)
    let m = json["model"] as? [String: Any]
    #expect(m?["command"] == nil, "ModelSummary 不应包含 command")
}

@Test("模型摘要不包含 workDir")
func modelSummaryExcludesWorkDir() async throws {
    let (server, store, _, port) = try makeTestServer()
    let model = try saveTestModel(named: "Safe", command: "echo", to: store)
    try server.start()
    defer { try? server.stop() }

    let (_, json) = try await apiRequest(method: "GET", path: "/api/models/\(model.id.uuidString)", port: port)
    let m = json["model"] as? [String: Any]
    #expect(m?["workDir"] == nil, "ModelSummary 不应包含 workDir")
}

@Test("模型摘要不包含 env")
func modelSummaryExcludesEnv() async throws {
    let (server, store, _, port) = try makeTestServer()
    let model = try saveTestModel(named: "Safe", command: "echo", to: store)
    try server.start()
    defer { try? server.stop() }

    let (_, json) = try await apiRequest(method: "GET", path: "/api/models/\(model.id.uuidString)", port: port)
    let m = json["model"] as? [String: Any]
    #expect(m?["env"] == nil, "ModelSummary 不应包含 env")
}

@Test("GET /api/models 列表也不泄露敏感字段")
func listModelsExcludesSensitiveFields() async throws {
    let (server, store, _, port) = try makeTestServer()
    _ = try saveTestModel(named: "M", command: "hidden-cmd", to: store)
    try server.start()
    defer { try? server.stop() }

    let (_, json) = try await apiRequest(method: "GET", path: "/api/models", port: port)
    let models = json["models"] as? [[String: Any]]
    let m = models?.first
    #expect(m?["command"] == nil)
    #expect(m?["workDir"] == nil)
    #expect(m?["env"] == nil)
}

// MARK: - 禁止的配置写入接口

@Test("POST /api/models 不被注册")
func postModelsDisallowed() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, _) = try await apiRequest(method: "POST", path: "/api/models", port: port)
    #expect(status != 200, "POST /api/models 不应返回成功")
}

@Test("PUT /api/models/:id 不被注册")
func putModelDisallowed() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, _) = try await apiRequest(
        method: "PUT",
        path: "/api/models/00000000-0000-0000-0000-000000000000",
        port: port
    )
    #expect(status != 200, "PUT /api/models/:id 不应返回成功")
}

@Test("DELETE /api/models/:id 不被注册")
func deleteModelDisallowed() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, _) = try await apiRequest(
        method: "DELETE",
        path: "/api/models/00000000-0000-0000-0000-000000000000",
        port: port
    )
    #expect(status != 200, "DELETE /api/models/:id 不应返回成功")
}

// MARK: - 生命周期控制

@Test("POST /api/models/:id/start 启动模型并返回状态")
func startViaAPI() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "API-Start", command: "sleep 10", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
    #expect(json["status"] as? String == "running")
}

@Test("POST /api/models/:id/stop 停止模型")
func stopViaAPI() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "API-Stop", command: "sleep 60", to: store)
    try server.start()
    defer { try? server.stop() }

    // 先启动
    _ = try pm.start(config: model)

    // 通过 API 停止
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/stop",
        port: port
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
    #expect(json["status"] as? String == "stopped")
    #expect(pm.status(for: model.id) == .stopped)
}

@Test("POST /api/models/:id/restart 重启模型")
func restartViaAPI() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "API-Restart", command: "sleep 30", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    // 先启动
    _ = try pm.start(config: model)
    let pid1 = pm.pid(for: model.id)

    // 通过 API 重启
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/restart",
        port: port
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)

    let pid2 = pm.pid(for: model.id)
    #expect(pid2 != pid1, "重启后应是新进程")
}

// MARK: - 日志

@Test("GET /api/models/:id/logs 返回日志数组")
func logsViaAPI() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "API-Logs", command: "echo hello-world", to: store)
    try server.start()
    defer { try? server.stop() }

    _ = try pm.start(config: model)
    try await Task.sleep(nanoseconds: 200_000_000)

    let (status, json) = try await apiRequest(
        method: "GET",
        path: "/api/models/\(model.id.uuidString)/logs",
        port: port
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)

    let logs = json["logs"] as? [[String: Any]]
    #expect(logs != nil)
    #expect(logs!.contains(where: { ($0["message"] as? String) == "hello-world" }))
}

@Test("POST /api/models/:id/logs/clear 清空日志")
func clearLogsViaAPI() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "API-ClearLogs", command: "echo some-log", to: store)
    try server.start()
    defer { try? server.stop() }

    _ = try pm.start(config: model)
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(!pm.logs(for: model.id).isEmpty)

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/logs/clear",
        port: port
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
    #expect(pm.logs(for: model.id).isEmpty)
}

// MARK: - 错误格式

@Test("错误响应遵循统一 JSON 格式")
func errorResponseFormat() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "GET",
        path: "/api/models/nonexistent",
        port: port
    )
    #expect(status == 404)
    #expect(json["ok"] as? Bool == false)
    let error = json["error"] as? [String: Any]
    #expect(error != nil)
    #expect(error?["code"] is String)
    #expect(error?["message"] is String)
}
