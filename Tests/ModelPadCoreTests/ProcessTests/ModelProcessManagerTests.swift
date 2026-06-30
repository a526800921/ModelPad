import Foundation
import Testing

@testable import ModelPadCore

// MARK: - 辅助

func makeTestConfig(
    id: UUID = UUID(),
    name: String = "test-model",
    command: String,
    port: Int? = nil,
    workDir: String? = nil,
    env: [String: String] = [:]
) -> ModelConfig {
    ModelConfig(
        id: id,
        name: name,
        engine: .custom,
        command: command,
        workDir: workDir,
        env: env,
        port: port
    )
}

// MARK: - 无端口启动

@Test("无端口命令启动成功后进入 running")
func startWithoutPortGoesRunning() throws {
    let manager = ModelProcessManager()
    let config = makeTestConfig(command: "sleep 10")

    let status = try manager.start(config: config)
    #expect(status == .running, "无端口命令 spawn 后应直接 running")

    // 验证 PID 存在
    let pid = manager.pid(for: config.id)
    #expect(pid != nil, "应有 PID")
    #expect(pid! > 0)

    // 清理
    _ = manager.stop(modelId: config.id)
}

// MARK: - 重复启动保护

@Test("重复启动同一模型不会创建第二个进程")
func duplicateStartReturnsCurrentStatus() throws {
    let manager = ModelProcessManager()
    let config = makeTestConfig(command: "sleep 10")

    let status1 = try manager.start(config: config)
    #expect(status1 == .running)

    // 第二次启动应返回当前状态
    let status2 = try manager.start(config: config)
    #expect(status2 == .running, "重复启动应返回 running")

    // 验证只有一个进程被追踪
    let pid = manager.pid(for: config.id)
    #expect(pid != nil)

    _ = manager.stop(modelId: config.id)
}

// MARK: - 停止

@Test("手动停止运行中模型后进入 stopped")
func stopRunningModelGoesStopped() throws {
    let manager = ModelProcessManager()
    let config = makeTestConfig(command: "sleep 60")

    _ = try manager.start(config: config)
    #expect(manager.status(for: config.id) == .running)

    let status = manager.stop(modelId: config.id)
    #expect(status == .stopped)

    // PID 应被清除
    #expect(manager.pid(for: config.id) == nil)
}

@Test("停止未运行模型返回 stopped")
func stopNonRunningModel() {
    let manager = ModelProcessManager()
    let status = manager.stop(modelId: UUID())
    #expect(status == .stopped)
}

// MARK: - 异常退出

@Test("运行中进程异常退出后进入 error")
func processAbnormalExitGoesError() throws {
    let manager = ModelProcessManager()
    // bash -c "exit 1" 会立即以非零码退出
    let config = makeTestConfig(command: "exit 1")

    _ = try manager.start(config: config)
    // 无端口直接视为 running，但进程几乎立即退出
    // 等待终止回调执行
    Thread.sleep(forTimeInterval: 0.5)

    let finalStatus = manager.status(for: config.id)
    #expect(finalStatus == .error, "异常退出应进入 error，实际 \(finalStatus)")
}

// MARK: - 重启

@Test("重启等价于停止后启动")
func restartStopsThenStarts() throws {
    let manager = ModelProcessManager()
    let config = makeTestConfig(command: "sleep 30")

    // 先启动
    let s1 = try manager.start(config: config)
    #expect(s1 == .running)
    let pid1 = manager.pid(for: config.id)

    // 重启
    let s2 = try manager.restart(modelId: config.id, config: config)
    #expect(s2 == .running)
    let pid2 = manager.pid(for: config.id)

    // PID 应已变化（新进程）
    #expect(pid2 != nil)
    #expect(pid1 != pid2, "重启后应是新进程")

    _ = manager.stop(modelId: config.id)
}

// MARK: - 日志捕获

@Test("stdout 被捕获到对应日志流")
func stdoutCapturedToLogBuffer() throws {
    let manager = ModelProcessManager()
    let config = makeTestConfig(command: "echo hello-from-stdout")

    // echo 命令很快结束（无端口，直接 running）
    let _ = try manager.start(config: config)
    Thread.sleep(forTimeInterval: 0.2)

    let logs = manager.logs(for: config.id)
    let stdoutLogs = logs.filter { $0.stream == .stdout }
    #expect(!stdoutLogs.isEmpty, "应捕获到 stdout 日志")
    #expect(stdoutLogs.contains(where: { $0.message == "hello-from-stdout" }),
            "应包含 echo 输出")
}

