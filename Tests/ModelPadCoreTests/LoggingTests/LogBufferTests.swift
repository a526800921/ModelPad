import Foundation
import Testing

@testable import ModelPadCore

// MARK: - 基本操作

@Test("空缓冲返回空数组")
func emptyBufferReturnsEmpty() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 8000)
    #expect(buffer.all().isEmpty)
    #expect(buffer.count == 0)
}

@Test("追加一条日志后 all 返回该条")
func appendSingleEntry() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 8000)
    buffer.append(stream: .stdout, message: "hello")
    let entries = buffer.all()
    #expect(entries.count == 1)
    #expect(entries[0].stream == .stdout)
    #expect(entries[0].message == "hello")
}

@Test("追加多条日志按顺序返回")
func appendMultipleEntries() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 8000)
    buffer.append(stream: .stdout, message: "first")
    buffer.append(stream: .stderr, message: "second")
    buffer.append(stream: .system, message: "third")
    let entries = buffer.all()
    #expect(entries.count == 3)
    #expect(entries[0].message == "first")
    #expect(entries[1].message == "second")
    #expect(entries[2].message == "third")
}

// MARK: - 清空

@Test("clear 后缓冲为空")
func clearEmptiesBuffer() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 8000)
    buffer.append(stream: .stdout, message: "hello")
    #expect(buffer.count == 1)
    buffer.clear()
    #expect(buffer.count == 0)
    #expect(buffer.all().isEmpty)
}

// MARK: - 容量限制 / 环形缓冲

@Test("超过最大行数后 FIFO 淘汰旧条目")
func ringBufferEvictsOldestEntries() {
    let buffer = LogBuffer(maxLines: 5, maxLineLength: 8000)

    for i in 0..<7 {
        buffer.append(stream: .stdout, message: "line-\(i)")
    }

    let entries = buffer.all()
    #expect(entries.count == 5, "超过容量后应只保留最近 5 条")
    #expect(entries.first?.message == "line-2", "最早保留的应是第 3 条（index 2）")
    #expect(entries.last?.message == "line-6", "最后一条应是最新的")
}

@Test("容量边界精确")
func exactCapacityBoundary() {
    let buffer = LogBuffer(maxLines: 3, maxLineLength: 8000)
    buffer.append(stream: .stdout, message: "a")
    buffer.append(stream: .stdout, message: "b")
    buffer.append(stream: .stdout, message: "c")
    #expect(buffer.count == 3)

    // 第四条触发淘汰
    buffer.append(stream: .stdout, message: "d")
    #expect(buffer.count == 3)
    #expect(buffer.all()[0].message == "b")
    #expect(buffer.all()[2].message == "d")
}

// MARK: - 单行截断

@Test("单行超过最大长度时截断")
func truncateLongLine() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 10)
    let longMessage = String(repeating: "x", count: 25)
    buffer.append(stream: .stdout, message: longMessage)

    let entry = buffer.all().first!
    #expect(entry.message.count == 10)
    #expect(entry.message == String(repeating: "x", count: 10))
}

@Test("恰好等于最大长度时不截断")
func exactMaxLineLength() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 10)
    let exactMessage = String(repeating: "y", count: 10)
    buffer.append(stream: .stdout, message: exactMessage)

    let entry = buffer.all().first!
    #expect(entry.message.count == 10)
    #expect(entry.message == exactMessage)
}

@Test("短于最大长度时保持原样")
func shortLineUnchanged() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 8000)
    buffer.append(stream: .stderr, message: "short")
    #expect(buffer.all().first?.message == "short")
}

// MARK: - 隔离

@Test("两个 LogBuffer 实例相互独立")
func independentBuffers() {
    let buffer1 = LogBuffer(maxLines: 2000, maxLineLength: 8000)
    let buffer2 = LogBuffer(maxLines: 2000, maxLineLength: 8000)

    buffer1.append(stream: .stdout, message: "from-1")
    buffer2.append(stream: .stdout, message: "from-2")

    #expect(buffer1.all().count == 1)
    #expect(buffer1.all()[0].message == "from-1")
    #expect(buffer2.all().count == 1)
    #expect(buffer2.all()[0].message == "from-2")
}

// MARK: - 默认参数

@Test("默认参数：2000 行、8000 字符")
func defaultParameters() {
    let buffer = LogBuffer()
    #expect(buffer.maxLines == 2000)
    #expect(buffer.maxLineLength == 8000)
}

// MARK: - 环形缓冲边界

@Test("maxLines=1 单槽环形缓冲只保留最后一条")
func singleSlotRingBuffer() {
    let buffer = LogBuffer(maxLines: 1, maxLineLength: 8000)
    buffer.append(stream: .stdout, message: "first")
    #expect(buffer.count == 1)
    #expect(buffer.all()[0].message == "first")

    buffer.append(stream: .stdout, message: "second")
    #expect(buffer.count == 1)
    #expect(buffer.all()[0].message == "second")

    buffer.append(stream: .stderr, message: "third")
    #expect(buffer.count == 1)
    #expect(buffer.all()[0].message == "third")
}

@Test("缓冲区满后覆写保持时间顺序")
func ringBufferOverwriteOrder() {
    let buffer = LogBuffer(maxLines: 4, maxLineLength: 8000)

    // 填满
    for i in 0..<4 {
        buffer.append(stream: .stdout, message: "msg-\(i)")
    }
    var entries = buffer.all()
    #expect(entries.count == 4)
    #expect(entries.first?.message == "msg-0")
    #expect(entries.last?.message == "msg-3")

    // 覆写 2 条
    buffer.append(stream: .stdout, message: "msg-4")
    buffer.append(stream: .stdout, message: "msg-5")

    entries = buffer.all()
    #expect(entries.count == 4)
    // 最旧两条被覆盖：msg-0、msg-1 被淘汰
    #expect(entries.first?.message == "msg-2")
    #expect(entries[1].message == "msg-3")
    #expect(entries[2].message == "msg-4")
    #expect(entries[3].message == "msg-5")
}

@Test("clear 后环形缓冲重置可正常追加")
func clearResetsRingBuffer() {
    let buffer = LogBuffer(maxLines: 3, maxLineLength: 8000)

    // 填满并覆写
    for i in 0..<5 {
        buffer.append(stream: .stdout, message: "old-\(i)")
    }
    #expect(buffer.count == 3)

    // 清空
    buffer.clear()
    #expect(buffer.count == 0)
    #expect(buffer.all().isEmpty)

    // 重新追加
    buffer.append(stream: .stdout, message: "new-a")
    buffer.append(stream: .stderr, message: "new-b")
    #expect(buffer.count == 2)
    let entries = buffer.all()
    #expect(entries[0].message == "new-a")
    #expect(entries[1].message == "new-b")
}

// MARK: - 时间戳

@Test("每条日志都有时间戳")
func eachEntryHasTimestamp() {
    let buffer = LogBuffer(maxLines: 2000, maxLineLength: 8000)
    let before = Date()
    buffer.append(stream: .system, message: "test")
    let after = Date()

    let entry = buffer.all().first!
    #expect(entry.time >= before)
    #expect(entry.time <= after)
}
