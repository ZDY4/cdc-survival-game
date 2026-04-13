# Bevy AI Map Editing Remaining Work

本文件仅保留对照当前仓库后，尚未完成的部分。

## Remaining Constraints

后续剩余工作继续遵守以下边界：

- `game_data` 继续作为唯一权威地图/overworld 编辑内核
- `bevy_map_editor` 不直接实现第二套 JSON 修改规则
- 正式写盘继续保持 `proposal -> review -> apply -> save`
- 不重新引入 `tools/tauri_editor` 的地图/overworld 编辑主路径
- 若启用 overworld authoring，也必须走共享 Rust 结构化命令模型

## Remaining Work

### 1. Residual Tauri Retirement Cleanup

`tools/tauri_editor` 的地图模块主链已经退场，但仍应清理残留的旧入口表述，避免继续暗示存在地图 surface。

待完成项：

- 清理 `tools/tauri_editor` 中残留的旧地图入口兼容字样
- 清理测试名、启动 surface fallback 等仍引用 `"maps"` 的表述
- 如仍有 README 或菜单描述残留旧地图入口，统一移除或改成明确的“已下线”说明

完成定义：

- `tools/tauri_editor` 中不再出现会让人误解为仍支持地图编辑的入口表述

### 2. Better Proposal Review UX

当前编辑器已经能展示 summary、warnings、diagnostics 与原始输出，但还缺少更强的 proposal 差异可视化。

待完成项：

- 为 proposal 提供更强的 diff 可视化，而不只是文字摘要
- 明确展示 level / entry point / object / cell 级别的新增、删除、修改
- 在 review 阶段把 diagnostics 与受影响区域的关系展示得更直接

完成定义：

- 用户无需直接阅读原始 JSON 或原始模型输出，也能判断 proposal 的实际改动范围和风险

### 3. Overworld Structured Editing

第一阶段只完成了 overworld 浏览与预览，尚未进入结构化 authoring 闭环。

待完成项：

- 在共享 Rust 层补齐 overworld 结构化编辑命令与服务接口
- 在 `bevy_map_editor` 中补齐 overworld proposal review / apply / save 流程
- 保持与 map 编辑一致的校验、规范化、原子写盘约束

完成定义：

- 用户可对 overworld 完成一次结构化的“提案 -> 应用 -> 保存”，且正式写盘仍经过共享 Rust 内核

### 4. Batch Template Generation

目前主路径仍以单次交互式 authoring 为主，还缺少批处理模板生成能力。

待完成项：

- 基于共享 Rust 编辑内核补齐批处理模板生成入口
- 明确批处理输入、输出与覆盖策略
- 让 CLI fallback 或编辑器侧批量流程都复用同一套结构化能力

完成定义：

- 能对一组地图或模板需求执行可重复的批量生成，而不是依赖逐张对话操作

### 5. Finer Authoring Widgets

当前主闭环已可用，但常见地图编辑操作仍主要依赖 AI proposal 或基础浏览能力，缺少更细粒度的 authoring widgets。

待完成项：

- 为高频操作补齐更细粒度的编辑控件
- 这些控件仍只调用共享 Rust 结构化命令，不在 UI 层直接改 JSON
- 让常用修改不必完全依赖自由文本 prompt

完成定义：

- 常见 authoring 操作具备更直接的 UI 入口，同时不破坏共享 Rust 内核的唯一权威地位

## Suggested Order

建议按以下顺序继续推进：

1. 清理 `tools/tauri_editor` 的残留旧地图入口表述
2. 强化 `bevy_map_editor` 的 proposal review / diff 可视化
3. 扩展到 overworld 结构化编辑闭环
4. 在共享 Rust 能力稳定后补齐批处理模板生成
5. 最后补更细粒度的 authoring widgets