@Test("stderr 被捕获到对应日志流")
func stderrCapturedToLogBuffer() throws {
    let manager = ModelProcessManager()
    // 向 stderr 写入
    let config = makeTestConfig(command: "echo error-msg >&2")

    let _ = try manager.start(config: config)
    Thread.sleep(forTimeInterval: 0.2)

    let logs = manager.logs(for: config.id)
    let stderrLogs = logs.filter { $0.stream == .stderr }
    #expect(!stderrLogs.isEmpty, "应捕获到 stderr 日志")
    #expect(stderrLogs.contains(where: { $0.message == "error-msg" }),
            "应包含 stderr 输出")
}

@Test("system 日志记录启动和停止事件")
func systemLogRecordsLifecycleEvents() throws {
    let manager = ModelProcessManager()
    let config = makeTestConfig(command: "sleep 10")

    _ = try manager.start(config: config)
    _ = manager.stop(modelId: config.id)

    let logs = manager.logs(for: config.id)
    let systemLogs = logs.filter { $0.stream == .system }

    #expect(systemLogs.contains(where: { $0.message.contains("starting model") }),
            "应有启动 system 日志")
    #expect(systemLogs.contains(where: { $0.message.contains("stopped") }),
            "应有停止 system 日志")
}

// MARK: - 日志隔离

@Test("两个模型的日志缓冲相互隔离")
func perModelLogIsolation() throws {
    let manager = ModelProcessManager()
    let config1 = makeTestConfig(id: UUID(), name: "model-1", command: "echo log-from-1")
    let config2 = makeTestConfig(id: UUID(), name: "model-2", command: "echo log-from-2")

    let _ = try manager.start(config: config1)
    let _ = try manager.start(config: config2)
    Thread.sleep(forTimeInterval: 0.3)

    let logs1 = manager.logs(for: config1.id)
    let logs2 = manager.logs(for: config2.id)

    #expect(logs1.contains(where: { $0.message == "log-from-1" }))
    #expect(logs2.contains(where: { $0.message == "log-from-2" }))
    #expect(!logs1.contains(where: { $0.message == "log-from-2" }),
            "model-1 不应包含 model-2 的日志")
}

// MARK: - 重启清空日志

@Test("重启后旧日志被清空")
func restartClearsOldLogs() throws {
    let manager = ModelProcessManager()
    let config1 = makeTestConfig(command: "echo old-log")

    // 第一次启动
    let _ = try manager.start(config: config1)
    Thread.sleep(forTimeInterval: 0.2)

    let oldLogs = manager.logs(for: config1.id)
    #expect(!oldLogs.isEmpty, "第一次启动应有日志")
    #expect(oldLogs.contains(where: { $0.message == "old-log" }))

    // 停止
    _ = manager.stop(modelId: config1.id)

    // 重启，使用不产生旧日志的命令
    let config2 = makeTestConfig(id: config1.id, command: "echo new-log")
    let _ = try manager.restart(modelId: config1.id, config: config2)
    Thread.sleep(forTimeInterval: 0.2)

    let newLogs = manager.logs(for: config1.id)
    #expect(!newLogs.contains(where: { $0.message == "old-log" }),
            "重启后不应包含旧日志")
    #expect(newLogs.contains(where: { $0.message == "new-log" }),
            "重启后应包含新日志")

    _ = manager.stop(modelId: config1.id)
}

// MARK: - 有端口健康检查

@Test("有端口命令等待 TCP 健康检查后进入 running")
func portModelTCPSuccessGoesRunning() throws {
    // 使用随机端口避免冲突
    let port = 20100 + Int.random(in: 0...999)
    let manager = ModelProcessManager()
    // 模型命令本身通过 nc -l 在指定端口上监听
    let config = makeTestConfig(command: "nc -l \(port)", port: port)

    let status = try manager.start(config: config)
    #expect(status == .running, "nc -l 监听端口后 TCP 检查应通过，实际 \(status)")

    _ = manager.stop(modelId: config.id)
}

