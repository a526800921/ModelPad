import SwiftUI
import ModelPadCore

/// 左侧模型列表。
public struct ModelListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var pendingDeleteId: UUID?
    @State private var pendingDeleteIsRunning = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            Text("模型")
                .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 列表
            List(selection: $viewModel.selectedModelId) {
                ForEach(viewModel.models) { model in
                    ModelRow(
                        model: model,
                        status: viewModel.statusMessages[model.id] ?? .stopped,
                        isSelected: viewModel.selectedModelId == model.id
                    )
                    .tag(model.id)
                    .onTapGesture {
                        viewModel.selectModel(model.id)
                    }
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        let model = viewModel.models[idx]
                        requestDelete(model.id)
                    }
                }
            }
            .listStyle(.sidebar)

            // 底部按钮
            HStack {
                Button(action: { viewModel.newModel() }) {
                    Label("添加", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("添加模型")

                Button(action: { viewModel.reloadModels() }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("重新读取配置")

                Spacer()

                if let selectedId = viewModel.selectedModelId {
                    Button(action: { requestDelete(selectedId) }) {
                        Label("删除", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help("删除选中模型")
                    .disabled(viewModel.models.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .alert(alertTitle, isPresented: Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDeleteId = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDeleteId {
                    viewModel.deleteModel(id)
                }
                pendingDeleteId = nil
            }
        } message: {
            Text(pendingDeleteIsRunning
                ? "该模型正在运行。删除前会先停止它。"
                : "确定删除这个模型配置吗？")
        }
    }

    private var alertTitle: String {
        "删除模型"
    }

    private func requestDelete(_ id: UUID) {
        let status = viewModel.statusMessages[id] ?? .stopped
        pendingDeleteIsRunning = (status == .running || status == .starting)
        pendingDeleteId = id
    }
}

// MARK: - ModelRow

struct ModelRow: View {
    let model: ModelConfig
    let status: ModelStatus
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(engineDisplayName(model.engine))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let port = model.port {
                Text(":\(port)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch status {
        case .stopped: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }

    private func engineDisplayName(_ engine: Engine) -> String {
        switch engine {
        case .ollama: return "Ollama"
        case .llamacpp: return "llama.cpp"
        case .vllm: return "vLLM"
        case .custom: return "自定义"
        case .mlx: return "MLX"
        }
    }
}
