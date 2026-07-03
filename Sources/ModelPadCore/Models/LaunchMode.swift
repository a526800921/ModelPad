import Foundation

/// 启动模式：决定如何生成最终启动命令。
public enum LaunchMode: String, Codable, Equatable, CaseIterable, Sendable {
    /// 直接使用 ModelConfig.command 字符串。
    case command
    /// 从 PythonScriptConfig 拼接命令行。
    case pythonScript
}
