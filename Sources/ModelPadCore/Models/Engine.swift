/// 推理引擎类型，只用于分类、图标、筛选和启动命令模板，不决定启动逻辑。
public enum Engine: String, Codable, CaseIterable, Sendable {
    case ollama
    case llamacpp
    case vllm
    case custom
    case mlx
}
