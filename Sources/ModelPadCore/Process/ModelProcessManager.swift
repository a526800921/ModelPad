import Foundation

// MARK: - 运行上下文

/// 单个模型的运行时上下文，仅存在于内存中。
private final class RunningContext: @unchecked Sendable {
    var process: Process
    var stdoutPipe: Pipe
    var stderrPipe: Pipe
    var logBuffer: LogBuffer
    var status: ModelStatus
    var isManualStop: Bool

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe, logBuffer: LogBuffer) {
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.logBuffer = logBuffer
        self.status = .starting
        self.isManualStop = false
    }
}

// MARK: - 模型进程管理器

/// 模型进程生命周期管理器。
/// 负责启动、停止、重启模型进程，维护状态机，捕获日志，执行健康检查。
public final class ModelProcessManager: @unchecked Sendable {

    private var contexts: [UUID: RunningContext] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: - 启动

    /// 启动模型。同一模型只允许一个托管进程。
    /// - Parameters:
    ///   - config: 模型配置（command、workDir、env、port 等）。
    ///   - healthCheckTimeout: TCP 健康检查超时秒数，默认 30。
    /// - Returns: 当前状态（可能为 already running）。
    public func start(config: ModelConfig, healthCheckTimeout: TimeInterval = 30) throws -> ModelStatus {
        let modelId = config.id

        // 检查是否已存在运行/启动中的进程
        lock.lock()
        if let ctx = contexts[modelId] {
            let currentStatus = ctx.status
            lock.unlock()

            if currentStatus == .running || currentStatus == .starting {
                return currentStatus
            }

            // stopped 或 error：清理旧进程再启动
            _ = stop(modelId: modelId)
        } else {
            lock.unlock()
        }

        // 创建日志缓冲（启动时清空旧日志）
        let logBuffer = LogBuffer()

        let timestamp = ISO8601DateFormatter().string(from: Date())
        logBuffer.append(stream: .system, message: "[\(timestamp)] starting model '\(config.name)'")

        // 创建进程
        let process = Process()
        if config.launchMode == .pythonScript, let script = config.pythonScript, !script.scriptPath.isEmpty {
            // Python 脚本模式：绕过 shell，避免转义问题
            let py = script.pythonExecutable ?? "python3"
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [py, script.scriptPath] + script.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", config.command]
        }

        if let workDir = config.effectiveWorkDir() {
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)
        }

        // 注入环境变量
        var fullEnv = ProcessInfo.processInfo.environment
        for (key, value) in config.effectiveEnv() {
            fullEnv[key] = value
        }
        process.environment = fullEnv

        // stdout / stderr 管道
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 上下文
        let ctx = RunningContext(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            logBuffer: logBuffer
        )

        lock.lock()
        contexts[modelId] = ctx
        lock.unlock()

        // 异步读取 stdout / stderr
        captureOutput(pipe: stdoutPipe, stream: .stdout, buffer: logBuffer)
        captureOutput(pipe: stderrPipe, stream: .stderr, buffer: logBuffer)

        // 进程退出回调
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.lock.lock()
            guard let currentCtx = self.contexts[modelId] else {
                self.lock.unlock()
                return
            }

            // 无论手动/异常退出，先关闭管道避免 readabilityHandler 死循环
            currentCtx.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            currentCtx.stderrPipe.fileHandleForReading.readabilityHandler = nil

            if currentCtx.isManualStop {
                // 手动停止，状态已在 stop() 中设置
                self.lock.unlock()
                return
            }

