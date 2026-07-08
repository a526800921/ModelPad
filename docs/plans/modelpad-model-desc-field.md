# ModelPad 模型描述字段

## 目标

为模型配置新增 `desc` 描述字段，用于解释模型用途；在侧边栏列表中原引擎类型行改为展示 `desc`，并通过 API 对外暴露。

## 范围

- `ModelConfig` 新增 `desc: String?` 字段，向后兼容旧配置
- `ModelSummary`（API DTO）新增 `desc` 字段
- `ModelRow` 侧边栏列表将引擎类型行替换为 `desc`，空时显示 `-`
- `ModelConfigSheet` 配置弹窗新增描述输入框

## 非范围

- 菜单栏服务列表不展示 `desc`（菜单栏只展示服务名+状态点）
- 不修改 `ModelConfig` 其他字段的行为

## 阶段

### 阶段 1：数据模型、UI 和 API 新增 desc 字段

**状态**：已完成

**步骤**：

1. `ModelConfig.swift`：新增 `desc: String?`，CodingKey `"desc"`，init 默认 `nil`，`decodeIfPresent` 向后兼容，`encodeIfPresent`
2. `APIDTOs.swift`：`ModelSummary` 新增 `desc: String?`，构造函数透传
3. `ModelListView.swift`：`ModelRow` 底部行从 `engineDisplayName` 改为 `desc`，空时显示 `-`，移除未使用的 `engineDisplayName` 方法
4. `ModelConfigSheet.swift`：基本信息区新增描述 TextField，`populateFromModel`/`buildModel` 读写 `desc`

**验证方式**：`swift build` 编译通过；`swift test` 全部 145 个测试通过。

**完成条件**：构建和测试通过。

## 风险

- 无。新增可选字段，`decodeIfPresent` 保证旧配置文件完全兼容。

## 回滚

- 删除 `desc` 字段，恢复 `ModelRow` 中 `engineDisplayName` 即可。

## 未决问题

- 无。
