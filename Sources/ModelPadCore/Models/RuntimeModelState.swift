/// 运行时模型状态，只存在内存中，不作为可信配置持久化。
public struct RuntimeModelState: Sendable {
    public var status: ModelStatus
    public var pid: Int32?

    public init(status: ModelStatus = .stopped, pid: Int32? = nil) {
        self.status = status
        self.pid = pid
    }
}
