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
                    Text("选择一个模型，或新建模型")
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
                    Label("全部启动", systemImage: "play.fill")
                }
                .help("启动所有已停止或错误状态的模型")

                Button(action: { viewModel.stopAllModels() }) {
                    Label("全部停止", systemImage: "stop.fill")
                }
                .help("停止所有运行中的模型")
            }
        }
    }
}
