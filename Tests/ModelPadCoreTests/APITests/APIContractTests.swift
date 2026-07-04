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
    let port = 22000 + Int.random(in: 0...4999)
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

@Suite(.serialized) struct APIContractTests {

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

// MARK: - 未知模型统一错误

@Test("POST /api/models/:id/stop 未知模型返回 model_not_found")
func stopUnknownModel() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/00000000-0000-0000-0000-000000000000/stop",
        port: port
    )
    #expect(status == 404)
    #expect(json["ok"] as? Bool == false)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "model_not_found")
}

@Test("GET /api/models/:id/logs 未知模型返回 model_not_found")
func logsUnknownModel() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "GET",
        path: "/api/models/00000000-0000-0000-0000-000000000000/logs",
        port: port
    )
    #expect(status == 404)
    #expect(json["ok"] as? Bool == false)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "model_not_found")
}

@Test("POST /api/models/:id/logs/clear 未知模型返回 model_not_found")
func clearLogsUnknownModel() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/00000000-0000-0000-0000-000000000000/logs/clear",
        port: port
    )
    #expect(status == 404)
    #expect(json["ok"] as? Bool == false)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "model_not_found")
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

// MARK: - 启动请求体环境变量覆盖

@Test("POST start 无请求体仍可启动（向后兼容）")
func startWithoutBodyStillWorks() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "NoBody", command: "sleep 10", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: nil
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
    #expect(json["status"] as? String == "running")
}

@Test("POST start 空 JSON 对象保持当前启动行为")
func startWithEmptyJSONBody() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "EmptyJSON", command: "sleep 10", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = "{}".data(using: .utf8)!
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
}

@Test("POST start env 覆盖持久化 config 中的同名变量")
func startEnvOverrideWinsOverConfigEnv() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = ModelConfig(
        name: "EnvOverride",
        engine: .custom,
        command: "echo $TEST_VAR",
        env: ["TEST_VAR": "from-config"]
    )
    var appConfig = try store.load()
    appConfig.models.append(model)
    try store.save(appConfig)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = try JSONSerialization.data(withJSONObject: ["env": ["TEST_VAR": "from-request"]])
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)

    // 等待进程输出
    try await Task.sleep(nanoseconds: 300_000_000)
    let logs = pm.logs(for: model.id)
    #expect(logs.contains(where: { $0.message == "from-request" }),
            "应使用请求体覆盖的环境变量")
    #expect(!logs.contains(where: { $0.message == "from-config" }),
            "不应使用 config 中的原有环境变量")
}

@Test("POST start 请求体 env 未持久化到 config.json")
func startEnvOverrideNotPersisted() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "NoPersist", command: "sleep 10", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = try JSONSerialization.data(withJSONObject: ["env": ["TEMP_KEY": "temp-value"]])
    let (status, _) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 200)

    // 重新读取 config.json
    let reloaded = try store.load()
    let reloadedModel = reloaded.models.first(where: { $0.id == model.id })
    #expect(reloadedModel != nil)
    #expect(reloadedModel!.env["TEMP_KEY"] == nil,
            "请求体 env 不应被持久化到 config.json")
    #expect(reloadedModel!.env.isEmpty || reloadedModel!.env == [:],
            "config.json 中的 env 应保持原状")
}

@Test("POST start 非法 JSON 返回 invalid_request 且不启动")
func startInvalidJSONReturns400() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "BadJSON", command: "sleep 60", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = "not-json".data(using: .utf8)!
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 400)
    #expect(json["ok"] as? Bool == false)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "invalid_request")

    // 模型不应被启动
    #expect(pm.status(for: model.id) == .stopped)
}

@Test("POST start env 为非对象时返回 invalid_request")
func startEnvNotObjectReturns400() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "BadEnv", command: "sleep 60", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = try JSONSerialization.data(withJSONObject: ["env": "not-an-object"])
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 400)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "invalid_request")

    #expect(pm.status(for: model.id) == .stopped)
}

@Test("POST start env 包含空 key 返回 invalid_request")
func startEnvEmptyKeyReturns400() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "EmptyKey", command: "sleep 60", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = try JSONSerialization.data(withJSONObject: ["env": ["": "value"]])
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 400)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "invalid_request")

    #expect(pm.status(for: model.id) == .stopped)
}

@Test("POST start env 值非字符串返回 invalid_request")
func startEnvNonStringValueReturns400() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "NonStrVal", command: "sleep 60", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = try JSONSerialization.data(withJSONObject: ["env": ["KEY": 123]])
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 400)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "invalid_request")

    #expect(pm.status(for: model.id) == .stopped)
}

@Test("GET /api/models 和 GET /api/models/:id 仍不返回 env")
func startEnvDoesNotLeakInSummary() async throws {
    let (server, store, _, port) = try makeTestServer()
    let model = try saveTestModel(named: "NoLeak", command: "echo hi", to: store)
    try server.start()
    defer { try? server.stop() }

    // 列表不泄露
    let (_, listJson) = try await apiRequest(method: "GET", path: "/api/models", port: port)
    let models = listJson["models"] as? [[String: Any]]
    #expect(models?.first?["env"] == nil)

    // 单模型不泄露
    let (_, getJson) = try await apiRequest(
        method: "GET",
        path: "/api/models/\(model.id.uuidString)",
        port: port
    )
    let m = getJson["model"] as? [String: Any]
    #expect(m?["env"] == nil)
}

