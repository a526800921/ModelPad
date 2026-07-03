# 计划：ModelPad LogBuffer 性能优化

## 目标

修复模型日志热路径上的 `LogBuffer` 锁竞争和数组移位开销：将当前基于 `Array.removeFirst` 的日志缓冲实现替换为真正的环形缓冲，使 `append` 在缓冲区满时仍保持 O(1)，降低高输出模型下的 CPU 和 UI 刷新竞争风险。

## 背景参考

参考外部分析文档：`/Users/jafish/.claude/plans/deep-jingling-pike.md`。

该分析指出：

- `LogBuffer.append` 是模型进程日志捕获热路径，由 `Pipe.readabilityHandler` 高频调用。
- 当前实现中，缓冲区满后 `entries.removeFirst(overflow)` 会触发数组元素移位。
- 默认 `maxLines = 2000` 时，每次溢出追加都可能在锁内做较大内存移动。
- 优化方向是预分配定长数组，使用 `writeIndex` 和有效计数实现环形缓冲。

## 范围

- 修改 `Sources/ModelPadCore/Logging/LogBuffer.swift`：
  - 使用预分配定长数组作为环形缓冲。
  - `append` 锁内操作保持 O(1)。
  - `all()` 返回按时间顺序排列的日志快照。
  - `count` 返回当前有效条目数。
  - `clear()` 重置计数和写入位置。
- 保持现有外部行为：
  - 最大行数限制不变。
  - 单行最大字符截断规则不变。
  - 日志返回顺序不变。
  - 每模型日志隔离不变。
- 补充边界测试：
  - `maxLines = 1` 单槽环形缓冲。
  - 缓冲区满后覆写顺序正确。

## 非范围

- 不改变日志 UI。
- 不改变 HTTP API 日志响应契约。
- 不改变 `ModelProcessManager` 的进程捕获方式，除非实现中发现必须调整。
- 不做日志落盘、搜索、分页或流式推送。

## 当前阶段

当前阶段：阶段 1 已完成。

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | 环形缓冲替换 | `modelpad-v1` 阶段 2 已完成；现有 LogBuffer 测试存在 | LogBuffer 现有测试通过，新增边界测试通过，全量测试通过 | 已完成 |

### 阶段 1 完成证据

阶段 1 已于 2026-07-03 完成。

**修改文件：**
| 文件 | 变更 |
|---|---|
| `Sources/ModelPadCore/Logging/LogBuffer.swift` | `Array.removeFirst` O(n) 替换为预分配定长数组环形缓冲 O(1)，`append` 满时直接覆写 `writeIndex` |
| `Tests/ModelPadCoreTests/LoggingTests/LogBufferTests.swift` | 新增 3 个边界测试：`maxLines=1` 单槽、满覆写顺序、`clear` 后重置 |

**验证结果：**
| 验收项 | 状态 | 证据 |
|---|---|---|
| LogBuffer 专项测试 | ✅ | 17 tests, 0 failures |
| 全量 swift test | ✅ | 110 tests, 0 failures |
| append O(1) 满时无 removeFirst | ✅ | 预分配数组 + writeIndex 覆写 |
| maxLines=1 单槽只保留最后一条 | ✅ | `singleSlotRingBuffer` |
| 满覆写保持时间顺序 | ✅ | `ringBufferOverwriteOrder` |
| clear 后正常追加 | ✅ | `clearResetsRingBuffer` |
| 现有测试不退化 | ✅ | 14 原有测试 + 3 新增全通过 |

## 阶段 1：环形缓冲替换

### Step 0 证据

- `LogBuffer` 当前位于 `Sources/ModelPadCore/Logging/LogBuffer.swift`。
- `ModelProcessManager` 通过 `captureOutput` 把 stdout/stderr 写入 `LogBuffer.append`。
- 现有测试位于 `Tests/ModelPadCoreTests/LoggingTests/LogBufferTests.swift`。
- 外部分析文档已指出 `removeFirst` 在锁内触发 O(n) 移位，是高输出模型下的潜在性能风险。

### 设计方向

使用预分配定长数组和写入指针：

```swift
private var buffer: [ModelLogEntry?]
private var writeIndex: Int = 0
private var currentCount: Int = 0
```

行为约束：

- 未满时从 `0..<currentCount` 返回。
- 满时 `writeIndex` 指向最旧元素，`all()` 从 `writeIndex` 环形读取。
- `append` 写入 `buffer[writeIndex]`，然后 `writeIndex = (writeIndex + 1) % maxLines`。
- `currentCount` 饱和增长到 `maxLines`。
- 锁仍使用 `NSLock`，并使用 `defer` 释放。

### 实施步骤

1. 修改 `LogBuffer` 内部数据结构为环形缓冲。
2. 保持 `append`、`all()`、`count`、`clear()` 的公开语义不变。
3. 新增 `maxLines = 1` 单槽边界测试。
4. 新增缓冲区满后覆写顺序测试。
5. 运行 `swift test --filter "LogBuffer"`。
6. 运行全量 `swift test`。
7. 如有可用高输出模型，手动观察日志展示顺序和 CPU 状态。

### 验证方式

阶段 1 完成时至少验证：

- `swift test --filter "LogBuffer"` 通过。
- `swift test` 全量通过。
- 现有日志截断、FIFO 淘汰、清空、计数、时间戳测试不退化。
- `maxLines = 1` 时多次追加只保留最后一条。
- 缓冲区满后 `all()` 仍按时间顺序返回。

### 完成条件

- `LogBuffer.append` 在缓冲区满时不再使用数组头部删除或 O(n) 移位。
- 现有日志行为兼容。
- 新增边界测试覆盖环形缓冲行为。
- 测试证据写入本文档，并同步 `docs/PLAN_MAP.md`。

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 环形遍历顺序错误 | UI/API 日志顺序错乱 | 用满缓冲覆写顺序测试覆盖 | 回退到原 `Array` 实现 |
| `clear()` 后旧元素引用未释放 | 暂时持有旧日志内存 | 如需要在 `clear()` 中 nil-out 有效槽位 | 回退或补清理逻辑 |
| 并发读写行为变化 | UI 刷新或日志捕获异常 | 保持 `NSLock` 包裹所有状态访问，全量测试和高输出手动验收 | 回退到原实现 |
