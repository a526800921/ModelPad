import Foundation

/// 配置持久化存储，负责 JSON 读写、原子写入和损坏文件备份。
public final class ConfigStore: Sendable {

    // MARK: - 目录

    /// 配置根目录。
    public let baseDirectory: URL

    /// 默认配置目录：~/Library/Application Support/ModelPad/
    public static let defaultBaseDirectory: URL = {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ModelPad", isDirectory: true)
    }()

    /// 使用默认目录创建。
    public static let shared = ConfigStore(baseDirectory: defaultBaseDirectory)

    // MARK: - 路径计算

    private var configFileURL: URL {
        baseDirectory.appendingPathComponent("config.json")
    }

    private var tempFileURL: URL {
        baseDirectory.appendingPathComponent("config.json.tmp")
    }

    private var backupFileURL: URL {
        baseDirectory.appendingPathComponent("config.json.bak")
    }

    // MARK: - 初始化

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // MARK: - 便利静态方法

    /// 配置文件目录：~/Library/Application Support/ModelPad/
    public static func configDirectory() -> URL {
        defaultBaseDirectory
    }

    /// 配置文件路径：~/Library/Application Support/ModelPad/config.json
    public static func configFilePath() -> URL {
        shared.configFileURL
    }

    /// 使用默认目录读取。
    public static func load() throws -> AppConfig {
        try shared.load()
    }

    /// 使用默认目录保存。
    public static func save(_ config: AppConfig) throws {
        try shared.save(config)
    }

    // MARK: - 读取

    /// 读取配置。文件不存在时返回默认空配置。
    /// JSON 损坏时备份原文件并降级为空配置。
    public func load() throws -> AppConfig {
        let fileURL = configFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // 文件存在但无法读取，返回默认配置
            return .default
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            // JSON 损坏：备份原文件
            backupCorruptedFile(at: fileURL)
            // 降级为空配置
            return .default
        }
    }

    // MARK: - 写入

    /// 原子保存配置：先写临时文件，再 rename 覆盖目标文件。
    public func save(_ config: AppConfig) throws {
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: baseDirectory.path) {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)

        let tempURL = tempFileURL
        let targetURL = configFileURL

        // 先写临时文件（不使用 .atomic，因为后续会手动 rename）
        try data.write(to: tempURL)

        // 再 rename 覆盖目标文件
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: targetURL)
    }

    // MARK: - 损坏备份

    /// 将损坏的配置文件重命名为 .bak。
    private func backupCorruptedFile(at fileURL: URL) {
        let backupURL = backupFileURL

        // 如果已有旧备份，先删除
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }

        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    // MARK: - 重置

    /// 删除配置目录（测试辅助）。
    public func reset() throws {
        if FileManager.default.fileExists(atPath: baseDirectory.path) {
            try FileManager.default.removeItem(at: baseDirectory)
        }
    }

    /// 使用默认目录重置（测试辅助）。
    public static func reset() throws {
        try shared.reset()
    }
}
