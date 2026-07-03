import Foundation

/// 模型配置实体。command 保存完整启动命令字符串，不拆分 executable 和 arguments。
public struct ModelConfig: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var engine: Engine
    /// 启动命令字符串（launchMode == .command 时使用）。
    public var command: String
    public var workDir: String?
    public var env: [String: String]
    public var port: Int?
    public var createdAt: Date
    public var updatedAt: Date
    /// 启动模式，旧配置缺失时默认为 .command。
    public var launchMode: LaunchMode
    /// Python 脚本配置，launchMode == .pythonScript 时生效。
    public var pythonScript: PythonScriptConfig?

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, name, engine, command, workDir, env, port
        case createdAt, updatedAt
        case launchMode, pythonScript
    }

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        name: String,
        engine: Engine,
        command: String,
        workDir: String? = nil,
        env: [String: String] = [:],
        port: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        launchMode: LaunchMode = .command,
        pythonScript: PythonScriptConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.engine = engine
        self.command = command
        self.workDir = workDir
        self.env = env
        self.port = port
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.launchMode = launchMode
        self.pythonScript = pythonScript
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        engine = try container.decode(Engine.self, forKey: .engine)
        command = try container.decode(String.self, forKey: .command)
        workDir = try container.decodeIfPresent(String.self, forKey: .workDir)
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // 向后兼容：旧配置缺少 launchMode 时默认 .command
        launchMode = try container.decodeIfPresent(LaunchMode.self, forKey: .launchMode) ?? .command
        pythonScript = try container.decodeIfPresent(PythonScriptConfig.self, forKey: .pythonScript)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(engine, forKey: .engine)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(workDir, forKey: .workDir)
        if !env.isEmpty { try container.encode(env, forKey: .env) }
        try container.encodeIfPresent(port, forKey: .port)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(launchMode, forKey: .launchMode)
        try container.encodeIfPresent(pythonScript, forKey: .pythonScript)
    }

    // MARK: - 命令生成

    /// 根据启动模式生成最终执行命令。
    public func effectiveCommand() -> String {
        switch launchMode {
        case .command:
            return command
        case .pythonScript:
            guard let script = pythonScript, !script.scriptPath.isEmpty else {
                return command
            }
            let py = script.pythonExecutable ?? "python3"
            var parts = [py, script.scriptPath]
            parts.append(contentsOf: script.arguments)
            return parts.joined(separator: " ")
        }
    }

    /// 根据启动模式获取有效工作目录。
    public func effectiveWorkDir() -> String? {
        switch launchMode {
        case .command:
            return workDir
        case .pythonScript:
            return pythonScript?.workDir ?? workDir
        }
    }

    /// 根据启动模式获取合并后的环境变量。
    public func effectiveEnv() -> [String: String] {
        var result = env
        if launchMode == .pythonScript, let scriptEnv = pythonScript?.env {
            result.merge(scriptEnv) { _, new in new }
        }
        return result
    }
}
