/// 模型运行状态。
public enum ModelStatus: String, Codable, Sendable {
    /// 没有由 ModelPad 托管的运行进程。
    case stopped
    /// 进程已 spawn，但还没确认可用。
    case starting
    /// 进程存在；如配置端口，则 TCP 端口连通。
    case running
    /// 启动失败、进程异常退出、健康检查超时或失败。
    case error
}
