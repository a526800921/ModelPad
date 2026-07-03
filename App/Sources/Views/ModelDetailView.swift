import SwiftUI
import ModelPadCore

/// 右侧模型运行视图：状态 + 启停操作 + 日志，配置编辑移入弹窗。
public struct ModelDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel

    public init() {}

    public var body: some View {
        if let model = viewModel.editingModel {
            VStack(spacing: 0) {
                // 标题栏：模型名称 + 设置齿轮
                HStack {
                    Text(model.name)
                        .font(.headline)
                    Spacer()
                    Button(action: { viewModel.showConfigSheet = true }) {
                        Image(systemName: "gearshape")
                    }
                    .help("模型设置")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // 操作区
                actionSection(model: model)
                    .padding()

                Divider()

                // 日志区
                LogView(modelId: model.id)
                    .padding()
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .sheet(isPresented: $viewModel.showConfigSheet) {
                ModelConfigSheet()
            }
        }
    }

    // MARK: - 操作区

    private func actionSection(model: ModelConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("操作").font(.headline)

            HStack {
                let status = viewModel.statusMessages[model.id] ?? .stopped

                StatusBadge(status: status)

                if let pid = viewModel.pids[model.id] ?? nil {
                    Text("PID: \(pid)").font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { viewModel.startModel(model.id) }) {
                    Label("启动", systemImage: "play.fill")
                }
                .disabled(status == .running || status == .starting)

                Button(action: { viewModel.stopModel(model.id) }) {
                    Label("停止", systemImage: "stop.fill")
                }
                .disabled(status != .running && status != .starting)

                Button(action: { viewModel.restartModel(model.id) }) {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .disabled(status != .running)
            }
        }
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let status: ModelStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12))
        .cornerRadius(4)
    }

    private var statusColor: Color {
        switch status {
        case .stopped: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch status {
        case .stopped: return "已停止"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .error: return "错误"
        }
    }
}
