# 计划：ModelPad 菜单栏常驻和启动配置增强

## 目标

让 ModelPad 像 TranslateBar 一样作为菜单栏常驻 App 运行：启动后不出现在程序坞，只在系统右上角菜单栏显示图标，通过菜单栏图标打开面板和退出。

本计划同时吸收后续配置增强：模型配置需要支持 `py` 脚本配置，因为现有模型会依赖 Python 脚本启动。

后续阶段还需要补齐引擎分类：当前 `Engine` 枚举和设置弹窗只有 `ollama`、`llamacpp`、`vllm`、`custom`，但已有模型使用 `mlx_lm.server`，因此需要增加 `mlx` 引擎选项。

## 背景参考

- TranslateBar 是菜单栏 App，参考项目路径：`/Users/jafish/Documents/work/TranslateBar`。
- TranslateBar 的隐藏程序坞行为来自 `LSUIElement = YES`，其文档也明确“应用不出现在 Dock，仅菜单栏”。
- ModelPad 阶段 5 已完成菜单栏左键打开面板、右键显示 `显示面板` / `退出`。
- ModelPad 阶段 6 已完成 `.app` 打包入口和自定义图标。

## 范围

- ModelPad `.app` 启动后不出现在程序坞。
- ModelPad 仍在系统右上角菜单栏显示图标。
- 菜单栏图标左键点击显示下拉菜单。
- 左键下拉菜单只包含：
  - `显示面板`
  - `退出`
- 移除菜单栏图标右键事件，不再依赖右键菜单。
- 左键菜单中的 `退出` 不弹确认，直接进入完整退出流程：停止全部托管模型、停止 API Server、结束 App 进程。
- 保持 Finder 双击、`open dist/ModelPad.app` 和应用列表启动方式可用。
- 打包产物中的 `Info.plist` 应包含隐藏程序坞所需配置。
- 模型配置支持 Python 脚本启动配置：
  - 可记录脚本路径、工作目录、参数和必要环境变量。
  - 启动时仍由 ModelPad 托管进程生命周期。
  - 兼容现有 `command` 字符串配置；现有配置不得丢失或被强制迁移。
- 模型右侧详情界面改为运行视图：
  - 主区域只保留操作和日志。
  - 模型配置编辑不再直接铺在右侧主区域。
  - 右上角提供悬浮设置按钮。
  - 点击设置按钮打开弹窗，在弹窗内编辑模型配置。

## 非范围

- 不新增菜单栏模型列表、启停模型、全部启动或全部停止功能。
- 不新增登录项、开机自启或安装器。
- 不修改本地 HTTP API。
- 不改变模型进程托管、健康检查和日志行为。
- 不内置具体业务 Python 脚本内容，ModelPad 只保存和执行用户配置。
- 阶段 3 增加 MLX 引擎分类，仅用于配置分类、列表展示、筛选和启动模板；不引入 MLX 专用启动逻辑或健康检查。

## 当前阶段

当前阶段：阶段 3 已完成。三个计划阶段全部闭环。

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | 菜单栏交互调整和隐藏程序坞 | `modelpad-v1` 阶段 6 完成 | `.app` 启动后 Dock 不出现 ModelPad；菜单栏左键显示 `显示面板` / `退出` 下拉菜单；无右键事件依赖 | 已完成 |
| 阶段 2 | 配置编辑弹窗和 Python 脚本启动配置 | 阶段 1 完成 | 右侧详情只保留操作和日志；右上角设置按钮打开配置弹窗；模型配置可保存 py 脚本路径、参数、工作目录和环境变量，并通过托管进程启动 | 已完成 |
| 阶段 3 | MLX 引擎选项和 API 启停后的 UI 状态同步 | 阶段 2 完成 | 设置弹窗引擎列表包含 MLX；模型列表正确展示 MLX；配置 JSON 可编解码 `engine: "mlx"`；外部 API 启停模型后主面板状态能及时更新 | 已完成 |

## 阶段 1 候选：菜单栏交互调整和隐藏程序坞

### Step 0 证据

