# Repo-Local AI Editor Workflow Migration

## Summary

将 Bevy editor 的 AI 聊天入口整体迁出 editor 本体，改为仓库内的 repo-local agent workflow。

迁移后的职责边界：

- `bevy_item_editor` / `bevy_recipe_editor` / `bevy_map_editor` 不再内嵌 AI 聊天窗口、provider 设置、proposal 对话状态
- AI Agent 直接在仓库中读写内容文件
- 共享 Rust 层只提供内容加载、校验、格式化、摘要与 editor handoff
- Bevy editor 只保留可视化、手工精修、reload/save/validate、预览与空间复核

本次迁移不兼容旧 `ai_chat`，旧聊天窗口与旧 AI provider 工作流全部删除。

## Target Architecture

- `game_editor` 不再包含 `ai_chat`
- `item` / `recipe` / `map` editor 不再持有 `AiChatState` / `AiChatWorkerState`
- AI 改 `item` / `recipe` / `character` / `map` 的主路径改为：
  - 仓库内 workflow 文档
  - 统一 Rust CLI 校验/摘要工具
  - 必要时通过 editor handoff 打开对应 editor 复核

## Phase 1: Hard Removal

Status: completed

### 1. Delete Shared Chat Infrastructure

- 从 `rust/crates/game_editor/src/lib.rs` 删除 `pub mod ai_chat;`
- 删除 `rust/crates/game_editor/src/ai_chat.rs`
- 清理所有 `game_editor::ai_chat::*` 引用

### 2. Remove Item Editor AI Chat Integration

- 删除 `bevy_item_editor` 的：
  - AI chat panel
  - AI settings window
  - AI worker polling
  - AI proposal apply flow
- 清理以下文件中的旧接入：
  - `rust/apps/bevy_item_editor/src/app.rs`
  - `rust/apps/bevy_item_editor/src/state.rs`
  - `rust/apps/bevy_item_editor/src/ui.rs`
  - `rust/apps/bevy_item_editor/src/ui/panels.rs`
  - `rust/apps/bevy_item_editor/src/commands.rs`
  - `rust/apps/bevy_item_editor/src/main.rs`
- 删除 `rust/apps/bevy_item_editor/src/ai.rs`

### 3. Remove Recipe Editor AI Chat Integration

- 删除 `bevy_recipe_editor` 的：
  - AI chat panel
  - AI settings window
  - AI worker polling
  - AI proposal apply flow
- 清理以下文件中的旧接入：
  - `rust/apps/bevy_recipe_editor/src/app.rs`
  - `rust/apps/bevy_recipe_editor/src/state.rs`
  - `rust/apps/bevy_recipe_editor/src/ui.rs`
  - `rust/apps/bevy_recipe_editor/src/ui/panels.rs`
  - `rust/apps/bevy_recipe_editor/src/commands.rs`
  - `rust/apps/bevy_recipe_editor/src/main.rs`
- 删除 `rust/apps/bevy_recipe_editor/src/ai.rs`

### 4. Remove Map Editor AI Chat Integration

- 删除 `bevy_map_editor` 的：
  - AI chat panel
  - AI settings window
  - AI worker polling
  - editor 内生成 proposal 的入口
  - editor 内 apply proposal 的入口
- 清理以下文件中的旧接入：
  - `rust/apps/bevy_map_editor/src/app.rs`
  - `rust/apps/bevy_map_editor/src/state.rs`
  - `rust/apps/bevy_map_editor/src/ui.rs`
  - `rust/apps/bevy_map_editor/src/commands.rs`
  - `rust/apps/bevy_map_editor/src/main.rs`
- 删除 `rust/apps/bevy_map_editor/src/map_ai/`

### 5. Clean Old Config And Docs

- 删除旧 AI provider 设置持久化相关文档和说明
- 更新 editor 架构文档，明确 AI 主路径迁出 editor

## Phase 2: Repo-Local Agent Workflow

Status: completed for initial docs skeleton

新增仓库文档目录：

- `docs/agent-workflows/`

第一批 workflow：

- `edit-item.md`
- `edit-recipe.md`
- `edit-character.md`
- `edit-map.md`
- `review-map-visual.md`

每个 workflow 固定描述：

- 目标文件位置
- 必读依赖数据
- 常见约束
- 修改后必须执行的命令
- 输出摘要格式
- 是否要求进入 editor 复核

已落地：

- `docs/agent-workflows/README.md`
- `docs/agent-workflows/edit-item.md`
- `docs/agent-workflows/edit-recipe.md`
- `docs/agent-workflows/edit-character.md`
- `docs/agent-workflows/edit-map.md`
- `docs/agent-workflows/review-map-visual.md`

## Phase 3: Shared Rust CLI For Agents

Status: completed

新增轻量 CLI app，例如：

- `rust/apps/content_tools`

已落地第一版：

- `content_tools locate item <id>`
- `content_tools locate recipe <id>`
- `content_tools locate character <id>`
- `content_tools locate map <id>`
- `content_tools validate item <id>`
- `content_tools validate recipe <id>`
- `content_tools validate character <id>`
- `content_tools validate map <id>`
- `content_tools validate changed`
- `content_tools summarize item <id>`
- `content_tools summarize recipe <id>`
- `content_tools summarize character <id>`
- `content_tools summarize map <id>`
- `content_tools references item <id>`
- `content_tools references map <id>`
- `content_tools format item <id>`
- `content_tools format recipe <id>`
- `content_tools format character <id>`
- `content_tools format map <id>`
- `content_tools format changed`
- `content_tools diff-summary --path <file>`

