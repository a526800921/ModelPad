import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOFoundationCompat

// MARK: - API Server

/// 本地 HTTP API 服务器，只监听 127.0.0.1。
public final class APIServer: @unchecked Sendable {

    private let host: String
    private let port: Int
    private let processManager: ModelProcessManager
    private let configStore: ConfigStore
    private let rootResponse: APIResponse

    /// API 启停操作后回调，用于通知 UI 刷新状态。
    public var onModelStateChanged: (@Sendable () -> Void)?

    /// 配置重载请求回调，由 App 层绑定到 AppViewModel.reloadModels()。
    public var onConfigReloadRequested: (@Sendable () -> Void)?

    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?

    public init(
        host: String = "127.0.0.1",
        port: Int = 9999,
        processManager: ModelProcessManager,
        configStore: ConfigStore,
        readmePath: String? = nil
    ) {
        self.host = host
        self.port = port
        self.processManager = processManager
        self.configStore = configStore
        self.rootResponse = Self.loadRootResponse(readmePath: readmePath)
    }

    /// 加载 GET / 响应内容：README 文件或降级文案。
    private static func loadRootResponse(readmePath: String?) -> APIResponse {
        if let path = readmePath,
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return .text(content)
        }
        return .text("ModelPad API Server is running.\n")
    }

    // MARK: - 生命周期

    public func start() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let store: ConfigStore = configStore
        let pm: ModelProcessManager = processManager
        let rootResp = rootResponse
        let stateChanged = self.onModelStateChanged
        let configReloaded = self.onConfigReloadRequested

        let bootstrap = ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                let handler = APIHandler(processManager: pm, configStore: store, rootResponse: rootResp)
                handler.onModelStateChanged = stateChanged
                handler.onConfigReloadRequested = configReloaded
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(handler)
                }
            }

        let opt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
        channel = try bootstrap
            .serverChannelOption(opt, value: 1)
            .bind(host: host, port: port)
            .wait()
    }

    public func stop() throws {
        try channel?.close().wait()
        try group?.syncShutdownGracefully()
        channel = nil
        group = nil
    }
}

// MARK: - HTTP Handler