- 当前 ModelPad `App/Resources/Info.plist` 尚未声明 `LSUIElement`。
- 当前 ModelPad 已有 `NSStatusBar` 菜单栏图标。
- 当前 ModelPad 菜单栏交互是左键打开面板、右键菜单显示 `显示面板` / `退出`。
- 用户新增要求：菜单栏 icon 左键点击出现下拉菜单，把原右键功能放到左键，移除右键事件。
- TranslateBar 参考实现使用 `LSUIElement = YES` 隐藏程序坞图标。

### 实施方向

- 在 `App/Resources/Info.plist` 中增加：

```xml
<key>LSUIElement</key>
<true/>
```

- 如 `.app` 启动后仍存在激活策略不一致，再评估是否在 App 启动阶段补充 `NSApp.setActivationPolicy(.accessory)`。
- 打包脚本无需改变行为，只需继续复制 `Info.plist` 到 `.app`。
- 调整 `MenuBarController` 交互：
  - 左键点击菜单栏图标弹出 `NSMenu`。
  - 菜单项只包含 `显示面板` 和 `退出`。
  - 移除右键事件监听和右键菜单路径。
  - `显示面板` 复用现有打开/显示主面板逻辑。
  - `退出` 复用现有完整退出流程。

### 验证方式

阶段 1 完成时至少验证：

- `plutil -p dist/ModelPad.app/Contents/Info.plist` 显示 `LSUIElement => true`。
- `open dist/ModelPad.app` 后程序坞不出现 ModelPad 图标。
- 菜单栏出现 ModelPad 图标。
- 菜单栏左键显示下拉菜单。
- 左键下拉菜单只有 `显示面板` 和 `退出`。
- 菜单栏右键不再承担功能，不再依赖右键事件。
- 左键菜单 `显示面板` 可以打开主面板。
- 左键菜单 `退出` 可以结束 App。
- 退出后托管模型进程和 API Server 无残留。

### 完成条件

- ModelPad 以菜单栏常驻模式运行，不出现在程序坞。
- 菜单栏左键下拉菜单、打开面板和退出流程通过手动验收。
- 构建、测试和 `.app` 打包验证通过。
- 完成证据写入本文档，并同步 `docs/PLAN_MAP.md`。

### 阶段 1 完成证据

阶段 1 已于 2026-07-03 完成。

**实现内容：**
- `App/Resources/Info.plist` 已增加 `LSUIElement = true`。
- `MenuBarController` 已改为 `statusItem.menu = buildMenu()`，左键点击菜单栏图标弹出下拉菜单。
- 下拉菜单包含 `显示面板` 和 `退出`。
- 原右键事件监听路径已移除，代码中不再存在 `rightMouseUp` / `addLocalMonitor` 右键菜单路径。

**验证结果：**
| 验收项 | 状态 | 证据 |
|---|---|---|
| `Info.plist` 声明 `LSUIElement` | ✅ | `plutil -p App/Resources/Info.plist` 显示 `LSUIElement => true` |
| `.app` 打包产物声明 `LSUIElement` | ✅ | `dist/ModelPad.app/Contents/Info.plist` 显示 `LSUIElement => true` |
| 左键显示下拉菜单 | ✅ | 用户已完成手动验收 |
| 下拉菜单包含 `显示面板` / `退出` | ✅ | 用户已完成手动验收 |
| `显示面板` 可打开主面板 | ✅ | 用户已完成手动验收 |
| `退出` 可结束 App | ✅ | 用户已完成手动验收 |
| 启动后不出现在程序坞 | ✅ | 用户已完成手动验收 |
| 右键事件不再作为功能入口 | ✅ | 静态核对通过：未发现 `rightMouseUp` / `addLocalMonitor` |

**备注：**
- 验收时发现 `App/Sources/Views/ModelListView.swift` 同时存在“移除模型列表新增按钮”的变更。该变更不属于阶段 1 范围，更接近阶段 2 UI 精简，应在阶段 2 继续确认是否保留。

## 阶段 2 候选：配置编辑弹窗和 Python 脚本启动配置

### Step 0 证据

- 当前 `ModelConfig` 以 `command` 字符串保存完整启动命令。
- 现有模型中存在依赖 Python 脚本启动的场景。
- 用户新增要求：配置里面增加 py 脚本的配置，因为现有模型会依赖 py 脚本启动。
- 当前模型右侧详情界面同时承载配置编辑、操作和日志，密度较高。
- 用户新增要求：模型右侧配置界面调整为只有操作和日志；右上角悬浮设置按钮点击后打开弹窗，并在弹窗内编辑模型配置。
- 用户新增要求：面板顶部右上角的启动和停止入口去掉，避免和模型详情内操作重复。
- 用户确认 `App/Sources/Views/ModelListView.swift` 中移除模型列表标题栏新增按钮是用户主动变更；左下角已有 `添加` 按钮，阶段 2 应保留左下角新增入口，不恢复标题栏 `+`。

