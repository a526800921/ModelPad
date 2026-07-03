# ModelPad CPU 和内存风险审查报告

审查时间：2026-07-03 19:54 CST

审查范围：

- `Sources/ModelPadCore/Logging/LogBuffer.swift`
- `Sources/ModelPadCore/Process/ModelProcessManager.swift`
- `Sources/ModelPadCore/API/APIServer.swift`
- `Sources/ModelPadCore/Process/TCPHealthChecker.swift`
- `Sources/ModelPadCore/Persistence/ConfigStore.swift`
- `App/Sources/AppViewModel.swift`
- `App/Sources/Views/LogView.swift`
- `App/Sources/AppDelegate.swift`
- `App/Sources/MenuBar/MenuBarController.swift`
- 当前计划文档：`docs/plans/modelpad-logbuffer-performance.md`

## 结论

当前代码里没有发现“空闲状态下必然持续高 CPU”或“无上限日志内存增长”的直接路径。窗口隐藏后状态轮询会暂停；无运行模型时状态轮询降频到 10 秒；日志缓冲默认有 `maxLines = 2000` 和 `maxLineLength = 8000` 的上限。

但仍存在几类性能风险，主要在高输出模型、频繁请求日志接口、日志窗口打开并持续刷新时被放大。最高优先级仍是已进入新计划的 `LogBuffer` 环形缓冲修复。

## 风险清单

| 优先级 | 风险 | 触发条件 | 影响 | 建议 |
|---|---|---|---|---|
| P1 | `LogBuffer.append` 满缓冲后使用 `removeFirst` | 模型持续高频输出日志，缓冲区达到 2000 行后继续追加 | 锁内 O(n) 数组移位，CPU 和锁竞争升高 | 按 `modelpad-logbuffer-performance` 阶段 1 改为预分配环形缓冲 |
| P1 | stdout/stderr 读取会先把整块 `Data` 转成 `String` 再 split | 子进程一次输出很大的块或超长单行 | 临时内存峰值不受 `maxLineLength` 限制；高输出时增加分配和复制 | 后续可增加分块/按行解析，或对单次 chunk 做软上限 |
| P1 | 日志 UI 每秒复制全量日志快照 | 日志面板打开，日志接近 2000 行，模型持续输出 | 主线程每秒替换 `logs` 数组，SwiftUI diff 和渲染成本升高 | 环形缓冲后继续优化为增量刷新或按版本号/尾部游标拉取 |
| P1 | `/api/models/:id/logs` 每次返回全量日志并 pretty print | 调用方频繁拉取日志，日志接近上限 | JSON 编码和网络响应分配较大；可能影响 API event loop 响应 | 增加 `limit` / `since` / `tail` 查询参数；关闭 pretty print 或仅开发态使用 |
| P2 | `ModelProcessManager.logs` 持有 manager 锁时调用 `LogBuffer.all()` | UI/API 高频读日志，stdout/stderr 高频写日志 | 嵌套锁和快照复制放大锁竞争；通常不致命 | 先取出 `LogBuffer` 引用再释放 manager 锁，再调用 `all()` |
| P2 | `AppViewModel.refreshStatus()` 每次刷新都会重建 Timer | 窗口可见时 2 秒或 10 秒轮询 | 不太可能造成高 CPU，但有不必要的 timer churn | 只在目标 interval 变化时重建 timer |
| P2 | 停止后的 context 保留日志、pipe、process 对象 | 多个模型多次运行后保持 stopped/error context | 每个模型最多保留约 2000 条日志；模型数量多时内存线性增长 | 若不需要保留停止后日志，可增加日志保留策略或手动清理入口 |
| P2 | API POST body 没有大小上限 | 本机调用方发送大 body 到 POST 接口 | `bodyBuffer` 可增长导致内存峰值；仅限本机接口 | 为 body 设置最大字节数，超过返回 413 |
| P3 | `ConfigStore.load()` 每次 API 查询模型都整文件读取 | 模型列表很大且 API 高频查询 | 小规模配置影响很低；大配置下有额外 IO/JSON 开销 | 后续可在 App 层维护只读快照，配置变更时刷新 |

