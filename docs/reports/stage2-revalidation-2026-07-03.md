# ModelPad 菜单栏常驻和启动配置增强：阶段 2 复验报告

复验时间：2026-07-03 20:22 CST

复验对象：`docs/plans/modelpad-menu-bar-agent.md` 阶段 2：配置编辑弹窗和 Python 脚本启动配置。

## 结论

阶段 2 主体能力已落地，自动测试通过；但不建议把阶段 2 视为完全闭环，原因是 Python 脚本启动命令生成还有两个边界问题需要补进后续修复：

1. Python 脚本路径、Python 可执行文件和参数通过字符串拼接生成 shell 命令，遇到空格或 shell 特殊字符可能启动失败或行为异常。
2. 文档约束写明“相对脚本路径按模型 `workDir` 解析，`workDir` 为空时要求绝对路径”，当前实现没有校验该约束；相对路径且无工作目录时会交给 App 当前工作目录解析。

因此本次复验结论为：**阶段 2 自动/静态验收大体通过，存在 Python 脚本启动边界遗留问题，建议作为阶段 2 修复项或阶段 3 前置修复处理。**

## 已执行验证

### 自动测试

命令：

```bash
swift test
```

结果：

- 106 tests passed
- 0 failures
- 耗时约 5.7 秒

### 计划治理检查

命令：

```bash
python3 /Users/jafish/.codex/skills/plan-governance/scripts/check_plan_governance.py .
```

结果：

- 计划治理检查通过

## 验收项核对

| 验收项 | 结果 | 证据 |
|---|---|---|
| 旧版只含 `command` 的配置可以正常读取和保存 | 通过 | `ModelConfig.init(from:)` 对缺失 `launchMode` 默认 `.command`；测试 `modelConfigDecodeLegacyCommandOnly` 通过 |
| 新增 Python 脚本配置可以 JSON 编解码 | 通过 | `PythonScriptConfig` 为 `Codable`；测试 `pythonScriptConfigRoundtrip` 通过 |
| 右侧详情主区域只显示操作和日志 | 通过 | `ModelDetailView` 只包含标题、操作区、`LogView`，配置编辑移入 sheet |
| 面板顶部右上角不再出现启动/停止按钮 | 通过 | `MainWindow` 无 toolbar，未发现“全部启动/全部停止”入口 |
| 右上角设置按钮可打开配置弹窗 | 通过 | `ModelDetailView` 齿轮按钮设置 `showConfigSheet = true`，sheet 打开 `ModelConfigSheet` |
| 配置弹窗可以编辑、保存、取消模型配置 | 基本通过 | `ModelConfigSheet` 使用本地 `@State` 副本，保存时调用 `saveModelConfig`，取消只 dismiss |
| Python 脚本配置可以在配置弹窗中新增、编辑、保存 | 基本通过 | 弹窗包含脚本路径、Python 可执行文件、参数、工作目录、环境变量字段 |
| 通过 Python 脚本配置启动的模型由 ModelPad 托管 | 基本通过 | `ModelProcessManager` 使用 `config.effectiveCommand()` / `effectiveWorkDir()` / `effectiveEnv()` |
| 配置损坏备份和降级行为不受影响 | 通过 | 相关 `ConfigStore` 损坏配置测试通过 |

## 发现的问题

### P1：Python 脚本命令生成没有 shell 转义

位置：`Sources/ModelPadCore/Models/ModelConfig.swift`

当前 `effectiveCommand()` 在 Python 脚本模式下直接：

```swift
let py = script.pythonExecutable ?? "python3"
var parts = [py, script.scriptPath]
parts.append(contentsOf: script.arguments)
return parts.joined(separator: " ")
```

随后 `ModelProcessManager` 用：

```swift
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = ["-lc", config.effectiveCommand()]
```

影响：

- 脚本路径包含空格时会被 shell 拆开。
- 参数包含空格、引号、`$`、`;`、`&` 等字符时可能被错误解释。
- Python 可执行文件路径包含空格时同样会失败。

建议：

- 最小修复：对 Python 可执行文件、脚本路径和每个参数做 shell-safe quote。
- 更稳妥修复：Python 脚本模式不要经过 `/bin/zsh -lc` 字符串拼接，而是改为 `Process.executableURL = pythonExecutable`，`arguments = [scriptPath] + arguments`。但这会影响当前 `command` 字符串兼容路径，需要只对 `pythonScript` 模式特殊处理。

### P1：相对脚本路径约束没有被校验

位置：

- `Sources/ModelPadCore/Models/ModelConfig.swift`
- `App/Sources/Views/ModelConfigSheet.swift`

阶段 2 文档约束：

- Python 脚本路径必须支持绝对路径。
- 相对路径按模型 `workDir` 解析。
- `workDir` 为空时要求绝对路径。

当前实现：

- `effectiveWorkDir()` 返回 `pythonScript?.workDir ?? workDir`。
- 如果脚本路径是相对路径且 `workDir` 为空，没有校验或提示。
- 最终会交给当前进程工作目录解析，行为不确定。

建议：

- 保存配置时校验：`scriptPath` 为相对路径且有效工作目录为空时阻止保存或提示。
- 启动前校验：相对路径且无有效工作目录时不启动，记录错误日志。
- 测试覆盖该约束。

## 非阻塞观察

- `ModelConfigSheet` 使用 segmented picker 展示引擎；阶段 3 增加 `MLX` 后选项数会更多，可能需要确认宽度是否仍合适。
- `.app` 打包没有在本次复验中重新执行，因为本次只做代码和测试验收，未生成新的构建产物。
- 阶段 2 文档中的手动验收清单仍未勾选；本次复验不能替代用户手动确认真实 App 交互。

## 建议处理

1. 在进入 MLX 阶段 3 实现前，先补一个“阶段 2 遗留修复”：修复 Python 脚本命令转义和相对路径校验。
2. 修复后补充测试：
   - 脚本路径包含空格。
   - 参数包含空格。
   - 参数包含 shell 特殊字符。
   - 相对脚本路径且无有效工作目录时拒绝启动或保存。
3. 用户完成真实 App 手动验收后，再把阶段 2 手动验收清单勾选闭环。