### UI 调整方向

- `ModelDetailView` 主区域定位为运行视图，只展示：
  - 模型运行状态和操作按钮。
  - 日志区域。
- 面板顶部右上角不再显示启动/停止按钮；模型启停操作保留在当前模型详情运行视图内。
- 模型列表标题栏不恢复新增按钮；保留左下角 `添加` 按钮作为新增模型入口。
- 新增模型后应进入配置弹窗流程，避免右侧运行视图重新铺开配置字段。
- 配置编辑移入弹窗：
  - 右上角提供设置按钮，建议使用齿轮图标。
  - 点击后打开配置弹窗或 sheet。
  - 弹窗内编辑模型名称、引擎、端口、工作目录、环境变量、启动方式和命令/脚本配置。
  - 弹窗内提供保存/取消；取消不应污染已保存配置。
- 删除、保存、未保存状态和启动前自动保存行为需要重新验收，避免配置编辑从主区域迁移到弹窗后丢失既有能力。

### Python 脚本配置方向

在保持现有 `command` 字符串兼容的前提下，增加可选 Python 脚本配置字段。阶段 2 默认采用以下 Schema：

```swift
struct PythonScriptConfig: Codable, Equatable, Sendable {
    var scriptPath: String
    var arguments: [String]
    var pythonExecutable: String?
    var workDir: String?
    var env: [String: String]
}
```

约束：

- `command` 仍是兼容事实源，现有模型配置继续可用。
- 增加启动模式概念，至少支持 `command` 和 `pythonScript` 两种模式。
- 如果模型选择 Python 脚本模式，启动命令由脚本配置生成，但最终仍交给 `ModelProcessManager` 托管。
- Python 脚本路径必须支持绝对路径；相对路径按模型 `workDir` 解析。
- `pythonExecutable` 为空时默认使用 `python3`。
- UI 需要能编辑脚本路径、参数、Python 可执行文件、工作目录和环境变量。

### 实施步骤

1. 扩展模型配置数据结构，增加 Python 脚本配置和启动模式，保持旧 `command` 配置可解码。
2. 更新配置持久化测试，覆盖旧配置兼容、新字段编解码、损坏配置备份和保存读取往返。
3. 增加启动命令生成逻辑：`command` 模式沿用原字符串；`pythonScript` 模式由脚本配置生成最终命令。
4. 调整 `ModelDetailView` 为运行视图，只保留状态、当前模型启停/重启操作和日志。
5. 新增设置按钮和配置弹窗，在弹窗内编辑模型配置并保留保存/取消语义。
6. 保留用户已做的模型列表新增按钮移除方向，左下角 `添加` 作为新增模型入口。
7. 复验启动前自动保存、删除运行中模型、日志切换、退出清理。
8. 运行 `swift test` 和 `.app` 打包验证。

### 验证方式

阶段 2 完成时至少验证：

- 旧版只含 `command` 的配置可以正常读取和保存。
- 新增 Python 脚本配置可以 JSON 编解码。
- 右侧详情主区域只显示操作和日志，不直接铺开配置字段。
- 面板顶部右上角不再出现启动/停止按钮。
- 右上角悬浮设置按钮可打开配置弹窗。
- 配置弹窗可以编辑、保存、取消模型配置。
- Python 脚本配置可以在配置弹窗中新增、编辑、保存。
- 通过 Python 脚本配置启动的模型由 ModelPad 托管，状态、日志、停止和退出清理正常。
- 配置损坏备份和降级行为不受影响。

### 完成条件

- Python 脚本启动配置 Schema 明确并写入计划。
- 兼容旧配置。
- 右侧详情运行视图和配置弹窗交互通过验收。
- UI 和进程托管行为通过测试或手动验收。
- 完成证据写入本文档，并同步 `docs/PLAN_MAP.md`。

### 阶段 2 完成证据

阶段 2 已于 2026-07-03 完成。

