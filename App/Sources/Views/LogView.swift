import SwiftUI
import ModelPadCore

/// 日志显示区：实时滚动、清空、复制。
public struct LogView: View {
    let modelId: UUID
    @EnvironmentObject var viewModel: AppViewModel
    @State private var logs: [ModelLogEntry] = []
    @State private var autoScroll = true

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(modelId: UUID) {
        self.modelId = modelId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题栏
            HStack {
                Text("日志").font(.headline)
                Spacer()
                Toggle("自动滚动", isOn: $autoScroll).font(.caption)
                Button("清空") { viewModel.clearLogs(for: modelId) }
                    .font(.caption)
                Button("复制") { copyLogs() }
                    .font(.caption)
            }

            // 日志内容
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, entry in
                            LogEntryRow(entry: entry)
                                .id("\(entry.time.timeIntervalSince1970)")
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
                .cornerRadius(6)
                .onChange(of: logs.count) { _, _ in
                    if autoScroll, !logs.isEmpty {
                        proxy.scrollTo("\(logs[logs.count - 1].time.timeIntervalSince1970)")
                    }
                }
            }
        }
        .onAppear {
            logs = viewModel.logs(for: modelId)
        }
        .onChange(of: modelId) { _, newId in
            logs = viewModel.logs(for: newId)
        }
        .onReceive(timer) { _ in
            logs = viewModel.logs(for: modelId)
        }
    }

    private func copyLogs() {
        let text = logs.map { $0.message }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - LogEntryRow

struct LogEntryRow: View {
    let entry: ModelLogEntry

    var body: some View {
        HStack(spacing: 4) {
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(streamColor)
                .lineLimit(3)
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private var streamColor: Color {
        switch entry.stream {
        case .stdout: return .primary
        case .stderr: return .red
        case .system: return .blue
        }
    }
}
