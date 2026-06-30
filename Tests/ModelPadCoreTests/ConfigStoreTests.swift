import Foundation
import Testing

@testable import ModelPadCore

// MARK: - 辅助

/// 创建使用独立临时目录的 ConfigStore。
func makeTestStore() -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ModelPadTest-\(UUID().uuidString)")
    return ConfigStore(baseDirectory: tempDir)
}

// MARK: - 默认配置

@Test("默认配置版本号为 1")
func defaultConfigVersion() {
    let config = AppConfig.default
    #expect(config.version == 1)
}

@Test("默认配置 API 启用且监听 127.0.0.1:9786")
func defaultConfigApi() {
    let config = AppConfig.default
    #expect(config.api.enabled == true)
    #expect(config.api.host == "127.0.0.1")
    #expect(config.api.port == 9786)
}

@Test("默认配置模型列表为空")
func defaultConfigModelsEmpty() {
    let config = AppConfig.default
    #expect(config.models.isEmpty)
}

// MARK: - AppConfig 编解码

@Test("AppConfig JSON 编解码往返")
func appConfigRoundtrip() throws {
    let formatter = ISO8601DateFormatter()
    let model = ModelConfig(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Qwen-7B",
        engine: .ollama,
        command: "ollama serve",
        workDir: nil,
        env: [:],
        port: 11434,
        createdAt: formatter.date(from: "2026-06-30T12:00:00Z")!,
        updatedAt: formatter.date(from: "2026-06-30T12:00:00Z")!
    )

    let config = AppConfig(
        version: 1,
        api: ApiConfig(enabled: true, host: "127.0.0.1", port: 9786),
        models: [model]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(config)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(AppConfig.self, from: data)

    #expect(decoded.version == config.version)
    #expect(decoded.api.enabled == config.api.enabled)
    #expect(decoded.api.host == config.api.host)
    #expect(decoded.api.port == config.api.port)
    #expect(decoded.models.count == 1)
    #expect(decoded.models[0].id == model.id)
    #expect(decoded.models[0].name == model.name)
    #expect(decoded.models[0].command == model.command)
}

// MARK: - 配置保存和读取

@Test("保存空配置后能正确读取")
func saveAndLoadEmptyConfig() throws {
    let store = makeTestStore()

    let config = AppConfig.default
    try store.save(config)

    let loaded = try store.load()
    #expect(loaded.version == config.version)
    #expect(loaded.models.isEmpty)
    #expect(loaded.api.port == 9786)
}

@Test("保存含模型配置后能正确读取")
func saveAndLoadConfigWithModels() throws {
    let store = makeTestStore()

    let model = ModelConfig(
        name: "TestModel",
        engine: .vllm,
        command: "python -m vllm",
        port: 8000
    )
    let config = AppConfig(version: 1, api: .default, models: [model])
    try store.save(config)

    let loaded = try store.load()
    #expect(loaded.models.count == 1)
    #expect(loaded.models[0].name == "TestModel")
    #expect(loaded.models[0].engine == .vllm)
    #expect(loaded.models[0].port == 8000)
}

@Test("文件不存在时 load 返回默认配置")
func loadReturnsDefaultWhenFileNotExists() throws {
    let store = makeTestStore()

    let config = try store.load()
    #expect(config.version == 1)
    #expect(config.api.enabled == true)
    #expect(config.models.isEmpty)
}

// MARK: - 原子写入

@Test("原子写入后临时文件不存在")
func atomicWriteNoTempFileLeftBehind() throws {
    let store = makeTestStore()

    let config = AppConfig.default
    try store.save(config)

    // 临时文件不应存在（通过 baseDirectory 查找）
    let dirContents = try FileManager.default.contentsOfDirectory(
        at: store.baseDirectory,
        includingPropertiesForKeys: nil
    )
    let tempFiles = dirContents.filter { $0.lastPathComponent.hasSuffix(".tmp") }
    #expect(tempFiles.isEmpty, "原子写入后不应残留 .tmp 文件")

    // 目标文件应存在
    let configFiles = dirContents.filter { $0.lastPathComponent == "config.json" }
    #expect(configFiles.count == 1, "config.json 应存在")
}

@Test("两次连续保存配置正确")
func twoConsecutiveSaves() throws {
    let store = makeTestStore()

    // 第一次保存
    let config1 = AppConfig.default
    try store.save(config1)

    // 第二次保存（带模型）
    let model = ModelConfig(name: "M2", engine: .ollama, command: "ollama serve")
    let config2 = AppConfig(version: 1, api: .default, models: [model])
    try store.save(config2)

    let loaded = try store.load()
    #expect(loaded.models.count == 1)
    #expect(loaded.models[0].name == "M2")
}

// MARK: - 损坏 JSON 备份

@Test("损坏 JSON 文件被备份并降级为空配置")
func corruptedJSONBacksUpAndFallsBack() throws {
    let store = makeTestStore()

    // 先确保目录存在
    let dir = store.baseDirectory
    if !FileManager.default.fileExists(atPath: dir.path) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // 写入损坏的 JSON
    let corruptData = "{ this is not valid json }".data(using: .utf8)!
    let configFile = dir.appendingPathComponent("config.json")
    try corruptData.write(to: configFile)

    // 加载应返回默认配置
    let config = try store.load()
    #expect(config.version == 1)
    #expect(config.models.isEmpty)

    // 检查备份文件是否生成
    let backupFile = dir.appendingPathComponent("config.json.bak")
    let bakExists = FileManager.default.fileExists(atPath: backupFile.path)
    #expect(bakExists, "损坏的配置文件应被备份为 .bak")

    // 原始损坏文件应已被移走
    #expect(!FileManager.default.fileExists(atPath: configFile.path),
            "损坏的源文件应已被移走")
}

@Test("正常 JSON 读取不会生成备份")
func validJSONDoesNotCreateBackup() throws {
    let store = makeTestStore()

    // 保存正常配置
    try store.save(AppConfig.default)

    // 读取正常配置
    let _ = try store.load()

    // 不应有备份文件
    let backupFile = store.baseDirectory.appendingPathComponent("config.json.bak")
    let bakExists = FileManager.default.fileExists(atPath: backupFile.path)
    #expect(!bakExists, "正常 JSON 不应生成备份文件")
}