**新增文件：**
| 文件 | 说明 |
|---|---|
| `Sources/ModelPadCore/Models/LaunchMode.swift` | 启动模式枚举（`.command` / `.pythonScript`） |
| `Sources/ModelPadCore/Models/PythonScriptConfig.swift` | Python 脚本配置 struct |
| `App/Sources/Views/ModelConfigSheet.swift` | 配置编辑弹窗 |

**修改文件：**
| 文件 | 变更 |
|---|---|
| `Sources/ModelPadCore/Models/ModelConfig.swift` | 新增 `launchMode`、`pythonScript` 字段；自定义 `Codable` 向后兼容旧配置；新增 `effectiveCommand()`、`effectiveWorkDir()`、`effectiveEnv()` 方法 |
| `Sources/ModelPadCore/Process/ModelProcessManager.swift` | 改用 `effectiveCommand()`、`effectiveWorkDir()`、`effectiveEnv()` |
| `App/Sources/Views/MainWindow.swift` | 移除右上角"全部启动"/"全部停止"工具栏按钮 |
| `App/Sources/Views/ModelDetailView.swift` | 重写为运行视图：只保留状态 + 启停操作 + 日志；右上角齿轮按钮打开配置弹窗 |
| `App/Sources/AppViewModel.swift` | 新增 `showConfigSheet` 属性；新增 `saveModelConfig(_:)` 方法；`newModel()` 自动弹出配置弹窗 |
| `Tests/ModelPadCoreTests/ModelEncodingTests.swift` | 新增 12 个测试覆盖：PythonScriptConfig 编解码、LaunchMode 编解码、旧配置兼容、effectiveCommand/WorkDir/Env |

**验证结果：**
| 验收项 | 状态 | 证据 |
|---|---|---|
| 旧版只含 `command` 的配置可正常读取保存 | ✅ | 测试 `modelConfigDecodeLegacyCommandOnly` 通过 |
| 新增 Python 脚本配置 JSON 编解码 | ✅ | 测试 `pythonScriptConfigRoundtrip` 通过 |
| 右侧详情主区域只显示操作和日志 | ✅ | `ModelDetailView` 已移除 configSection |
| 面板顶部右上角无启动/停止按钮 | ✅ | `MainWindow` 已移除 toolbar |
| 右上角齿轮按钮可打开配置弹窗 | ✅ | 齿轮按钮 → `showConfigSheet` → `ModelConfigSheet` sheet |
| 配置弹窗可编辑保存取消 | ✅ | `ModelConfigSheet` 本地副本 + 保存/取消按钮 |
| Python 脚本配置可在弹窗中编辑保存 | ✅ | Script path / python exe / args / workDir / env 全部可编辑 |
| Swift 测试全部通过 | ✅ | 106 tests, 0 failures |
| `.app` 打包通过 | ✅ | `build_app.sh` 成功 |

**手动验收清单：**
- [x] `open dist/ModelPad.app` 启动后，右侧详情只显示模型名称、齿轮按钮、操作区和日志
- [x] 点击齿轮按钮打开配置弹窗，可编辑所有字段
- [x] 启动方式切换为 Python 脚本后显示脚本配置字段
- [x] 保存配置后可正常启动/停止模型
- [x] 取消配置弹窗后模型配置不变
- [x] 点击左下角 `添加` 按钮后自动弹出配置弹窗
- [x] 退出后模型进程和 API Server 无残留

## 阶段 3 候选：MLX 引擎选项和 API 启停后的 UI 状态同步

### Step 0 证据

- 当前 `Sources/ModelPadCore/Models/Engine.swift` 只包含：
  - `ollama`
  - `llamacpp`
  - `vllm`
  - `custom`
- 当前配置弹窗和模型列表都通过 `Engine.allCases` 展示引擎，因此 `Engine` 枚举缺少 `mlx` 会导致 UI 中没有 MLX 选项。
- `docs/plans/modelpad-workflow-compat.md` 已记录 `fanyi` 模型命令内联启动 `mlx_lm.server`，说明项目已有 MLX 使用场景。
- `Engine` 的既有定义只用于分类、图标、筛选和启动命令模板，不决定启动逻辑。
- 当前主面板状态来自 `AppViewModel.statusMessages` / `pids`。
- App 内点击启停按钮会在后台操作完成后调用 `refreshStatus()`。
- 外部调用本地 HTTP API 的 `/api/models/:id/start`、`/stop`、`/restart` 时，`APIServer` 直接操作 `ModelProcessManager`，不会通知 `AppViewModel` 立即刷新，因此界面可能要等下一次轮询，或在窗口隐藏/轮询暂停时长期不变。
- 用户新增缺陷反馈：接口对模型进行启停时，界面无实时变化；修复放到下个阶段。