private final class APIHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let processManager: ModelProcessManager
    private let configStore: ConfigStore
    private let rootResponse: APIResponse

    var onModelStateChanged: (@Sendable () -> Void)?
    var onConfigReloadRequested: (@Sendable () -> Void)?

    private var method: HTTPMethod = .GET
    private var path: String = ""
    private var bodyBuffer: ByteBuffer?

    /// 缓存的 OpenAPI 规范 JSON。
    private static let openapiSpec: Data = {
        let paths: [String: [String: Any]] = [
            "/api/health": [
                "get": specOperation(
                    summary: "健康检查",
                    description: "返回服务是否正常运行。",
                    response: ["ok": .bool]
                )
            ],
            "/api/models": [
                "get": specOperation(
                    summary: "模型列表",
                    description: "返回所有已配置模型的摘要信息（不含敏感字段）。",
                    response: [
                        "ok": .bool,
                        "models": .array(.ref("#/components/schemas/ModelSummary"))
                    ]
                )
            ],
            "/api/models/{id}": [
                "get": specOperation(
                    summary: "模型详情",
                    description: "查询单个模型的状态和配置摘要。",
                    parameters: [
                        ["name": "id", "in": "path", "required": true, "schema": ["type": "string"]]
                    ],
                    response: [
                        "ok": .bool,
                        "model": .ref("#/components/schemas/ModelSummary")
                    ]
                )
            ],
            "/api/models/{id}/start": [
                "post": specOperation(
                    summary: "启动模型",
                    description: "启动指定模型。可选请求体携带一次性环境变量覆盖。",
                    parameters: [
                        ["name": "id", "in": "path", "required": true, "schema": ["type": "string"]]
                    ],
                    requestBody: [
                        "content": [
                            "application/json": [
                                "schema": [
                                    "type": "object",
                                    "properties": [
                                        "env": [
                                            "type": "object",
                                            "additionalProperties": ["type": "string"],
                                            "description": "本次启动追加/覆盖的环境变量"
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ],
                    response: [
                        "ok": .bool,
                        "status": .string,
                        "pid": .int
                    ]
                )
            ],
            "/api/models/{id}/stop": [
                "post": specOperation(
                    summary: "停止模型",
                    description: "停止指定模型的进程。",
                    parameters: [
                        ["name": "id", "in": "path", "required": true, "schema": ["type": "string"]]
                    ],
                    response: ["ok": .bool]
                )
            ],
            "/api/models/{id}/restart": [
                "post": specOperation(
                    summary: "重启模型",
                    description: "重启指定模型进程。",
                    parameters: [
                        ["name": "id", "in": "path", "required": true, "schema": ["type": "string"]]
                    ],
                    response: [
                        "ok": .bool,
                        "status": .string,
                        "pid": .int
                    ]
                )
            ],
            "/api/models/{id}/logs": [
                "get": specOperation(
                    summary: "模型日志",
                    description: "获取指定模型的最新日志条目。",
                    parameters: [
                        ["name": "id", "in": "path", "required": true, "schema": ["type": "string"]]
                    ],
                    response: [
                        "ok": .bool,
                        "logs": .array(.ref("#/components/schemas/LogEntry"))
                    ]
                )
            ],
            "/api/models/{id}/logs/clear": [
                "post": specOperation(
                    summary: "清空日志",
                    description: "清空指定模型的日志缓冲区。",
                    parameters: [
                        ["name": "id", "in": "path", "required": true, "schema": ["type": "string"]]
                    ],
                    response: ["ok": .bool]
                )
            ],
            "/api/config/reload": [
                "post": specOperation(
                    summary: "重载配置",
                    description: "从配置文件重新加载模型列表（不重启进程）。",
                    response: [
                        "ok": .bool,
                        "models": .array(.ref("#/components/schemas/ModelSummary"))
                    ]
                )
            ]
        ]

        let spec: [String: Any] = [
            "openapi": "3.1.0",
            "info": [
                "title": "ModelPad API",
                "version": "1.0.0",
                "description": "ModelPad 本地 HTTP API — 管理本机模型服务进程的启停、状态查询和日志查看。"
            ],
            "servers": [
                ["url": "http://127.0.0.1:9999", "description": "本地开发服务器"]
            ],
            "paths": paths,
            "components": [
                "schemas": [
                    "ModelSummary": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string", "format": "uuid", "description": "模型 UUID"],
                            "name": ["type": "string", "description": "模型名称"],
                            "engine": ["type": "string", "description": "引擎类型 (ollama / llamacpp / vllm / custom / mlx)"],
                            "desc": ["type": "string", "nullable": true, "description": "模型用途描述"],
                            "port": ["type": "integer", "nullable": true, "description": "监听端口"],
                            "status": ["type": "string", "description": "运行状态 (running / stopped / error / starting)"],
                            "pid": ["type": "integer", "nullable": true, "description": "进程 PID"],
                            "baseUrl": ["type": "string", "nullable": true, "description": "服务地址"],
                            "createdAt": ["type": "string", "format": "date-time"],
                            "updatedAt": ["type": "string", "format": "date-time"]
                        ]
                    ] as [String: Any],
                    "LogEntry": [
                        "type": "object",
                        "properties": [
                            "stream": ["type": "string", "description": "stdout 或 stderr"],
                            "message": ["type": "string", "description": "日志内容"],
                            "timestamp": ["type": "string", "format": "date-time"]
                        ]
                    ] as [String: Any],
                    "ErrorResponse": [
                        "type": "object",
                        "properties": [
                            "ok": ["type": "boolean", "enum": [false]],
                            "error": [
                                "type": "object",
                                "properties": [
                                    "code": ["type": "string"],
                                    "message": ["type": "string"]
                                ]
                            ]
                        ]
                    ] as [String: Any]
                ]
            ]
        ]

        let data = try? JSONSerialization.data(
            withJSONObject: spec,
            options: [.prettyPrinted, .sortedKeys]
        )
        return data ?? Data("{}".utf8)
    }()

    /// OpenAPI Response 字段类型助手。
    private indirect enum SpecField {
        case bool
        case int
        case string
        case array(SpecField)
        case ref(String)

        var schemaDict: [String: Any] {
            switch self {
            case .bool:      return ["type": "boolean"]
            case .int:       return ["type": "integer"]
            case .string:    return ["type": "string"]
            case .array(let item):
                return ["type": "array", "items": item.schemaDict]
            case .ref(let r):
                return ["$ref": r]
            }
        }
    }

    /// 构造一个路径操作的字典。
    private static func specOperation(
        summary: String,
        description: String,
        parameters: [[String: Any]]? = nil,
        requestBody: [String: Any]? = nil,
        response: [String: SpecField]
    ) -> [String: Any] {
        var op: [String: Any] = [
            "summary": summary,
            "description": description,
            "responses": [
                "200": [
                    "description": "成功",
                    "content": [
                        "application/json": [
                            "schema": specResponseSchema(response)
                        ]
                    ]
                ],
                "404": [
                    "description": "未找到",
                    "content": [
                        "application/json": [
                            "schema": ["$ref": "#/components/schemas/ErrorResponse"]
                        ]
                    ]
                ]
            ]
        ]
        if let params = parameters, !params.isEmpty {
            op["parameters"] = params
        }
        if let body = requestBody {
            op["requestBody"] = body
        }
        return op
    }

    /// 将响应字段映射为 JSON Schema。
    private static func specResponseSchema(_ fields: [String: SpecField]) -> [String: Any] {
        var properties: [String: Any] = [:]
        for (key, field) in fields {
            properties[key] = field.schemaDict
        }
        return [
            "type": "object",
            "properties": properties
        ]
    }

    init(processManager: ModelProcessManager, configStore: ConfigStore, rootResponse: APIResponse) {
        self.processManager = processManager
        self.configStore = configStore
        self.rootResponse = rootResponse
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            method = head.method
            path = head.uri
            bodyBuffer = nil

            if method != .POST {
                respond(context: context)
            }

        case .body(var buffer):
            if var existing = bodyBuffer {
                existing.writeBuffer(&buffer)
                bodyBuffer = existing
            } else {
                bodyBuffer = buffer
            }

        case .end:
            if method == .POST {
                respond(context: context)
            }
        }
    }

    // MARK: - 路由

    private func respond(context: ChannelHandlerContext) {
        let response = route(method: method, path: path)
        send(response: response, context: context)
    }

    private func route(method: HTTPMethod, path: String) -> APIResponse {
        // GET /
        if method == .GET, path == "/" {
            return rootResponse
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        let count = components.count
        let prefix = count >= 2 && components[0] == "api"

        // GET /api/health
        if method == .GET, path == "/api/health" {
            return .success(SuccessResponse())
        }

        // GET /openapi.json
        if method == .GET, path == "/openapi.json" {
            return .json(Self.openapiSpec)
        }

        // GET /api/models
        if method == .GET, path == "/api/models" {
            return handleListModels()
        }

        // POST /api/config/reload
        if method == .POST, path == "/api/config/reload" {
            return handleConfigReload()
        }

        guard prefix, components[1] == "models", count >= 3 else {
            return .error(ErrorResponse(code: "not_found", message: "Route not found"))
        }

        let modelId = String(components[2])

        // GET /api/models/:id
        if method == .GET, count == 3 {
            return handleGetModel(id: modelId)
        }

        guard count >= 4 else {
            return .error(ErrorResponse(code: "not_found", message: "Route not found"))
        }

        let action = String(components[3])

        // GET /api/models/:id/logs
        if method == .GET, action == "logs" {
            return handleGetLogs(id: modelId)
        }

        // POST /api/models/:id/start
        if method == .POST, action == "start" {
            return handleStart(id: modelId)
        }

        // POST /api/models/:id/stop
        if method == .POST, action == "stop" {
            return handleStop(id: modelId)
        }

        // POST /api/models/:id/restart
        if method == .POST, action == "restart" {
            return handleRestart(id: modelId)
        }

        // POST /api/models/:id/logs/clear
        if method == .POST, action == "logs", count == 5, components[4] == "clear" {
            return handleClearLogs(id: modelId)
        }

        return .error(ErrorResponse(code: "not_found", message: "Route not found"))
    }

    // MARK: - 处理器

    /// 从 AppConfig 构建模型摘要列表（复用逻辑，避免 handleListModels 与 handleConfigReload 漂移）。
    private func buildModelSummaries(from config: AppConfig) -> [ModelSummary] {
        config.models.map { c in
            ModelSummary(
                from: c,
                status: processManager.status(for: c.id),
                pid: processManager.pid(for: c.id)
            )
        }
    }

    private func handleListModels() -> APIResponse {
        let config = (try? configStore.load()) ?? .default
        return .success(.models(buildModelSummaries(from: config)))
    }

    private func handleConfigReload() -> APIResponse {
        let fileURL = configStore.baseDirectory.appendingPathComponent("config.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // 配置文件不存在：视为空配置（200）
            onConfigReloadRequested?()
            return .success(.models(buildModelSummaries(from: .default)))
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .error(ErrorResponse(code: "config_reload_failed", message: "无法读取配置文件"))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let config = try? decoder.decode(AppConfig.self, from: data) else {
            return .error(ErrorResponse(code: "config_reload_failed", message: "配置文件格式无效"))
        }

        // 通知 UI 刷新模型列表
        onConfigReloadRequested?()

        return .success(.models(buildModelSummaries(from: config)))
    }

    private func handleGetModel(id: String) -> APIResponse {
        guard let uuid = UUID(uuidString: id),
              let config = findModel(id: uuid) else {
            return .error(ErrorResponse(code: "model_not_found", message: "Model not found"))
        }
        let summary = ModelSummary(
            from: config,
            status: processManager.status(for: uuid),
            pid: processManager.pid(for: uuid)
        )
        return .success(.model(summary))
    }

    private func handleStart(id: String) -> APIResponse {
        guard let uuid = UUID(uuidString: id),
              let config = findModel(id: uuid) else {
            return .error(ErrorResponse(code: "model_not_found", message: "Model not found"))
        }

        // 解析可选请求体中的一次性环境变量覆盖
        var envOverrides: [String: String]? = nil
        if let bodyBuffer {
            let data = bodyBuffer.getData(at: bodyBuffer.readerIndex, length: bodyBuffer.readableBytes) ?? Data()
            if !data.isEmpty {
                let request: StartModelRequest
                do {
                    request = try JSONDecoder().decode(StartModelRequest.self, from: data)
                } catch {
                    return .error(ErrorResponse(code: "invalid_request", message: "Request body is not valid JSON"))
                }
                if let error = request.validate() {
                    return .error(ErrorResponse(code: "invalid_request", message: error))
                }
                envOverrides = request.env
            }
        }

        defer { onModelStateChanged?() }
        do {
            let status = try processManager.start(config: config, envOverrides: envOverrides)
            let pid = processManager.pid(for: uuid)
            return .success(.started(status: status.rawValue, pid: pid ?? 0))
        } catch {
            return .error(ErrorResponse(code: "start_failed", message: error.localizedDescription))
        }
    }

    private func handleStop(id: String) -> APIResponse {
        defer { onModelStateChanged?() }
        guard let uuid = UUID(uuidString: id),
              findModel(id: uuid) != nil else {
            return .error(ErrorResponse(code: "model_not_found", message: "Model not found"))
        }
        _ = processManager.stop(modelId: uuid)
        return .success(.stopped())
    }

    private func handleRestart(id: String) -> APIResponse {
        guard let uuid = UUID(uuidString: id),
              let config = findModel(id: uuid) else {
            return .error(ErrorResponse(code: "model_not_found", message: "Model not found"))
        }
        defer { onModelStateChanged?() }
        do {
            let status = try processManager.restart(modelId: uuid, config: config)
            let pid = processManager.pid(for: uuid)
            return .success(.started(status: status.rawValue, pid: pid ?? 0))
        } catch {
            return .error(ErrorResponse(code: "restart_failed", message: error.localizedDescription))
        }
    }

    private func handleGetLogs(id: String) -> APIResponse {
        guard let uuid = UUID(uuidString: id),
              findModel(id: uuid) != nil else {
            return .error(ErrorResponse(code: "model_not_found", message: "Model not found"))
        }
        let logs = processManager.logs(for: uuid)
        return .success(.logs(logs))
    }

    private func handleClearLogs(id: String) -> APIResponse {
        guard let uuid = UUID(uuidString: id),
              findModel(id: uuid) != nil else {
            return .error(ErrorResponse(code: "model_not_found", message: "Model not found"))
        }
        processManager.clearLogs(for: uuid)
        return .success(SuccessResponse())
    }

    // MARK: - 辅助

    private func findModel(id: UUID) -> ModelConfig? {
        guard let config = try? configStore.load() else { return nil }
        return config.models.first(where: { $0.id == id })
    }

    private func send(response: APIResponse, context: ChannelHandlerContext) {
        let status: HTTPResponseStatus
        let body: Data
        let contentType: String

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        switch response {
        case .success(let resp):
            status = .ok
            body = (try? encoder.encode(resp)) ?? Data()
            contentType = "application/json"
        case .error(let resp):
            status = resp.error.code == "model_not_found" ? .notFound : .badRequest
            body = (try? encoder.encode(resp)) ?? Data()
            contentType = "application/json"
        case .text(let text):
            status = .ok
            body = Data(text.utf8)
            contentType = "text/plain; charset=utf-8"
        case .json(let data):
            status = .ok
            body = data
            contentType = "application/json"
        }

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)

        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: HTTPHeaders([
                ("Content-Type", contentType),
                ("Content-Length", "\(body.count)")
            ])
        )

        _ = context.write(wrapOutboundOut(.head(head)))
        _ = context.write(wrapOutboundOut(.body(.byteBuffer(buffer))))
        _ = context.writeAndFlush(wrapOutboundOut(.end(nil as HTTPHeaders?)))
    }
}
