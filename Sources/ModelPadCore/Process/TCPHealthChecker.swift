import Foundation

/// TCP 端口健康检查，v1 只做 TCP connect。
public enum TCPHealthChecker {

    /// 检查指定 host:port 是否在 timeout 内可连接。
    /// 在超时窗口内重试，每次失败后等待一小段时间再试，
    /// 以应对端口尚未绑定或进程正在启动的场景。
    /// - Parameters:
    ///   - host: 目标主机，通常为 127.0.0.1。
    ///   - port: 目标端口。
    ///   - timeout: 超时秒数，默认 30。
    /// - Returns: 连接成功返回 true，超时返回 false。
    public static func check(host: String, port: Int, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let retryInterval: TimeInterval = 0.2

        // 解析地址（只做一次）
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        while true {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { return false }

            // 设置非阻塞
            let flags = fcntl(sock, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)
            }

            // 非阻塞连接
            let connectResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if connectResult == 0 {
                close(sock)
                return true
            }

            if errno == EINPROGRESS {
                // 用 poll 等待连接完成
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { close(sock); return false }

                var pollfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                let pollResult = poll(&pollfd, 1, Int32(remaining * 1000))

                if pollResult > 0 {
                    var error: Int32 = 0
                    var errorLen = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &errorLen)
                    close(sock)
                    if error == 0 {
                        return true
                    }
                }
                close(sock)
                // poll 超时或出错，继续重试
            } else {
                close(sock)
                // ECONNREFUSED 等立即失败，重试
            }

            // 检查是否已超时
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }

            // 等待一段时间再重试
            let waitTime = min(retryInterval, remaining)
            Thread.sleep(forTimeInterval: waitTime)
        }
    }
}