@Test("POST start 空 env 对象保持当前行为")
func startEmptyEnvObject() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let model = try saveTestModel(named: "EmptyEnv", command: "sleep 10", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: model.id)
        try? server.stop()
    }

    let body = try JSONSerialization.data(withJSONObject: ["env": [String: String]()])
    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/models/\(model.id.uuidString)/start",
        port: port,
        body: body
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
    #expect(json["status"] as? String == "running")
}

// MARK: - POST /api/config/reload

@Test("POST /api/config/reload 成功返回刷新后的模型列表")
func configReloadReturnsModels() async throws {
    let (server, store, _, port) = try makeTestServer()
    _ = try saveTestModel(named: "ReloadTest", command: "echo hi", to: store)
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/config/reload",
        port: port
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)

    let models = json["models"] as? [[String: Any]]
    #expect(models?.count == 1)
    #expect(models?[0]["name"] as? String == "ReloadTest")
}

@Test("POST /api/config/reload 空配置返回空列表 200")
func configReloadEmptyConfig() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/config/reload",
        port: port
    )
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
    let models = json["models"] as? [[String: Any]]
    #expect(models?.isEmpty == true)
}

@Test("POST /api/config/reload 配置损坏返回 config_reload_failed")
func configReloadCorruptedConfig() async throws {
    let (server, store, _, port) = try makeTestServer()
    // 确保目录存在
    if !FileManager.default.fileExists(atPath: store.baseDirectory.path) {
        try FileManager.default.createDirectory(at: store.baseDirectory, withIntermediateDirectories: true)
    }
    // 破坏 config.json
    let fileURL = store.baseDirectory.appendingPathComponent("config.json")
    try "{ bad json".write(to: fileURL, atomically: true, encoding: .utf8)
    try server.start()
    defer { try? server.stop() }

    let (status, json) = try await apiRequest(
        method: "POST",
        path: "/api/config/reload",
        port: port
    )
    #expect(status == 400)
    #expect(json["ok"] as? Bool == false)
    let error = json["error"] as? [String: Any]
    #expect(error?["code"] as? String == "config_reload_failed")
}

@Test("POST /api/config/reload 不修改磁盘配置")
func configReloadDoesNotMutateConfig() async throws {
    let (server, store, _, port) = try makeTestServer()
    let model = try saveTestModel(named: "Original", command: "echo hi", to: store)
    try server.start()
    defer { try? server.stop() }

    _ = try await apiRequest(method: "POST", path: "/api/config/reload", port: port)

    // 验证配置未被修改
    let config = try store.load()
    #expect(config.models.count == 1)
    #expect(config.models[0].id == model.id)
}

@Test("POST /api/config/reload 不启停任何模型进程")
func configReloadDoesNotStartOrStopProcesses() async throws {
    let (server, store, pm, port) = try makeTestServer()
    let running = try saveTestModel(named: "Running", command: "sleep 60", to: store)
    let stopped = try saveTestModel(named: "Stopped", command: "sleep 10", to: store)
    try server.start()
    defer {
        _ = pm.stop(modelId: running.id)
        try? server.stop()
    }

    // 只启动 running
    _ = try pm.start(config: running)
    #expect(pm.status(for: running.id) == .running)
    #expect(pm.status(for: stopped.id) == .stopped)

    _ = try await apiRequest(method: "POST", path: "/api/config/reload", port: port)

    // 刷新后进程状态不变
    #expect(pm.status(for: running.id) == .running, "刷新不应停止运行中模型")
    #expect(pm.status(for: stopped.id) == .stopped, "刷新不应启动已停止模型")
}

@Test("POST /api/config/reload 不暴露敏感字段")
func configReloadExcludesSensitiveFields() async throws {
    let (server, store, _, port) = try makeTestServer()
    _ = try saveTestModel(named: "Safe", command: "secret", to: store)
    try server.start()
    defer { try? server.stop() }

    let (_, json) = try await apiRequest(method: "POST", path: "/api/config/reload", port: port)
    let models = json["models"] as? [[String: Any]]
    let m = models?.first
    #expect(m?["command"] == nil)
    #expect(m?["workDir"] == nil)
    #expect(m?["env"] == nil)
}

// MARK: - 既有 API 回归

@Test("reload 后 GET /api/models 列表与刷新响应一致")
func listModelsMatchesReloadResponse() async throws {
    let (server, store, _, port) = try makeTestServer()
    _ = try saveTestModel(named: "Consistent", command: "echo hi", to: store)
    try server.start()
    defer { try? server.stop() }

    let (_, reloadJson) = try await apiRequest(method: "POST", path: "/api/config/reload", port: port)
    let (_, listJson) = try await apiRequest(method: "GET", path: "/api/models", port: port)

    let reloadModels = reloadJson["models"] as? [[String: Any]]
    let listModels = listJson["models"] as? [[String: Any]]

    #expect(reloadModels?.count == listModels?.count)
    #expect(reloadModels?[0]["name"] as? String == listModels?[0]["name"] as? String)
    #expect(reloadModels?[0]["id"] as? String == listModels?[0]["id"] as? String)
}

@Test("reload 后既有端点 GET /api/health 仍正常")
func healthStillWorksAfterReload() async throws {
    let (server, _, _, port) = try makeTestServer()
    try server.start()
    defer { try? server.stop() }

    _ = try await apiRequest(method: "POST", path: "/api/config/reload", port: port)

    let (status, json) = try await apiRequest(method: "GET", path: "/api/health", port: port)
    #expect(status == 200)
    #expect(json["ok"] as? Bool == true)
}

} // APIContractTests