@Test("有端口命令 TCP 健康检查超时进入 error 并终止进程")
func portModelTCPTimeoutGoesErrorAndProcessKilled() throws {
    let port = 19881
    let manager = ModelProcessManager()
    // 模型命令 sleep 不监听任何端口，TCP 检查会超时
    let config = makeTestConfig(command: "sleep 30", port: port)

    let status = try manager.start(config: config, healthCheckTimeout: 1)
    #expect(status == .error, "TCP 超时应进入 error，实际 \(status)")

    // 确认进程已被终止
    Thread.sleep(forTimeInterval: 0.3)
    let pid = manager.pid(for: config.id)
    #expect(pid == nil, "健康检查失败后进程应被终止，pid 应为 nil，实际 \(String(describing: pid))")

    // 确认 system 日志包含超时和终止信息
    let logs = manager.logs(for: config.id)
    #expect(logs.contains(where: { $0.message.contains("health check timeout") }),
            "日志应包含 health check timeout")
    #expect(logs.contains(where: { $0.message.contains("terminated due to health check failure") }),
            "日志应包含 process terminated")
}

// MARK: - error 状态重新启动

@Test("error 状态重新启动会先清理旧进程再创建新进程")
func restartFromErrorCleansUpOldProcess() throws {
    let port = 19882
    let manager = ModelProcessManager()
    // 第一次启动：端口不可达 → timeout → error
    let config = makeTestConfig(command: "sleep 30", port: port)

    let status1 = try manager.start(config: config, healthCheckTimeout: 1)
    #expect(status1 == .error)

    // 确认旧进程已被清理
    let pid1 = manager.pid(for: config.id)
    #expect(pid1 == nil)

    // 重新启动同一个模型（error → stopped → 新启动）
    let config2 = makeTestConfig(id: config.id, command: "sleep 10")
    let status2 = try manager.start(config: config2)
    #expect(status2 == .running, "error 后重新启动应成功，实际 \(status2)")

    let pid2 = manager.pid(for: config.id)
    #expect(pid2 != nil, "新进程应有 PID")

    _ = manager.stop(modelId: config.id)
}

// MARK: - 查询未追踪的模型

@Test("查询未追踪模型返回 stopped")
func unknownModelReturnsStopped() {
    let manager = ModelProcessManager()
    #expect(manager.status(for: UUID()) == .stopped)
    #expect(manager.pid(for: UUID()) == nil)
    #expect(manager.logs(for: UUID()).isEmpty)
}

// MARK: - 启动中可被停止

@Test("启动中模型可被停止")
func startingModelCanBeStopped() throws {
    let manager = ModelProcessManager()
    // 命令有端口但端口不可达，health check 期间状态应为 starting
    let port = 20200 + Int.random(in: 0...999)
    let config = makeTestConfig(command: "sleep 30", port: port)

    // 在后台启动
    Task {
        let _ = try? manager.start(config: config, healthCheckTimeout: 5)
    }

    // 等待进程 spawn 完成，状态应为 starting
    Thread.sleep(forTimeInterval: 0.3)

    let status = manager.status(for: config.id)
    // 实际状态应为 starting（TCP 检查还在等待中）
    #expect(status == .starting, "健康检查期间状态应为 starting，实际 \(status)")

    // 从 starting 状态停止
    let stopResult = manager.stop(modelId: config.id)
    #expect(stopResult == .stopped, "启动中停止后应返回 stopped，实际 \(stopResult)")

    // PID 应为 nil
    #expect(manager.pid(for: config.id) == nil)
}

// MARK: - env 和 workDir 注入

@Test("env 变量注入到进程")
func envInjection() throws {
    let manager = ModelProcessManager()
    let config = makeTestConfig(
        command: "echo $TEST_VAR",
        env: ["TEST_VAR": "injected-value"]
    )

    let _ = try manager.start(config: config)
    Thread.sleep(forTimeInterval: 0.2)

    let logs = manager.logs(for: config.id)
    #expect(logs.contains(where: { $0.message == "injected-value" }),
            "环境变量应被注入并可在命令中读取")
}
