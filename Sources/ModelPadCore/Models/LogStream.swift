/// 日志来源流。
public enum LogStream: String, Codable, Sendable {
    case stdout
    case stderr
    case system
}
