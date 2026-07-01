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
                Text("Logs").font(.headline)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll).font(.caption)
                Button("Clear") { viewModel.clearLogs(for: modelId) }
                    .font(.caption)
                Button("Copy") { copyLogs() }
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
                .frame(maxHeight: 200)
                .background(Color.black.opacity(0.06))
                .cornerRadius(6)
                .onChange(of: logs.count) { _ in
                    if autoScroll, !logs.isEmpty {
                        proxy.scrollTo("\(logs[logs.count - 1].time.timeIntervalSince1970)")
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            logs = viewModel.logs(for: modelId)
        }
    }

    private func copyLogs() {
        let text = logs.map { "[\($0.stream.rawValue)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - LogEntryRow

struct LogEntryRow: View {
    let entry: ModelLogEntry

    var body: some View {
        HStack(spacing: 4) {
            Text(streamLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(streamColor)
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(3)
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private var streamLabel: String {
        switch entry.stream {
        case .stdout: return "OUT"
        case .stderr: return "ERR"
        case .system: return "SYS"
        }
    }

    private var streamColor: Color {
        switch entry.stream {
        case .stdout: return .primary
        case .stderr: return .red
        case .system: return .blue
        }
    }
}
