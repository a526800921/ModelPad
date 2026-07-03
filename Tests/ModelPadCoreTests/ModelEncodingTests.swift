import Foundation
import Testing

@testable import ModelPadCore

// MARK: - Engine 编解码

@Test("Engine rawValue 编解码往返")
func engineRawValueRoundtrip() throws {
    for engine in Engine.allCases {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(engine)
        let decoded = try decoder.decode(Engine.self, from: data)
        #expect(decoded == engine)
    }
}

@Test("Engine 从合法 JSON 字符串解码")
func engineDecodeFromValidJSON() throws {
    let json = #""ollama""#
    let data = json.data(using: .utf8)!
    let engine = try JSONDecoder().decode(Engine.self, from: data)
    #expect(engine == .ollama)
}

@Test("Engine 从非法字符串解码失败")
func engineDecodeFromInvalidJSON() {
    let json = #""unknown_engine""#
    let data = json.data(using: .utf8)!
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(Engine.self, from: data)
    }
}

// MARK: - ModelStatus 编解码

@Test("ModelStatus rawValue 编解码往返")
func modelStatusRawValueRoundtrip() throws {
    let statuses: [ModelStatus] = [.stopped, .starting, .running, .error]
    for status in statuses {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(status)
        let decoded = try decoder.decode(ModelStatus.self, from: data)
        #expect(decoded == status)
    }
}

@Test("ModelStatus 从合法 JSON 字符串解码")
func modelStatusDecodeFromValidJSON() throws {
    let json = #""running""#
    let data = json.data(using: .utf8)!
    let status = try JSONDecoder().decode(ModelStatus.self, from: data)
    #expect(status == .running)
}

// MARK: - LogStream 编解码

@Test("LogStream rawValue 编解码往返")
func logStreamRawValueRoundtrip() throws {
    let streams: [LogStream] = [.stdout, .stderr, .system]
    for stream in streams {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(stream)
        let decoded = try decoder.decode(LogStream.self, from: data)
        #expect(decoded == stream)
    }
}

// MARK: - ModelConfig 编解码

@Test("ModelConfig JSON 编解码往返")
func modelConfigRoundtrip() throws {
    let config = ModelConfig(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Qwen-7B",
        engine: .ollama,
        command: "ollama serve",
        workDir: nil,
        env: [:],
        port: 11434,
        createdAt: ISO8601DateFormatter().date(from: "2026-06-30T12:00:00Z")!,
        updatedAt: ISO8601DateFormatter().date(from: "2026-06-30T12:00:00Z")!
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(config)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ModelConfig.self, from: data)

    #expect(decoded.id == config.id)
    #expect(decoded.name == config.name)
    #expect(decoded.engine == config.engine)
    #expect(decoded.command == config.command)
    #expect(decoded.workDir == config.workDir)
    #expect(decoded.env == config.env)
    #expect(decoded.port == config.port)
    #expect(decoded.createdAt == config.createdAt)
    #expect(decoded.updatedAt == config.updatedAt)
}

@Test("ModelConfig 可选字段 nil 可以正确编解码")
func modelConfigNilOptionalFields() throws {
    let config = ModelConfig(
        name: "Minimal",
        engine: .custom,
        command: "echo hello"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(config)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ModelConfig.self, from: data)

    #expect(decoded.workDir == nil)
    #expect(decoded.port == nil)
}

@Test("ModelConfig 部分 JSON key 缺失时解码失败")
func modelConfigDecodeFailsOnMissingKeys() {
    // 缺少 command 字段
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "name": "Test",
      "engine": "ollama",
      "port": 11434
    }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(throws: (any Error).self) {
        try decoder.decode(ModelConfig.self, from: data)
    }
}

// MARK: - ModelLogEntry 编解码

@Test("ModelLogEntry JSON 编解码往返")
func modelLogEntryRoundtrip() throws {
    let formatter = ISO8601DateFormatter()
    let entry = ModelLogEntry(
        time: formatter.date(from: "2026-06-30T12:00:00Z")!,
        stream: .stdout,
        message: "server listening on 11434"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(entry)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ModelLogEntry.self, from: data)

    #expect(decoded.time == entry.time)
    #expect(decoded.stream == entry.stream)
    #expect(decoded.message == entry.message)
}

// MARK: - PythonScriptConfig 编解码

@Test("PythonScriptConfig JSON 编解码往返")
func pythonScriptConfigRoundtrip() throws {
    let config = PythonScriptConfig(
        scriptPath: "/home/user/run.py",
        arguments: ["--port", "8080", "--verbose"],
        pythonExecutable: "/usr/local/bin/python3.12",
        workDir: "/home/user/project",
        env: ["PYTHONPATH": "/home/user/lib", "MODEL_DIR": "/data/models"]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(PythonScriptConfig.self, from: data)

    #expect(decoded.scriptPath == config.scriptPath)
    #expect(decoded.arguments == config.arguments)
    #expect(decoded.pythonExecutable == config.pythonExecutable)
    #expect(decoded.workDir == config.workDir)
    #expect(decoded.env == config.env)
}

@Test("PythonScriptConfig 可选字段 nil 可以正确编解码")
func pythonScriptConfigNilOptionalFields() throws {
    let config = PythonScriptConfig(scriptPath: "/tmp/test.py")

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(PythonScriptConfig.self, from: data)

    #expect(decoded.scriptPath == "/tmp/test.py")
    #expect(decoded.arguments == [])
    #expect(decoded.pythonExecutable == nil)
    #expect(decoded.workDir == nil)
    #expect(decoded.env == [:])
}

// MARK: - LaunchMode 编解码

@Test("LaunchMode 编解码往返")
func launchModeRoundtrip() throws {
    for mode in LaunchMode.allCases {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(mode)
        let decoded = try decoder.decode(LaunchMode.self, from: data)
        #expect(decoded == mode)
    }
}

// MARK: - ModelConfig 向后兼容

@Test("旧版只含 command 的配置可以正常解码（缺少 launchMode 和 pythonScript）")
func modelConfigDecodeLegacyCommandOnly() throws {
    // 模拟阶段 1 旧配置 JSON（无 launchMode/pythonScript）
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "name": "Qwen-7B",
      "engine": "ollama",
      "command": "ollama serve",
      "port": 11434,
      "createdAt": "2026-06-30T12:00:00Z",
      "updatedAt": "2026-06-30T12:00:00Z"
    }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let config = try decoder.decode(ModelConfig.self, from: data)

    #expect(config.name == "Qwen-7B")
    #expect(config.engine == .ollama)
    #expect(config.command == "ollama serve")
    #expect(config.launchMode == .command)
    #expect(config.pythonScript == nil)
}

