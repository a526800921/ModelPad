import Foundation
import Testing

@testable import ModelPadCore

// MARK: - 辅助

/// 创建使用独立临时目录的 ConfigStore。
func makeCorruptedTestStore() -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ModelPadCorruptTest-\(UUID().uuidString)")
    return ConfigStore(baseDirectory: tempDir)
}

// MARK: - 损坏备份内容验证

@Test("损坏备份文件保留原始损坏内容")
func backupPreservesCorruptedContent() throws {
    let store = makeCorruptedTestStore()

    // 先确保目录存在
    let dir = store.baseDirectory
    if !FileManager.default.fileExists(atPath: dir.path) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // 写入损坏的 JSON
    let corruptContent = "{ this is not valid json }"
    let configFile = dir.appendingPathComponent("config.json")
    try corruptContent.write(to: configFile, atomically: true, encoding: .utf8)

    // 触发加载和备份
    let _ = try store.load()

    // 验证备份内容
    let backupFile = dir.appendingPathComponent("config.json.bak")
    #expect(FileManager.default.fileExists(atPath: backupFile.path))

    let backedUpContent = try String(contentsOf: backupFile, encoding: .utf8)
    #expect(backedUpContent == corruptContent,
            "备份文件应保留原始损坏内容")
}

@Test("二次损坏会覆盖旧备份")
func secondCorruptionOverwritesOldBackup() throws {
    let store = makeCorruptedTestStore()

    let dir = store.baseDirectory
    if !FileManager.default.fileExists(atPath: dir.path) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // 第一次损坏
    let corrupt1 = "{ first corrupt }"
    let configFile = dir.appendingPathComponent("config.json")
    try corrupt1.write(to: configFile, atomically: true, encoding: .utf8)
    let _ = try store.load()

    // 验证第一次备份
    let backupFile = dir.appendingPathComponent("config.json.bak")
    #expect(FileManager.default.fileExists(atPath: backupFile.path))
    let backup1 = try String(contentsOf: backupFile, encoding: .utf8)
    #expect(backup1 == corrupt1)

    // 第二次损坏（写入新损坏内容）
    let corrupt2 = "{ second corrupt }"
    try corrupt2.write(to: configFile, atomically: true, encoding: .utf8)
    let _ = try store.load()

    // 验证第二次备份覆盖了第一次
    let backup2 = try String(contentsOf: backupFile, encoding: .utf8)
    #expect(backup2 == corrupt2,
            "第二次损坏应覆盖旧备份")
}

// MARK: - 降级后功能正常

@Test("损坏降级后仍可正常保存和读取新配置")
func canSaveAndLoadAfterCorruptionFallback() throws {
    let store = makeCorruptedTestStore()

    let dir = store.baseDirectory
    if !FileManager.default.fileExists(atPath: dir.path) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // 写入损坏 JSON
    let corruptData = "{ corrupt }".data(using: .utf8)!
    let configFile = dir.appendingPathComponent("config.json")
    try corruptData.write(to: configFile)

    // 加载降级为空配置
    let fallback = try store.load()
    #expect(fallback.models.isEmpty)

    // 保存新配置
    let model = ModelConfig(name: "Recovered", engine: .custom, command: "echo ok")
    let newConfig = AppConfig(version: 1, api: .default, models: [model])
    try store.save(newConfig)

    // 读取回来
    let loaded = try store.load()
    #expect(loaded.models.count == 1)
    #expect(loaded.models[0].name == "Recovered")
}

// MARK: - 深度编解码验证

@Test("编码后 JSON 结构与计划文档契约一致")
func encodedJSONMatchesContract() throws {
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
    let config = AppConfig(version: 1, api: .default, models: [model])

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(config)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    // 验证顶层结构
    #expect(json?["version"] as? Int == 1)
    #expect(json?["api"] != nil)
    #expect(json?["models"] != nil)

    // 验证 API 配置
    let api = json?["api"] as? [String: Any]
    #expect(api?["enabled"] as? Bool == true)
    #expect(api?["host"] as? String == "127.0.0.1")
    #expect(api?["port"] as? Int == 9999)

    // 验证模型配置
    let models = json?["models"] as? [[String: Any]]
    #expect(models?.count == 1)
    #expect(models?[0]["name"] as? String == "Qwen-7B")
    #expect(models?[0]["engine"] as? String == "ollama")
    #expect(models?[0]["command"] as? String == "ollama serve")
}
