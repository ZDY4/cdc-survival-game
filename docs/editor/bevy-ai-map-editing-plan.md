# Bevy AI Map Editing Plan

## Goal

地图编辑入口统一收口到 `rust/apps/bevy_map_editor`。

第一阶段的地图工具职责固定为：

- 浏览 `maps` 与 `overworld`
- 渲染当前选中文档的 3D 预览
- 在编辑器内部进行 AI 对话
- 通过共享 Rust 地图编辑内核生成结构化编辑提案
- 由用户确认后应用提案并保存到现有 JSON 文件

旧 `tools/tauri_editor` 不再承担任何 `maps` / `overworld` 编辑职责。

## Architecture Decision

长期结构固定为四层：

1. `game_data` 共享地图编辑内核
   - 权威 schema
   - 读图、校验、规范化、结构化编辑命令、原子写盘
2. `bevy_map_editor` 应用服务层
   - 文档加载
   - 选中状态
   - 预览场景重建
   - diagnostics 聚合
   - 提案应用与保存编排
3. `bevy_map_editor` 内建 AI 会话层
   - provider 配置
   - prompt / session state
   - tool orchestration
   - proposal summary / diagnostics / apply / save
4. 可选 CLI fallback
   - `game_data` 下的 `map_tool`
   - 仅用于 agent、CI、批处理与调试

关键原则：

- `game_data::MapEditorService` 是唯一权威编辑实现
- `bevy_map_editor` 不能自己实现第二套地图 JSON 修改规则
- AI 主路径是结构化命令，不是直接输出整份 JSON 覆盖文件
- 正式写盘必须经过 `proposal -> review -> apply -> save`

## Tauri Retirement Scope

以下能力从 `tools/tauri_editor` 完全退场：

- 地图编辑窗口
- overworld 编辑窗口
- 地图窗口通信 payload / event
- Tauri 地图 backend command
- 地图模块的前端本地 normalize / repair / save 逻辑

退场后的 `tools/tauri_editor` 只保留：

- items
- dialogues
- quests
- settings
- 与上述模块共用的编辑器壳层能力

## Shared Rust Core

`rust/crates/game_data/src/map_edit.rs` 继续作为权威实现，第一阶段对外接口基准为：

- `MapEditorService`
- `MapEditCommand`
- `MapEditResult`
- `MapEditDiagnostic`
- `MapEditOperationSummary`
- `MapEditError`

共享内核职责：

- 从 `data/maps/*.json` 读取地图
- 基于结构化命令修改 `MapDefinition`
- 执行校验与规范化
- 生成结构化 diagnostics
- 原子写盘

第一阶段最小命令集：

- `CreateMap`
- `ValidateMap`
- `FormatMap`
- `UpsertEntryPoint`
- `RemoveEntryPoint`
- `UpsertObject`
- `RemoveObject`
- `AddLevel`
- `RemoveLevel`
- `PaintCells`
- `ClearCells`

## Bevy Editor Responsibilities

`rust/apps/bevy_map_editor` 负责产品层行为，不负责底层地图语义。

应用层职责拆分如下。

### Library / Selection

- 读取 map library 与 overworld library
- 支持 reload
- 支持当前文档切换
- 保持 selected map / selected overworld 状态

### Scene Preview

- 根据当前选中文档重建预览场景
- 支持地图层级切换
- 支持相机 orbit / top-down 浏览
- 对 dirty / reload / apply 结果做统一刷新

### Diagnostics

- 展示当前文档 diagnostics
- 展示 AI proposal 预检查 diagnostics
- 展示 save 成功或失败状态

### Proposal Orchestration

- 持有 AI 返回的结构化 proposal
- 将 proposal 转成 `PreparedProposal`
- 在内存态预览 apply 结果
- 允许用户显式点击 apply
- apply 后标记文档 dirty
- save 时调用共享 Rust 内核写盘

## Bevy AI Session Layer

AI 会话只存在于 `bevy_map_editor` 内部，不再依赖 Tauri 前端。

第一阶段 UI 组成：

- provider 配置区
- 会话消息区
- prompt 输入区
- 当前 map 上下文摘要
- 最近一次 proposal 摘要
- diagnostics 列表
- `Apply` 按钮
- `Save` 按钮

第一阶段交互流：

1. 用户选择当前 map
2. 用户输入 prompt
3. 编辑器拼装上下文并调用 provider
4. AI 返回结构化 proposal
5. 编辑器用共享 Rust 内核预执行 proposal
6. 编辑器展示 summary / warnings / diagnostics / diff-like details
7. 用户点击 `Apply`
8. 编辑器把结果写回内存态文档
9. 用户点击 `Save`
10. 共享 Rust 内核执行校验、规范化、原子写盘

失败路径要求：

- provider 失败时显示明确错误
- schema 不合法时显示解析错误
- proposal 语义非法时显示 `MapEditError`
- save 失败时不留下半写文件

## Proposal Model

AI 不直接产出整份地图文件作为主写入路径。

第一阶段 proposal 结构固定包含：