### 范围

- 在 `Engine` 中增加 `mlx` 枚举值，JSON raw value 使用 `"mlx"`。
- 设置弹窗“引擎”选项展示 `MLX`。
- 模型列表中的引擎标签展示 `MLX`。
- 补充编解码测试，覆盖 `engine: "mlx"`。
- 如存在启动命令模板，新增 MLX 模板示例；没有模板系统则不强行新增。
- API 启停模型后，主面板应及时反映状态和 PID 变化。
- 刷新机制应避免恢复高频空闲轮询；窗口隐藏时可以选择记录脏状态，待面板显示时刷新。

### 非范围

- 不新增 MLX 专用启动逻辑。
- 不新增 MLX 专用健康检查。
- 不改变 Python 脚本配置、`command` 配置或进程托管逻辑。
- 不自动迁移现有 `custom` 模型到 `mlx`；用户可手动修改分类。
- 不新增外部 API 的配置写入能力。
- 不引入远程推送或 WebSocket；本阶段只解决本机 App 进程内 API 操作后的 UI 状态同步。

### 实施步骤

1. 更新 `Engine` 枚举，增加 `case mlx`。
2. 更新设置弹窗和模型列表的引擎显示名映射，`mlx` 显示为 `MLX`。
3. 更新测试，覆盖 `Engine.allCases` 往返和 `engine: "mlx"` 解码。
4. 为 API 启停路径增加 App 内状态刷新通知机制，候选方式：
   - `APIServer` 在 start/stop/restart 成功后调用一个可选回调，由 App 层绑定到 `AppViewModel.refreshStatus()`。
   - 或由 `ModelProcessManager` 发布轻量状态变更事件，App 层订阅后刷新。
5. 确保回调切回主线程更新 `@Published` 状态。
6. 如相关文档或示例列出引擎清单，同步加入 MLX。
7. 运行 `swift test`。
8. 手动或脚本验证 API 启停后 UI 状态及时更新。

### 阶段 3 完成证据

阶段 3 已于 2026-07-03 完成。

**修改文件：**
| 文件 | 变更 |
|---|---|
| `Sources/ModelPadCore/Models/Engine.swift` | 新增 `case mlx` |
| `App/Sources/Views/ModelListView.swift` | engineDisplayName 新增 `"MLX"` |
| `App/Sources/Views/ModelConfigSheet.swift` | engineDisplayName 新增 `"MLX"` |
| `Sources/ModelPadCore/API/APIServer.swift` | 新增 `onModelStateChanged` 回调，启停操作后触发 |
| `App/Sources/AppDelegate.swift` | 绑定回调到 `viewModel.refreshStatus()` |
| `Tests/ModelPadCoreTests/ModelEncodingTests.swift` | 新增 `engineDecodeMLXFromJSON` 测试 |

**验证结果：**
| 验收项 | 状态 |
|---|---|
| Engine.allCases 包含 mlx，JSON `"mlx"` 可编解码 | ✅ 107 tests |
| 旧配置 ollama/llamacpp/vllm/custom 正常 | ✅ 107 tests |
| API 启停后 UI 状态即时刷新 | ✅ 回调 → refreshStatus |
| swift test 通过 | ✅ 107 tests |
| 真实运行验收 | ✅ 用户确认已闭环 |

### 验证方式

阶段 3 完成时至少验证：

- 设置弹窗引擎分段控件或选择控件中可选择 `MLX`。
- 模型保存为 MLX 后，配置 JSON 中 `engine` 为 `"mlx"`。
- 重新启动 App 或重新加载配置后，MLX 分类保持不丢失。
- 模型列表展示 `MLX`。
- 旧配置中的 `ollama`、`llamacpp`、`vllm`、`custom` 仍可正常读取。
- 通过 `POST /api/models/:id/start` 启动模型后，主面板状态从停止更新为启动中或运行中，不需要用户手动点击刷新或重新选择模型。
- 通过 `POST /api/models/:id/stop` 停止模型后，主面板状态和 PID 及时更新。
- 通过 `POST /api/models/:id/restart` 重启模型后，主面板状态和 PID 及时更新。
- 窗口隐藏期间外部 API 启停模型后，再打开面板时状态是最新的。
- `swift test` 通过。

