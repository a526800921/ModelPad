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


    }
}
