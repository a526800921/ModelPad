import SwiftUI
import ModelPadCore

/// 右侧模型详情区：配置编辑 + 操作 + 日志。
public struct ModelDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel

    public init() {}

    public var body: some View {
        if let model = viewModel.editingModel {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    configSection(model: model)
                    Divider()
                    actionSection(model: model)
                    Divider()
                    LogView(modelId: model.id)
                }
                .padding()
            }
        }
    }

    // MARK: - 配置区

    private func configSection(model: ModelConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配置").font(.headline)
                Spacer()
                if viewModel.hasUnsavedChanges {
                    Text("未保存").font(.caption).foregroundColor(.orange)
                }
                Button("保存") { viewModel.saveEditingModel(model) }
                    .disabled(!viewModel.hasUnsavedChanges)
            }

            // 名称
            fieldRow(label: "名称") {
                TextField("模型名称", text: Binding(
                    get: { model.name },
                    set: { viewModel.updateEditingModel(name: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            // 引擎
            fieldRow(label: "引擎") {
                Picker("", selection: Binding(
                    get: { model.engine },
                    set: { viewModel.updateEditingModel(engine: $0) }
                )) {
                    ForEach(Engine.allCases, id: \.self) { engine in
                        Text(engineDisplayName(engine)).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
            }

            // 命令
            fieldRow(label: "启动命令") {
                TextEditor(text: Binding(
                    get: { model.command },
                    set: { viewModel.updateEditingModel(command: $0) }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
            }

            // 端口
            fieldRow(label: "端口") {
                TextField("可选", value: Binding(
                    get: { model.port },
                    set: { viewModel.updateEditingModel(port: $0) }
                ), format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            }

            // 工作目录
            fieldRow(label: "工作目录") {
                TextField("可选", text: Binding(
                    get: { model.workDir ?? "" },
                    set: { viewModel.updateEditingModel(workDir: $0) }
                ))
                .textFieldStyle(.roundedBorder)
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

    // MARK: - 辅助

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }

    private func engineDisplayName(_ engine: Engine) -> String {
        switch engine {
        case .ollama: return "Ollama"
        case .llamacpp: return "llama.cpp"
        case .vllm: return "vLLM"
        case .custom: return "自定义"
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
