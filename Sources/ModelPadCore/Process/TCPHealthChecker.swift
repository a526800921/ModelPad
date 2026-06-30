import Foundation

/// TCP 端口健康检查，v1 只做 TCP connect。
public enum TCPHealthChecker {

    /// 检查指定 host:port 是否在 timeout 内可连接。
    /// - Parameters:
    ///   - host: 目标主机，通常为 127.0.0.1。
    ///   - port: 目标端口。
    ///   - timeout: 超时秒数，默认 30。
    /// - Returns: 连接成功返回 true，超时或失败返回 false。
    public static func check(host: String, port: Int, timeout: TimeInterval = 30) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // 设置非阻塞
        let flags = fcntl(sock, F_GETFL, 0)
        guard flags >= 0 else { return false }
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        // 解析地址
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        // 非阻塞连接
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true
        }

        if errno != EINPROGRESS {
            return false
        }

        // 用 poll 等待连接完成或超时
        var pollfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pollfd, 1, Int32(timeout * 1000))

        if pollResult > 0 {
            // 连接完成，检查是否有错误
            var error: Int32 = 0
            var errorLen = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &errorLen)
            return error == 0
        }

        return false
    }
}
