import Foundation

/// Python 脚本启动配置。
public struct PythonScriptConfig: Codable, Equatable, Sendable {
    /// 脚本文件路径（绝对路径，或相对 workDir 的路径）。
    public var scriptPath: String
    /// 传给脚本的参数列表。
    public var arguments: [String]
    /// Python 可执行文件路径，为空时默认使用 python3。
    public var pythonExecutable: String?
    /// 脚本工作目录，优先级高于模型级 workDir。
    public var workDir: String?
    /// 额外环境变量，会与模型级 env 合并。
    public var env: [String: String]

    public init(
        scriptPath: String,
        arguments: [String] = [],
        pythonExecutable: String? = nil,
        workDir: String? = nil,
        env: [String: String] = [:]
    ) {
        self.scriptPath = scriptPath
        self.arguments = arguments
        self.pythonExecutable = pythonExecutable
        self.workDir = workDir
        self.env = env
    }
}