## 重点证据

### 1. `LogBuffer` 实现仍是数组头删

位置：`Sources/ModelPadCore/Logging/LogBuffer.swift`

- `entries` 是普通数组。
- `append` 满缓冲后执行 `entries.removeFirst(overflow)`。
- 该操作发生在 `NSLock` 保护区内。

这会在高输出日志场景中把日志追加热路径变成锁内 O(n) 移位。该问题已经单独落地为计划：`docs/plans/modelpad-logbuffer-performance.md`。

### 2. stdout/stderr 捕获存在大块临时分配

位置：`Sources/ModelPadCore/Process/ModelProcessManager.swift`

`captureOutput` 当前流程：

1. `handle.availableData`
2. `String(data: data, encoding: .utf8)`
3. `text.split(separator: "\n")`
4. 每行 `String(line)` 后写入 `LogBuffer`

即使 `LogBuffer` 最终会按 8000 字符截断，截断发生在 append 内部，之前整块 `Data`、整块 `String`、split 结果和每行转换仍会产生临时内存。模型如果输出超长单行或短时间大量日志，会产生明显内存峰值和 CPU 分配成本。

### 3. 日志读取路径是全量快照

位置：

- `App/Sources/Views/LogView.swift`
- `App/Sources/AppViewModel.swift`
- `Sources/ModelPadCore/API/APIServer.swift`

UI 侧 `LogView` 每 1 秒执行一次 `viewModel.logs(for:)`，并把结果保存到本地 `@State logs`。API 侧 `GET /api/models/:id/logs` 每次返回全量日志数组。两条路径都会复制最多 2000 条日志，并在 UI 或 JSON 编码阶段继续分配。

单次规模可控，但高频调用时会变成 CPU 和内存分配压力。

### 4. 空闲轮询风险较低

位置：`App/Sources/AppViewModel.swift`

- 窗口隐藏时 `isWindowVisible == false`，`updateRefreshTimer()` 会直接返回，状态轮询暂停。
- 无运行模型时刷新间隔为 10 秒。
- 有运行模型时刷新间隔为 2 秒。

这条路径不像是空闲高 CPU 的主因。不过 `refreshStatus()` 每次都会调用 `updateRefreshTimer()`，导致 timer 每次触发后又被销毁重建，属于可以顺手优化的轻量问题。

### 5. 进程停止路径是阻塞等待，但不忙等

位置：

- `Sources/ModelPadCore/Process/ModelProcessManager.swift`
- `App/Sources/AppDelegate.swift`

停止进程时使用 `Thread.sleep` 间隔等待，不是 CPU 忙等。App 退出时清理放在后台线程，并有 30 秒兜底。这里主要风险是退出耗时或 API 响应被阻塞，不是高 CPU 或内存溢出。

## 建议处理顺序

1. 先实施 `modelpad-logbuffer-performance`：把 `LogBuffer` 改为环形缓冲，并补 `maxLines = 1`、满缓冲覆写顺序测试。
2. 同阶段或下一小步优化日志读取锁范围：`ModelProcessManager.logs` 先取 `LogBuffer` 引用后释放 manager 锁。
3. 增加日志拉取分页或 tail 能力：UI 和 API 都避免每秒/每次全量复制全部日志。
4. 对 `captureOutput` 增加分块/按行解析策略，降低超长单行和超大 chunk 的临时内存峰值。
5. 低优先级优化状态刷新 timer：只有 interval 或可见性变化时才重建 timer。
6. 给 API POST body 加大小上限，避免本机误调用导致内存峰值。

## 验证建议

建议后续实施时建立一个专门的性能回归脚本或测试模型：

- 高输出短行：每秒输出数千行，观察 `LogBuffer.append` 和 UI 刷新。
- 超长单行：单次输出数 MB 字符串，观察内存峰值。
- 高频日志 API：循环请求 `/api/models/:id/logs`，观察 API 线程和 CPU。
- 空闲模式：无模型运行、窗口关闭后观察 1-3 分钟 CPU 是否接近 0。

当前本次审查未运行性能压测，只做代码路径静态审查。
