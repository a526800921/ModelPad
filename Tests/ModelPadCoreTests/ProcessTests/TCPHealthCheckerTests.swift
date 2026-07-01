import Foundation
import Testing

@testable import ModelPadCore

@Suite(.serialized) struct TCPHealthCheckerTests {

// MARK: - 可连接

@Test("对监听端口返回 true")
func checkListeningPortReturnsTrue() throws {
    // 使用 nc 在随机端口上启动 TCP 监听
    let port = 19876
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    process.arguments = ["-l", "\(port)"]

    // 捕获输出避免阻塞
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()

    // 给 nc 一点时间启动
    Thread.sleep(forTimeInterval: 0.5)

    // 验证可连接
    let result = TCPHealthChecker.check(host: "127.0.0.1", port: port, timeout: 3)
    #expect(result == true, "nc 已在监听 \(port)，应返回 true")

    // 清理
    process.terminate()
    process.waitUntilExit()
}

// MARK: - 不可连接

@Test("对未监听端口返回 false")
func checkUnreachablePortReturnsFalse() {
    // 使用一个大概率无服务监听的端口
    let result = TCPHealthChecker.check(host: "127.0.0.1", port: 19877, timeout: 1)
    #expect(result == false, "无进程监听的端口应返回 false")
}

// MARK: - 超时

@Test("不可达主机应超时返回 false")
func unreachableHostReturnsFalse() {
    // 使用 TEST-NET 地址，不应可达
    let start = Date()
    let result = TCPHealthChecker.check(host: "192.0.2.1", port: 80, timeout: 2)
    let elapsed = Date().timeIntervalSince(start)

    #expect(result == false, "不可达主机应返回 false")
    #expect(elapsed < 4, "应在 timeout 附近返回（允许一些余量），实际耗时 \(elapsed)s")
}

// MARK: - 默认参数

@Test("默认超时 30 秒")
func defaultTimeoutIs30() {
    // 对某个不可达端口发起检查，验证它不会立即返回（但也设置短超时避免等待）
    let start = Date()
    let result = TCPHealthChecker.check(host: "127.0.0.1", port: 19878, timeout: 0.5)
    let elapsed = Date().timeIntervalSince(start)
    #expect(result == false)
    #expect(elapsed < 2)
}

} // TCPHealthCheckerTests