            // 异常退出
            let exitCode = proc.terminationStatus
            let reason = proc.terminationReason
            currentCtx.logBuffer.append(
                stream: .system,
                message: "[\(ISO8601DateFormatter().string(from: Date()))] process exited: code=\(exitCode) reason=\(reason.rawValue)"
            )
            currentCtx.status = .error
            self.lock.unlock()
        }

        // 启动进程
        try process.run()

        // 健康检查
        if let port = config.port {
            ctx.logBuffer.append(stream: .system, message: "[\(ISO8601DateFormatter().string(from: Date()))] waiting for TCP health check on :\(port)")

            let healthy = TCPHealthChecker.check(host: "127.0.0.1", port: port, timeout: healthCheckTimeout)

            lock.lock()
            if healthy {
                ctx.status = .running
                ctx.logBuffer.append(stream: .system, message: "[\(ISO8601DateFormatter().string(from: Date()))] TCP health check passed, model running")
                lock.unlock()
            } else {
                ctx.status = .error
                ctx.logBuffer.append(stream: .system, message: "[\(ISO8601DateFormatter().string(from: Date()))] TCP health check timeout on :\(port)")

                // 健康检查失败，终止进程
                ctx.isManualStop = true  // 阻止 terminationHandler 重复设 error
                let pid = ctx.process.processIdentifier
                let failedProcess = ctx.process
                lock.unlock()

                failedProcess.terminate()
                // 短暂等待退出
                let deadline = Date().addingTimeInterval(2)
                while failedProcess.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if failedProcess.isRunning {
                    kill(pid, SIGKILL)
                    failedProcess.waitUntilExit()
                }

                lock.lock()
                ctx.logBuffer.append(stream: .system, message: "[\(ISO8601DateFormatter().string(from: Date()))] process terminated due to health check failure")
                lock.unlock()
            }
        } else {
            // 无端口：进程成功 spawn 后直接视为 running
            lock.lock()
            ctx.status = .running
            ctx.logBuffer.append(stream: .system, message: "[\(ISO8601DateFormatter().string(from: Date()))] process spawned, model running")
            lock.unlock()
        }

        lock.lock()
        let finalStatus = ctx.status
        lock.unlock()
        return finalStatus
    }

    // MARK: - 停止

    /// 停止模型进程。
    /// - Parameter modelId: 模型 ID。
    /// - Returns: 停止后的状态。
    public func stop(modelId: UUID) -> ModelStatus {
        lock.lock()
        guard let ctx = contexts[modelId] else {
            lock.unlock()
            return .stopped
        }

        if ctx.status == .stopped {
            lock.unlock()
            return .stopped
        }

        // 标记手动停止
        ctx.isManualStop = true

        let pid = ctx.process.processIdentifier
        let process = ctx.process
        lock.unlock()

        // 优雅终止 SIGTERM
        process.terminate()

        // 等待最多 5 秒
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // 仍未退出则强制 SIGKILL
        if process.isRunning {
            kill(pid, SIGKILL)
            process.waitUntilExit()
        }

        lock.lock()
        ctx.status = .stopped
        ctx.logBuffer.append(stream: .system, message: "[\(ISO8601DateFormatter().string(from: Date()))] model stopped")
        // 关闭管道监听防止死循环
        ctx.stdoutPipe.fileHandleForReading.readabilityHandler = nil
        ctx.stderrPipe.fileHandleForReading.readabilityHandler = nil
        lock.unlock()

        return .stopped
    }

    // MARK: - 重启

    /// 重启模型：先停止再启动。
    /// - Parameters:
    ///   - modelId: 模型 ID。
    ///   - config: 模型配置。
    /// - Returns: 启动后的状态。
    public func restart(modelId: UUID, config: ModelConfig) throws -> ModelStatus {
        _ = stop(modelId: modelId)
        return try start(config: config)
    }

    // MARK: - 查询

    /// 查询模型当前状态。
    public func status(for modelId: UUID) -> ModelStatus {
        lock.lock()
        defer { lock.unlock() }
        return contexts[modelId]?.status ?? .stopped
    }

    /// 查询模型 PID。
    public func pid(for modelId: UUID) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard let ctx = contexts[modelId], ctx.process.isRunning else { return nil }
        return ctx.process.processIdentifier
    }

    /// 获取模型日志快照。
    public func logs(for modelId: UUID) -> [ModelLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return contexts[modelId]?.logBuffer.all() ?? []
    }

    /// 清空模型日志。
    public func clearLogs(for modelId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        contexts[modelId]?.logBuffer.clear()
    }

    // MARK: - 内部

    /// 异步捕获管道输出。EOF 时自动清理 readabilityHandler 防止死循环。
    ///
    /// tqdm 在 pipe 模式下每行以 `\n` 收尾时，中间进度更新用 `\r` 覆盖刷新。
    /// 此处积累到 `\n` 再输出整行，但如果超过 4KB 还没见到 `\n`（纯 `\r` 进度条），
    /// 也立即输出避免长时间无反馈。
    private func captureOutput(pipe: Pipe, stream: LogStream, buffer: LogBuffer) {
        let partial = PartialData()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF：输出残留
                if !partial.data.isEmpty, let text = String(data: partial.data, encoding: .utf8) {
                    let final = text.split(separator: "\r", omittingEmptySubsequences: true).last
                    if let msg = final, !msg.isEmpty {
                        buffer.append(stream: stream, message: String(msg))
                    }
                }
                handle.readabilityHandler = nil
                return
            }

            partial.data.append(data)

            // 提取所有完整行（以 \n 结尾）
            while let nlIndex = partial.data.firstIndex(of: 0x0A) {
                let lineData = partial.data[..<nlIndex]
                partial.data.removeSubrange(...nlIndex)

                guard let text = String(data: lineData, encoding: .utf8) else { continue }
                let segments = text.split(separator: "\r", omittingEmptySubsequences: true)
                for seg in segments where !seg.allSatisfy({ $0.isWhitespace }) {
                    buffer.append(stream: stream, message: String(seg))
                }
            }

            // 超过 4KB 还没 \n：纯 \r 进度条，输出当前状态
            if partial.data.count > 4096 {
                if let text = String(data: partial.data, encoding: .utf8) {
                    let final = text.split(separator: "\r", omittingEmptySubsequences: true).last
                    if let msg = final, !msg.isEmpty,
                       !msg.allSatisfy({ $0.isWhitespace }) {
                        buffer.append(stream: stream, message: String(msg))
                    }
                }
                partial.data.removeAll()
            }

            // 硬上限防内存撑爆
            if partial.data.count > 256_000 {
                partial.data.removeAll()
            }
        }
    }
}

/// 可变 Data 缓冲，用于 pipe readabilityHandler 中跨 chunk 积累行数据。
private final class PartialData: @unchecked Sendable {
    var data = Data()
}
