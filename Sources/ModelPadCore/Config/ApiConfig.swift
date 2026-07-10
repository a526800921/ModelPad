import Foundation

/// API 服务器配置。
public struct ApiConfig: Codable, Sendable {
    public var enabled: Bool
    public var host: String
    public var port: Int

    public static let `default` = ApiConfig(
        enabled: true,
        host: "127.0.0.1",
        port: 9999
    )

    public init(enabled: Bool, host: String, port: Int) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }
}
