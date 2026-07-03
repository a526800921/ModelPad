import SwiftUI
import ModelPadCore

/// 模型配置编辑弹窗。
struct ModelConfigSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    // 本地编辑副本
    @State private var name: String = ""
    @State private var engine: Engine = .custom
    @State private var launchMode: LaunchMode = .command
    @State private var command: String = ""
    @State private var portText: String = ""
    @State private var workDir: String = ""
    @State private var envText: String = ""
    // Python 脚本字段
    @State private var scriptPath: String = ""
    @State private var pythonExe: String = ""
    @State private var scriptArgs: String = ""
    @State private var scriptWorkDir: String = ""
    @State private var scriptEnvText: String = ""
    @State private var showPathWarning = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("模型设置").font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("保存") { save() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 基本信息
                    fieldSection("基本信息") {
                        fieldRow(label: "名称") {
                            TextField("模型名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        fieldRow(label: "引擎") {
                            Picker("", selection: $engine) {
                                ForEach(Engine.allCases, id: \.self) { e in
                                    Text(engineDisplayName(e)).tag(e)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        fieldRow(label: "启动方式") {
                            Picker("", selection: $launchMode) {
                                Text("命令").tag(LaunchMode.command)
                                Text("Python 脚本").tag(LaunchMode.pythonScript)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }

                    // 命令模式
                    if launchMode == .command {
                        fieldSection("启动命令") {
                            TextEditor(text: $command)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.secondary.opacity(0.3))
                                )
                        }
                    }

                    // Python 脚本模式
                    if launchMode == .pythonScript {
                        fieldSection("Python 脚本") {
                            fieldRow(label: "脚本路径") {
                                TextField("/path/to/script.py", text: $scriptPath)
                                    .textFieldStyle(.roundedBorder)
                            }
                            fieldRow(label: "Python 可执行文件") {
                                TextField("python3", text: $pythonExe)
                                    .textFieldStyle(.roundedBorder)
                            }
                            fieldRow(label: "脚本参数（每行一个）") {
                                TextEditor(text: $scriptArgs)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(.secondary.opacity(0.3))
                                    )
                            }
                            fieldRow(label: "脚本工作目录") {
                                TextField("可选，留空使用模型工作目录", text: $scriptWorkDir)
                                    .textFieldStyle(.roundedBorder)
                            }
                            fieldRow(label: "脚本环境变量（KEY=VALUE，每行一个）") {
                                TextEditor(text: $scriptEnvText)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(.secondary.opacity(0.3))
                                    )
                            }
                        }
                    }

                    // 通用设置
                    fieldSection("运行设置") {
                        fieldRow(label: "端口（TCP 健康检查）") {
                            TextField("可选", text: $portText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                        fieldRow(label: "工作目录") {
                            TextField("可选", text: $workDir)
                                .textFieldStyle(.roundedBorder)
                        }
                        fieldRow(label: "环境变量（KEY=VALUE，每行一个）") {
                            TextEditor(text: $envText)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.secondary.opacity(0.3))
                                )
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 560)
        .onAppear { populateFromModel() }
        .alert("脚本路径无效", isPresented: $showPathWarning) {
            Button("返回修改", role: .cancel) {}
            Button("仍然保存") {
                if let model = buildModel() { doSave(model) }
            }
        } message: {
            Text("脚本路径是相对路径，但没有设置工作目录。启动时可能找不到脚本。建议使用绝对路径或设置工作目录。")
        }
    }

    // MARK: - 数据填充

    private func populateFromModel() {
        guard let model = viewModel.editingModel else { return }
        name = model.name
        engine = model.engine
        launchMode = model.launchMode
        command = model.command
        portText = model.port.map(String.init) ?? ""
        workDir = model.workDir ?? ""
        envText = envDictToString(model.env)

        if let script = model.pythonScript {
            scriptPath = script.scriptPath
            pythonExe = script.pythonExecutable ?? ""
            scriptArgs = script.arguments.joined(separator: "\n")
            scriptWorkDir = script.workDir ?? ""
            scriptEnvText = envDictToString(script.env)
        }
    }

    // MARK: - 保存

    private func save() {
        guard let model = buildModel() else { return }

        // 校验：脚本路径为相对路径且无工作目录时弹警告
        if !model.isPythonScriptPathValid {
            showPathWarning = true
            return
        }

        doSave(model)
    }

    private func buildModel() -> ModelConfig? {
        guard var model = viewModel.editingModel else { return nil }

        model.name = name
        model.engine = engine
        model.launchMode = launchMode
        model.command = command
        model.workDir = workDir.isEmpty ? nil : workDir
        model.env = envStringToDict(envText)
        model.port = Int(portText).flatMap { $0 > 0 ? $0 : nil }

        if launchMode == .pythonScript {
            let pyWorkDir = scriptWorkDir.isEmpty ? nil : scriptWorkDir
            let pyEnv = envStringToDict(scriptEnvText)
            let args = scriptArgs
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
            model.pythonScript = PythonScriptConfig(
                scriptPath: scriptPath,
                arguments: args,
                pythonExecutable: pythonExe.isEmpty ? nil : pythonExe,
                workDir: pyWorkDir,
                env: pyEnv
            )
        } else {
            model.pythonScript = nil
        }

        return model
    }

    private func doSave(_ model: ModelConfig) {
        viewModel.saveModelConfig(model)
        dismiss()
    }

    // MARK: - 辅助

    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            content()
        }
    }

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
        case .mlx: return "MLX"
        }
    }

    private func envDictToString(_ env: [String: String]) -> String {
        env.map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "\n")
    }

    private func envStringToDict(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = String(line).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    result[key] = value
                }
            }
        }
        return result
    }
}
