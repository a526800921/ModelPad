import SwiftUI

/// 主窗口：左侧模型列表 + 右侧详情。
public struct MainWindow: View {
    @EnvironmentObject var viewModel: AppViewModel

    public init() {}

    public var body: some View {
        HSplitView {
            // 左侧：模型列表
            ModelListView()
                .frame(minWidth: 200, idealWidth: 240)
                .frame(maxWidth: 300)

            // 右侧：详情 + 日志
            if viewModel.selectedModelId != nil {
                ModelDetailView()
            } else {
                VStack {
                    Spacer()
                    Text("Select a model or create a new one")
                        .foregroundColor(.secondary)
                        .font(.title3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { viewModel.startAllModels() }) {
                    Label("Start All", systemImage: "play.fill")
                }
                .help("Start all stopped/error models")

                Button(action: { viewModel.stopAllModels() }) {
                    Label("Stop All", systemImage: "stop.fill")
                }
                .help("Stop all running models")
            }
        }
    }
}
