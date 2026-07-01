import Foundation

// MARK: - 模型摘要（不包含 command、workDir、env）

/// API 返回的模型运行摘要。
/// 遵循公共 API 契约：不暴露 command、workDir、env。
public struct ModelSummary: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let engine: Engine
    public let port: Int?
    public let status: ModelStatus
    public let pid: Int32?
    public let baseUrl: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(from config: ModelConfig, status: ModelStatus, pid: Int32?) {
        self.id = config.id
        self.name = config.name
        self.engine = config.engine
        self.port = config.port
        self.status = status
        self.pid = pid
        self.baseUrl = config.port.map { "http://127.0.0.1:\($0)" }
        self.createdAt = config.createdAt
        self.updatedAt = config.updatedAt
    }
}

// MARK: - 统一成功响应

public struct SuccessResponse: Codable, Sendable {
    public let ok: Bool
    public var status: String?
    public var pid: Int32?
    public var models: [ModelSummary]?
    public var model: ModelSummary?
    public var logs: [ModelLogEntry]?

    public init(ok: Bool = true) {
        self.ok = ok
    }

    public static func models(_ list: [ModelSummary]) -> SuccessResponse {
        var resp = SuccessResponse()
        resp.models = list
        return resp
    }

    public static func model(_ summary: ModelSummary) -> SuccessResponse {
        var resp = SuccessResponse()
        resp.model = summary
        return resp
    }

    public static func started(status: String, pid: Int32) -> SuccessResponse {
        var resp = SuccessResponse()
        resp.status = status
        resp.pid = pid
        return resp
    }

    public static func stopped() -> SuccessResponse {
        var resp = SuccessResponse()
        resp.status = "stopped"
        return resp
    }

    public static func logs(_ entries: [ModelLogEntry]) -> SuccessResponse {
        var resp = SuccessResponse()
        resp.logs = entries
        return resp
    }
}

// MARK: - 统一错误响应

public struct ErrorDetail: Codable, Sendable {
    public let code: String
    public let message: String
}

public struct ErrorResponse: Codable, Sendable {
    public let ok: Bool
    public let error: ErrorDetail

    public init(code: String, message: String) {
        self.ok = false
        self.error = ErrorDetail(code: code, message: message)
    }
}

// MARK: - API 统一响应类型

public enum APIResponse: Sendable {
    case success(SuccessResponse)
    case error(ErrorResponse)
}