- `summary`
- `warnings`
- `target`
- `operations`

`target` 支持：

- `current_map`
- `new_map`

`operations` 第一阶段支持：

- `add_level`
- `remove_level`
- `upsert_entry_point`
- `remove_entry_point`
- `upsert_object`
- `remove_object`
- `paint_cells`
- `clear_cells`

正式写盘前必须经过共享内核对每个 operation 的验证与应用。

## Overworld Scope

第一阶段对 `overworld` 的范围刻意收窄：

- 支持浏览与预览
- 支持作为 AI 上下文引用来源
- 不要求第一阶段完成完整 AI authoring 闭环

如果后续启用 overworld 编辑，也必须走同一套共享 Rust 结构化命令模型，不能在 Bevy UI 层直接改 JSON。

## CLI Fallback

`rust/crates/game_data/src/bin/map_tool.rs` 保留，但角色调整为 fallback：

- 调试共享地图编辑内核
- agent 非交互调用
- CI 批量校验或格式化

CLI 不是主产品入口，不承载主要用户交互。

## Interfaces

当前需要保留或新增的接口如下。

### Shared Rust

- `game_data::MapEditorService`
- `game_data::MapEditCommand`
- `game_data::MapEditResult`
- `game_data::MapEditDiagnostic`
- `game_data::MapEditOperationSummary`
- `game_data::MapEditError`

### Bevy Editor Internal

- `EditorState`
- AI settings resource
- AI worker / provider status resource
- proposal state resource
- apply / save orchestration helpers

### Removed Tauri Interfaces

- `load_map_workspace`
- `validate_map_document`
- `create_map_draft`
- `save_map_documents`
- `delete_map_document`
- `load_overworld_workspace`
- `validate_overworld_document`
- `save_overworld_documents`
- `delete_overworld_document`
- `MapEditorOpenDocumentPayload`
- `MapEditorStateChangedPayload`
- `MapEditorSaveCompletePayload`
- `MapEditorSessionEndedPayload`
- `MAP_EDITOR_*` window events

## Delivery Checklist

### Phase 1. Retire Old Tauri Map Editor

- [ ] 删除 Tauri 地图窗口与相关前端模块
- [ ] 删除 Tauri 地图 backend command
- [ ] 删除地图窗口通信 payload / event
- [ ] 清理菜单、README、测试中的旧地图入口表述
- [ ] 保证 `tools/tauri_editor` 在无地图模块时仍可构建

完成定义：

- `tools/tauri_editor` 中不再存在地图编辑入口或地图编辑命令

### Phase 2. Stabilize Shared Map Editing Core

- [ ] 保留 `MapEditorService` 作为唯一权威编辑实现
- [ ] 确认第一阶段命令集完整可用
- [ ] 保证 create / validate / format / mutate / save 闭环稳定

完成定义：

- `cargo test -p game_data` 通过

### Phase 3. Bevy Editor Authoring Loop

- [ ] 地图库加载
- [ ] 当前 map 选择
- [ ] 3D 预览重建
- [ ] diagnostics 面板
- [ ] reload
- [ ] save

完成定义：

- `bevy_map_editor` 能完成查看、修改后保存的最小闭环

### Phase 4. Bevy AI Proposal Loop

- [ ] provider 配置
- [ ] prompt 输入
- [ ] AI proposal 调用
- [ ] proposal summary / warnings 展示
- [ ] pre-apply diagnostics
- [ ] apply
- [ ] save

完成定义：

- 用户可在编辑器内完成一次 “提案 -> 应用 -> 保存”

### Phase 5. Follow-up Expansion

- [ ] 多轮会话上下文
- [ ] 更强的 diff 可视化
- [ ] overworld 结构化编辑
- [ ] 批处理生成模板
- [ ] 更精细的 authoring widgets

完成定义：

- 不属于第一阶段必须项

## Verification

第一阶段验收基线：

- `cargo test -p game_data`
- `cargo check -p bevy_map_editor`
- `npm run build` in `tools/tauri_editor`
- `cargo run -p bevy_map_editor` 可启动且无启动期 panic

最小 smoke 关注点：

- 能读取 `data/maps`
- 能读取 `data/overworld`
- 选中 map 后预览可刷新
- AI 能生成一次结构化 proposal
- 合法 proposal 可 apply
- save 失败时能展示结构化错误且不写坏文件

## Non-goals

第一阶段明确不做：

- 再做一套 Tauri 地图编辑前端
- 直接让 AI 覆盖整份地图 JSON
- 静默自动写盘
- 撤销 / 重做系统
- 复杂笔刷、框选、图层 authoring
- 地图数据库或远程内容服务
- Godot 侧地图编辑能力扩展

## Default Decisions

- 地图 JSON 继续作为最终落盘格式
- `bevy_map_editor` 是唯一地图产品入口
- `game_data` 是唯一权威地图编辑实现
- AI 主入口是 Bevy 内建会话面板
- CLI 只作为 fallback
- 用户必须显式确认 apply / save
