import Foundation

/// 线程安全的内存环形日志缓冲，每模型独立实例。
public final class LogBuffer: @unchecked Sendable {

    public let maxLines: Int
    public let maxLineLength: Int

    private var entries: [ModelLogEntry] = []
    private let lock = NSLock()

    /// 创建日志缓冲。
    /// - Parameters:
    ///   - maxLines: 最大保留行数，默认 2000。
    ///   - maxLineLength: 单行最大字符数，超长截断，默认 8000。
    public init(maxLines: Int = 2000, maxLineLength: Int = 8000) {
        self.maxLines = maxLines
        self.maxLineLength = maxLineLength
    }

    // MARK: - 追加

    /// 追加一条日志。
    public func append(stream: LogStream, message: String) {
        let truncated: String
        if message.count > maxLineLength {
            truncated = String(message.prefix(maxLineLength))
        } else {
            truncated = message
        }

        let entry = ModelLogEntry(time: Date(), stream: stream, message: truncated)

        lock.lock()
        entries.append(entry)

        // FIFO 淘汰
        if entries.count > maxLines {
            let overflow = entries.count - maxLines
            entries.removeFirst(overflow)
        }
        lock.unlock()
    }

    // MARK: - 查询

    /// 返回当前全部日志的快照。
    public func all() -> [ModelLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// 当前日志条数。
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - 清空

    /// 清空全部日志。
    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