真实运行验收放在阶段 3 末尾执行：

- 构建或启动真实 `dist/ModelPad.app`，确认默认 `9786` 端口监听。
- 使用 `curl http://127.0.0.1:9786/api/health` 验证真实 App 实例返回成功。
- 使用 `curl http://127.0.0.1:9786/api/models` 验证真实 App 实例可读取当前配置模型列表。
- 对一个可安全启停的测试模型执行真实 API：
  - `POST /api/models/:id/start`
  - `POST /api/models/:id/stop`
  - `POST /api/models/:id/restart`
  - `GET /api/models/:id/logs`
  - `POST /api/models/:id/logs/clear`
- 真实 API 启停后，观察主面板状态和 PID 是否及时变化。
- 验证禁止接口在真实 App 实例中仍不开放：
  - `POST /api/models`
  - `PUT /api/models/:id`
  - `DELETE /api/models/:id`
- 验证模型摘要仍不泄露 `command`、`workDir`、`env`。
- 验收结束后退出 App，确认 API 端口释放，托管模型进程无残留。

### 完成条件

- MLX 作为正式引擎分类进入配置 Schema。
- UI 可选择和展示 MLX。
- 编解码测试覆盖 MLX。
- 不引入 MLX 专用启动或健康检查行为。
- API 启停、重启模型后，主面板状态同步通过测试或手动验收。
- 真实运行 App 实例的 HTTP API 验收完成，测试契约和真实端口行为一致。
- 不回退阶段 5 的空闲功耗优化。
- 完成证据写入本文档，并同步 `docs/PLAN_MAP.md`。

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 隐藏程序坞后用户找不到退出入口 | 无 Dock 菜单可退出 | 左键下拉菜单保留 `退出`，并验收退出流程 | 移除 `LSUIElement` |
| `Cmd+Q` 行为与无 Dock App 的激活状态相关 | 快捷键可能依赖窗口是否激活 | 以菜单栏左键下拉菜单 `退出` 作为可靠退出入口，`Cmd+Q` 作为补充验收 | 移除 `LSUIElement` 或调整激活策略 |
| Python 脚本配置与 `command` 双事实源冲突 | 启动行为难以预测 | 保持 `command` 兼容，脚本模式生成命令前需明确优先级 | 回退到只使用 `command` |
| 配置编辑移入弹窗后保存路径遗漏 | 用户编辑后未保存或启动前未自动保存 | 保留保存/取消语义，并复验启动前自动保存、删除运行中模型等既有流程 | 回退到主区域配置编辑 |

## 测试覆盖率

- 阶段 3 验收运行 `swift test`，结果为 107 tests passed，0 failures。
- 覆盖重点包括 `Engine.mlx` JSON 编解码、旧引擎配置兼容、API 契约、模型启停、日志、配置持久化和 App ViewModel 行为。
- 真实运行验收已由用户确认闭环：真实 App 默认 `9786` 端口、允许接口、禁止配置写入接口、敏感字段不泄露、API 启停后的 UI 状态同步和退出清理均已完成验收。

## 阶段 2 实施前确认项

| 问题 | 默认方案 | 是否需要用户确认 | 状态 |
|---|---|---|---|
| 新增模型入口放在哪里 | 保留左下角 `添加` 按钮，不恢复标题栏 `+`；新增后进入配置弹窗流程 | 否 | 已确认 |
| Python 脚本参数如何编辑 | 第一版使用逐行文本或简单数组编辑，保存为 `[String]` | 可实施后按 UI 验收调整 | 默认可实施 |
| Python 脚本相对路径如何解析 | 相对路径按模型 `workDir` 解析，`workDir` 为空时要求绝对路径 | 否 | 已定 |
| `pythonExecutable` 为空时使用什么 | 默认 `python3` | 否 | 已定 |
| 旧 `command` 配置是否迁移 | 不强制迁移；旧配置保持 `command` 模式 | 否 | 已定 |
