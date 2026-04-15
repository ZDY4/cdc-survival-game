# Bevy AI Map Editing Next Roadmap

本文件不再机械罗列“尚未完成的所有事项”，而是只保留对照当前仓库后，**仍建议继续开发** 的地图 AI 编辑路线。

已经确认但**不适合继续作为主计划项**的内容，会放在文末的“移出主计划”部分说明原因。

## 当前判断

对照当前代码，`bevy_map_editor` 已经具备这些基础能力：

- map 侧已经有 `proposal -> review -> apply -> save` 主闭环
- AI proposal 生成前，已经会动态构建 `generation_context`
- validator catalog 已经接入 `item / character / world tile` 相关 ID
- proposal review 已经提供结构化 diff，而不再只依赖 summary 和 raw output
- AI proposal 生成前已经有单图 preflight：
  - 会阻止基于当前存在 validation error 的地图继续生成 proposal
  - 会把 AI content catalog 的 load warnings 暴露到 UI 状态
- map 侧已经能完成基础浏览、校验、AI 生成和保存
- overworld 目前仍然是 `view-first`

因此当前真正限制落地效率的，不再是“有没有最小 AI 闭环”，而是：

- 高频的确定性编辑还缺少直接入口，仍然过度依赖自由文本 prompt
- overworld 还没有进入结构化 authoring，但这件事是否现在就做，需要看真实需求强度

## Recently Completed

### 1. Proposal Review Diff UX

已完成内容：

- proposal review 已经从“摘要 + raw output”提升为结构化 diff review
- 当前 review 会明确展示：
  - level 新增 / 删除
  - entry point 新增 / 删除 / 修改
  - object 新增 / 删除 / 修改
  - cell 在各 level 上的 added / removed / updated 汇总与样本
- diagnostics 会尽量挂到受影响对象、entry point 或 level 旁边

当前意义：

- 用户不再需要主要依赖 raw JSON 或模型原始输出判断 proposal 风险
- map AI 单图闭环的 review 成本已经明显下降

### 2. Map Schema / Validator / AI Catalog / Single-Map Loop Stability

已完成内容：

- map validator catalog 已接入 `item / character / world tile` 相关 ID
- AI generation context 已接入同类 catalog 信息
- 单图 proposal 生成前会先做 map preflight
- 若当前地图已有 validation error，会直接阻止继续生成 proposal
- 若 AI catalog 载入存在 warning，会通过 UI 状态暴露出来

当前意义：

- 单图 authoring 闭环已经比之前更稳，不再鼓励在已损坏的 map 草稿上继续叠加 proposal
- catalog / validator / generation context 三者的边界已经比前期更一致

## Roadmap Constraints

后续剩余工作继续遵守以下边界：

- `game_data` 继续作为唯一权威地图 / overworld 编辑内核
- `bevy_map_editor` 不直接实现第二套 JSON 修改规则
- 正式写盘继续保持 `proposal -> review -> apply -> save`
- 不重新引入 `tools/tauri_editor` 的地图 / overworld 编辑主路径
- 若启用 overworld authoring，也必须走共享 Rust 结构化命令模型

## Recommended Work

### 1. Focused Authoring Widgets

结论：**保留为后置项，但当前原型阶段不建议提到高优先级。**

原因：

- 当前工程仍处在关卡原型阶段，核心问题不是“操作入口不够多”，而是“proposal 是否可靠、review 是否足够直观、schema 是否稳定”
- `Focused Authoring Widgets` 主要解决的是生产期的编辑效率问题，而不是原型期的能力验证问题
- 如果现在就系统性补这类控件，容易过早把编辑器产品化，分散对地图模型、AI proposal 质量和 review 流程的注意力
- 这类操作本质上仍然有长期价值，因为高频确定性修改不应该永久依赖自由文本 prompt

建议调整后的开发目标：

- 当前阶段不做系统性 widget 开发
- 只在出现明显高频、重复、确定性修改痛点时，补单个最小控件
- 只补少量高频、确定性、共享 Rust 内核已经支持的操作入口
- UI 仍只调用 `game_data::MapEditorService`，不在前端直接改 JSON
- 第一批更适合做成 widget 的操作：
  - level add / remove
  - entry point upsert / remove
  - object upsert / remove 的基础表单入口
  - cell paint / clear 的受控入口
  - 常见 building / prop / pickup / ai_spawn 的最小字段编辑入口

不建议当前阶段做的事情：

- 一次性补齐所有 object kind 的复杂表单
- 在 UI 层单独维护第二套对象约束逻辑
- 把它作为当前原型阶段主线任务推进

完成定义：

- 常见确定性修改不必再强依赖自由文本 prompt
- 同时不破坏共享 Rust 内核的唯一权威地位

### 2. Overworld Structured Editing

结论：**值得保留，但应降为条件性第二优先级，而不是当前主线。**

原因：

- 从架构一致性看，map 已经进入结构化 authoring 闭环，而 overworld 仍停留在 view-first，长期确实不完整
- 但从当前工程状态看，map 侧的 review UX 和高频操作入口还没有补齐
- 如果在 map 主闭环体验还不够稳的时候就扩到 overworld，容易把编辑器面继续摊大

建议调整后的开发目标：

- 只有在出现明确 overworld authoring 需求时，再推进这项
- 一旦推进，必须先补共享 Rust 层的 overworld 结构化编辑命令与服务接口
- `bevy_map_editor` 侧只接 proposal review / apply / save 流程，不允许 UI 私有绕路

完成定义：

- 用户可对 overworld 完成一次结构化的“提案 -> 应用 -> 保存”
- 写盘、校验、规范化仍经过共享 Rust 内核

## Suggested Order

建议按以下顺序继续推进：

1. 先根据真实需求判断是否需要进入 overworld 结构化编辑
2. 只有在出现明确高频编辑痛点时，再补少量 focused authoring widgets

## Removed From Main Roadmap

### 1. Residual Tauri Retirement Cleanup

结论：**不再作为主计划项保留。**

原因：

- 这件事仍然有清理价值，但它本质上是低成本卫生项，不值得继续占据地图 AI 主路线图
- 当前残留主要是 `tools/tauri_editor` 中的旧测试名、fallback 文案或历史表述
- 更合适的处理方式是：单独做一次小清理，或在碰到相关文件时顺手清掉

处理建议：

- 不放在主计划中追踪
- 后续用一次独立 cleanup 提交解决

### 2. Batch Template Generation

结论：**当前不建议开发，先移出主计划。**

原因：

- 在 review UX 还不够强、widgets 还没补齐前，引入 batch generation 会放大错误传播面
- 当前地图 AI 输出约束和 proposal review 还没有成熟到适合批量化执行
- 如果连单张地图的改动风险都还不能低成本判断，批处理会让回滚、覆盖策略和结果验收复杂度明显上升

后续何时再考虑：

- 等 map proposal review 足够稳定
- 等高频确定性修改已有直接入口
- 等真正出现批量模板生成的明确生产需求

在那之前，不建议把它作为近阶段目标
