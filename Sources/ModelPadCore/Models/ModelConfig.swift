import Foundation

/// 模型配置实体。command 保存完整启动命令字符串，不拆分 executable 和 arguments。
public struct ModelConfig: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var engine: Engine
    public var command: String
    public var workDir: String?
    public var env: [String: String]
    public var port: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        engine: Engine,
        command: String,
        workDir: String? = nil,
        env: [String: String] = [:],
        port: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
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
    }
}