尚未落地：

- 暂无

首批命令：

### Locate / Summarize

- `content_tools locate item <id>`
- `content_tools locate recipe <id>`
- `content_tools locate character <id>`
- `content_tools locate map <id>`
- `content_tools summarize item <id>`
- `content_tools summarize recipe <id>`
- `content_tools summarize map <id>`
- `content_tools summarize character <id>`

### Validate

- `content_tools validate item <id>`
- `content_tools validate recipe <id>`
- `content_tools validate character <id>`
- `content_tools validate map <id>`
- `content_tools validate changed`

### Format

- `content_tools format item <id>`
- `content_tools format recipe <id>`
- `content_tools format character <id>`
- `content_tools format map <id>`
- `content_tools format changed`

### Diff / References

- `content_tools diff-summary --path <file>`
- `content_tools references item <id>`
- `content_tools references map <id>`

## Phase 4: Core Workflows

### Item Workflow

- Agent 定位 item 文件
- 读取相关 schema / catalog / 引用
- 修改内容
- 跑 item validate
- 如涉及 recipe / loot / vendor，补 references 检查
- 输出 diff 摘要

### Character Workflow

- Agent 定位角色与相关 appearance / dialogue / schedule 数据
- 修改角色内容
- 跑 character validate
- 如涉及联动内容，补关联检查
- 输出 diff 摘要

### Map Workflow

- Agent 定位 map 文件
- 先读地图摘要和当前校验状态
- 修改地图 JSON
- 跑 map validate
- 输出操作摘要和潜在风险
- 默认要求再用 map editor 做空间复核

## Phase 5: Keep Editors Review-Focused

### Item / Recipe Editors Keep

- 列表
- 详情
- 预览
- save / reload / validate
- handoff 打开

### Item / Recipe Editors Remove

- AI chat 面板
- AI settings
- AI proposal apply
- AI worker polling

### Map Editor Keep

- 地图浏览
- save / reload / validate
- scene rebuild
- 可视化检查

### Map Editor Remove

- AI chat 面板
- provider settings
- editor 内生成 AI proposal

## Phase 6: Thin Bridge Between Agent And Editor

Status: completed

新增薄桥脚本，例如：

- `tools/agent/open-editor.ps1 --item <id>`
- `tools/agent/open-editor.ps1 --recipe <id>`
- `tools/agent/open-editor.ps1 --character <id>`
- `tools/agent/open-editor.ps1 --map <id>`

已落地第一版：

- `tools/agent/open-editor.ps1`
- `run_bevy_item_editor.bat --select-item <id>`
- `run_bevy_recipe_editor.bat --select-recipe <id>`
- `run_bevy_map_editor.bat --select-map <id>`
- `run_bevy_character_editor.bat --select-character <id>`

当前行为：

- `item` / `recipe` / `character` / `map` 优先复用最近活跃实例，并通过 handoff 文件下发选中请求
- 若没有活跃实例，则直接启动对应 editor，并把目标 id 作为启动参数传入
- `item` / `recipe` / `character` / `map` 已支持启动时选中目标与外部选中请求
- `open-editor.ps1` 会对最近活跃实例尝试前置窗口；若前置失败，仍保留 selection handoff

继续复用 `game_editor::editor_handoff`，但语义统一为复核指定目标，而不是聊天流程的一部分。

## Phase 7: Docs And Rules

更新：

- 仓库 `AGENTS.md`
- editor 架构文档
- editor 使用文档
- `docs/agent-workflows/README.md`

固定规则：

- 不再给 Bevy editor 新增 AI 聊天窗口
- AI 改内容默认走 repo-local workflow
- editor 主要用于可视化复核和精修，不再作为 AI 对话入口

## Suggested Execution Order

1. 删除旧 `ai_chat` 体系和三个 editor 的接入
   - done
2. 新增 `content_tools` 最小 CLI
   - done
   - `locate` / `validate` / `summarize` / `references` / `validate changed` / `format` / `diff-summary` 已完成
3. 补 `item / character / map` workflow 文档
   - done
4. 补 `open-editor` handoff 薄桥
   - done
   - `item / recipe / character / map` 已支持启动选中与外部 handoff 选中
5. 再按真实使用频率补充地图 visual review 辅助
   - done
   - 新增 `tools/agent/review-map-visual.ps1 -Map <id>`
   - 统一串联 `content_tools locate/summarize/references/validate` 与 `open-editor.ps1 -Map <id>`
   - `docs/agent-workflows/review-map-visual.md` 已更新为可直接执行的复核入口

## Minimum Acceptance

- `game_editor` 不再导出 `ai_chat`
- `bevy_item_editor` / `bevy_recipe_editor` / `bevy_map_editor` 不再出现聊天窗口、AI 设置、AI worker
- Agent 可以只靠仓库 workflow + CLI 修改 `item` / `character` / `map`
- 修改后有统一校验命令
- 地图修改后有统一 editor 复核入口
- 文档不再把 editor 内聊天视为主路径
