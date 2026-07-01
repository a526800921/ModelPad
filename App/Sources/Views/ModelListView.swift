import SwiftUI
import ModelPadCore

/// 左侧模型列表。
public struct ModelListView: View {
    @EnvironmentObject var viewModel: AppViewModel

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("Models")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.newModel() }) {
                    Image(systemName: "plus")
                }
                .help("Add model")
            }
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
                        viewModel.deleteModel(model.id)
                    }
                }
            }
            .listStyle(.sidebar)

            // 底部按钮
            HStack {
                Button(action: { viewModel.newModel() }) {
                    Label("Add", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("Add model")

                Spacer()

                if let selectedId = viewModel.selectedModelId {
                    Button(action: { viewModel.deleteModel(selectedId) }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help("Delete selected model")
                    .disabled(viewModel.models.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
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
                Text(model.engine.rawValue)
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
}
