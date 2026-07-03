import Foundation

/// 线程安全的内存环形日志缓冲，每模型独立实例。
/// 使用预分配定长数组 + 写入指针实现 O(1) append。
public final class LogBuffer: @unchecked Sendable {

    public let maxLines: Int
    public let maxLineLength: Int

    private var buffer: [ModelLogEntry?]
    private var writeIndex: Int = 0
    private var currentCount: Int = 0
    private let lock = NSLock()

    /// 创建日志缓冲。
    /// - Parameters:
    ///   - maxLines: 最大保留行数，默认 2000。
    ///   - maxLineLength: 单行最大字符数，超长截断，默认 8000。
    public init(maxLines: Int = 2000, maxLineLength: Int = 8000) {
        self.maxLines = maxLines
        self.maxLineLength = maxLineLength
        self.buffer = Array(repeating: nil, count: maxLines)
    }

    // MARK: - 追加

    /// 追加一条日志。O(1)，满时覆盖最旧条目。
    public func append(stream: LogStream, message: String) {
        let truncated: String
        if message.count > maxLineLength {
            truncated = String(message.prefix(maxLineLength))
        } else {
            truncated = message
        }

        let entry = ModelLogEntry(time: Date(), stream: stream, message: truncated)

        lock.lock()
        buffer[writeIndex] = entry
        writeIndex = (writeIndex + 1) % maxLines
        if currentCount < maxLines {
            currentCount += 1
        }
        lock.unlock()
    }

    // MARK: - 查询

    /// 返回当前全部日志的快照，按时间从旧到新排序。
    public func all() -> [ModelLogEntry] {
        lock.lock()
        defer { lock.unlock() }

        guard currentCount > 0 else { return [] }

        // 未满时条目在 [0..<currentCount)
        if currentCount < maxLines {
            return buffer.prefix(currentCount).compactMap { $0 }
        }

        // 已满时：最旧条目在 writeIndex，环形读取 currentCount 条
        var result: [ModelLogEntry] = []
        result.reserveCapacity(currentCount)
        for i in 0..<currentCount {
            let idx = (writeIndex + i) % maxLines
            if let entry = buffer[idx] {
                result.append(entry)
            }
        }
        return result
    }

    /// 当前日志条数。
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentCount
    }

    // MARK: - 清空

    /// 清空全部日志。
    public func clear() {
        lock.lock()
        // 释放缓冲中所有引用
        for i in 0..<buffer.count {
            buffer[i] = nil
        }
        writeIndex = 0
        currentCount = 0
        lock.unlock()
    }
}
