import Foundation

/// 日志条目，包含时间、来源流和消息内容。
public struct ModelLogEntry: Codable, Sendable {
    public var time: Date
    public var stream: LogStream
    public var message: String

    public init(time: Date = Date(), stream: LogStream, message: String) {
        self.time = time
        self.stream = stream
        self.message = message
    }
}