@Test("ModelConfig 含 Python 脚本配置的完整编解码往返")
func modelConfigWithPythonScriptRoundtrip() throws {
    let config = ModelConfig(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Custom-Python",
        engine: .custom,
        command: "",
        workDir: "/home/user",
        env: ["GLOBAL": "1"],
        port: 8080,
        createdAt: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!,
        updatedAt: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!,
        launchMode: .pythonScript,
        pythonScript: PythonScriptConfig(
            scriptPath: "run.py",
            arguments: ["--verbose"],
            pythonExecutable: nil,
            workDir: nil,
            env: ["SCRIPT_VAR": "x"]
        )
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(config)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ModelConfig.self, from: data)

    #expect(decoded.name == "Custom-Python")
    #expect(decoded.launchMode == .pythonScript)
    #expect(decoded.pythonScript?.scriptPath == "run.py")
    #expect(decoded.pythonScript?.arguments == ["--verbose"])
    #expect(decoded.pythonScript?.pythonExecutable == nil)
    #expect(decoded.env == ["GLOBAL": "1"])
}

// MARK: - effectiveCommand / effectiveWorkDir / effectiveEnv

@Test("effectiveCommand command 模式直接返回 command 字符串")
func effectiveCommandCommandMode() {
    let config = ModelConfig(name: "test", engine: .custom, command: "echo hello")
    #expect(config.effectiveCommand() == "echo hello")
}

@Test("effectiveCommand pythonScript 模式拼接命令")
func effectiveCommandPythonScriptMode() {
    var config = ModelConfig(name: "test", engine: .custom, command: "", launchMode: .pythonScript)
    config.pythonScript = PythonScriptConfig(
        scriptPath: "/app/start.py",
        arguments: ["--port", "8080"],
        pythonExecutable: "python3.12"
    )
    #expect(config.effectiveCommand() == "python3.12 /app/start.py --port 8080")
}

@Test("effectiveCommand pythonScript 模式使用默认 python3")
func effectiveCommandPythonScriptDefaultPython() {
    var config = ModelConfig(name: "test", engine: .custom, command: "", launchMode: .pythonScript)
    config.pythonScript = PythonScriptConfig(scriptPath: "run.py")
    #expect(config.effectiveCommand() == "python3 run.py")
}

@Test("effectiveCommand pythonScript 模式无脚本配置时回退到 command")
func effectiveCommandPythonScriptFallback() {
    let config = ModelConfig(name: "test", engine: .custom, command: "fallback cmd", launchMode: .pythonScript)
    #expect(config.effectiveCommand() == "fallback cmd")
}

@Test("effectiveWorkDir command 模式返回模型级 workDir")
func effectiveWorkDirCommandMode() {
    let config = ModelConfig(name: "test", engine: .custom, command: "", workDir: "/tmp")
    #expect(config.effectiveWorkDir() == "/tmp")
}

@Test("effectiveWorkDir pythonScript 模式优先脚本级 workDir")
func effectiveWorkDirPythonScriptOverride() {
    var config = ModelConfig(name: "test", engine: .custom, command: "", workDir: "/model", launchMode: .pythonScript)
    config.pythonScript = PythonScriptConfig(scriptPath: "x.py", workDir: "/script")
    #expect(config.effectiveWorkDir() == "/script")
}

@Test("effectiveWorkDir pythonScript 脚本 workDir 为空时回退模型级")
func effectiveWorkDirPythonScriptFallback() {
    var config = ModelConfig(name: "test", engine: .custom, command: "", workDir: "/model", launchMode: .pythonScript)
    config.pythonScript = PythonScriptConfig(scriptPath: "x.py", workDir: nil)
    #expect(config.effectiveWorkDir() == "/model")
}

@Test("effectiveEnv pythonScript 模式合并脚本级 env")
func effectiveEnvPythonScriptMerge() {
    var config = ModelConfig(name: "test", engine: .custom, command: "", env: ["A": "1", "B": "2"], launchMode: .pythonScript)
    config.pythonScript = PythonScriptConfig(scriptPath: "x.py", env: ["B": "override", "C": "3"])
    let merged = config.effectiveEnv()
    #expect(merged["A"] == "1")
    #expect(merged["B"] == "override")
    #expect(merged["C"] == "3")
}

// MARK: - RuntimeModelState 默认值

@Test("RuntimeModelState 默认状态为 stopped")
func runtimeModelStateDefaults() {
    let state = RuntimeModelState()
    #expect(state.status == .stopped)
    #expect(state.pid == nil)
}
