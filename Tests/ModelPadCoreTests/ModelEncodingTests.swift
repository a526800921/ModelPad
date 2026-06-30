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

// MARK: - RuntimeModelState 默认值

@Test("RuntimeModelState 默认状态为 stopped")
func runtimeModelStateDefaults() {
    let state = RuntimeModelState()
    #expect(state.status == .stopped)
    #expect(state.pid == nil)
}
