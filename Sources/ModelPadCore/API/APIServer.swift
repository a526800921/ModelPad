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

    /// API 启停操作后回调，用于通知 UI 刷新状态。
    public var onModelStateChanged: (@Sendable () -> Void)?

    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?

    public init(
        host: String = "127.0.0.1",
        port: Int = 9786,
        processManager: ModelProcessManager,
        configStore: ConfigStore
    ) {
        self.host = host
        self.port = port
        self.processManager = processManager
        self.configStore = configStore
    }

    // MARK: - 生命周期

    public func start() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let store: ConfigStore = configStore
        let pm: ModelProcessManager = processManager
        let stateChanged = self.onModelStateChanged

        let bootstrap = ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                let handler = APIHandler(processManager: pm, configStore: store)
                handler.onModelStateChanged = stateChanged
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

    var onModelStateChanged: (@Sendable () -> Void)?

    private var method: HTTPMethod = .GET
    private var path: String = ""
    private var bodyBuffer: ByteBuffer?

    init(processManager: ModelProcessManager, configStore: ConfigStore) {
        self.processManager = processManager
        self.configStore = configStore
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
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        let count = components.count
        let prefix = count >= 2 && components[0] == "api"

        // GET /api/health
        if method == .GET, path == "/api/health" {
            return .success(SuccessResponse())
        }

        // GET /api/models
        if method == .GET, path == "/api/models" {
            return handleListModels()
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

    private func handleListModels() -> APIResponse {
        let config = (try? configStore.load()) ?? .default
        let summaries = config.models.map { c in
            ModelSummary(
                from: c,
                status: processManager.status(for: c.id),
                pid: processManager.pid(for: c.id)
            )
        }
        return .success(.models(summaries))
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        switch response {
        case .success(let resp):
            status = .ok
            body = (try? encoder.encode(resp)) ?? Data()
        case .error(let resp):
            status = resp.error.code == "model_not_found" ? .notFound : .badRequest
            body = (try? encoder.encode(resp)) ?? Data()
        }

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)

        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: HTTPHeaders([
                ("Content-Type", "application/json"),
                ("Content-Length", "\(body.count)")
            ])
        )

        _ = context.write(wrapOutboundOut(.head(head)))
        _ = context.write(wrapOutboundOut(.body(.byteBuffer(buffer))))
        _ = context.writeAndFlush(wrapOutboundOut(.end(nil as HTTPHeaders?)))
    }
}
