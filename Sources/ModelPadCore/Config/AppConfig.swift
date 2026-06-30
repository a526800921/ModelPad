import Foundation

/// 应用配置根对象。
public struct AppConfig: Codable, Sendable {
    public var version: Int
    public var api: ApiConfig
    public var models: [ModelConfig]

    /// 默认空配置。
    public static let `default` = AppConfig(
        version: 1,
        api: .default,
        models: []
    )

    public init(version: Int, api: ApiConfig, models: [ModelConfig]) {
        self.version = version
        self.api = api
        self.models = models
    }
}
