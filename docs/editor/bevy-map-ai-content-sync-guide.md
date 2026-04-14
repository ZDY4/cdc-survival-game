# Bevy Map AI 内容同步操作说明

本文档面向维护地图内容、`world tiles`、可放置物件目录和地图 AI 输入上下文的开发者，只描述“新增/修改内容后如何同步给 AI”，不覆盖地图编辑器的一般使用说明。

相关但不同职责的文档：

- [bevy-ai-map-editing-plan.md](/D:/Projects/cdc-survival-game/docs/editor/bevy-ai-map-editing-plan.md)：记录地图 AI 编辑链路后续还要补哪些能力
- 本文档：记录当内容发生变更时，维护者应该执行哪些同步和检查动作

## 当前仓库现状

先明确当前真实行为，避免按“理想方案”误判：

- `bevy_map_editor` 的地图 AI prompt 构建入口在 [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs)。
- 当前 prompt 不再只传 `selected_map` 和 `available_map_ids`，还会在每次发起 AI proposal 前动态构建 `generation_context`。
- `generation_context` 当前会枚举：
  - `available_object_kinds`
  - `item_ids`
  - `character_ids`
  - `prototype_ids`
  - `wall_set_ids`
  - `surface_set_ids`
  - `container_visual_ids`
  - 面向各 `MapObjectKind` 的最小字段 guidance 和 placement rules
- 地图校验入口在 [map_edit.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map_edit.rs)。
- `MapEditorService::validation_catalog()` 当前会加载：
  - `item_ids`
  - `character_ids`
  - `prototype_ids`
  - `wall_set_ids`
  - `surface_set_ids`
- `world tiles` 的真实 ID 来源在 [world_tiles.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/world_tiles.rs)。
- 容器视觉 ID 的当前来源仍不在 `game_data`，而是在 [container_visuals.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/container_visuals.rs) 的 `ContainerVisualRegistry::builtin()`。

一句话总结当前状态：

- 纯“内容数据”层面的新增或修改，已经可以在下一次 AI proposal 构建时自动进入 prompt catalog。
- 同一批 `world tile / item / character` ID 也会进入地图 validator catalog。
- 但“结构/schema 变更”仍然不能只靠改数据，必须同步更新 Rust schema、validator 和 AI guidance。

## 同步原则

内容变更分两类处理，操作方式不同。

### 1. 内容数据变更

这类变更包括：

- 新增 `world tile` prototype
- 新增 `wall_set_id / surface_set_id`
- 新增 `item_id`
- 新增 `character_id`
- 新增 `container visual_id`
- 新增参考地图或示例地图

目标是让：

- loader / registry 能读到新内容
- validator 能校验应校验的内容
- 地图 AI 在下一次 proposal 构建时拿到新的 catalog

### 2. 结构 / schema 变更

这类变更包括：

- 新增 `MapObjectKind`
- 给 `MapObjectProps` 增加新 payload
- 新增 placement 字段
- 新增新的交互语义或对象约束关系

这类变更不能只改数据，必须同步更新代码链路。至少要检查：

- Rust schema
- validator
- AI prompt / payload 构建
- 需要时更新代表性示例地图

## 新增或修改内容后必须执行的操作

下面按内容类型列出操作清单。

### A. 新增或修改 `world tiles / wall set / surface set / prototype`

适用范围：

- `data/world_tiles/*.json`

必须执行：

- 更新对应的 `data/world_tiles/*.json`
- 确认 [world_tiles.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/world_tiles.rs) 的 `load_world_tile_library()` 能成功读取新内容
- 确认新增 ID 落在以下集合中：
  - `prototype_ids`
  - `wall_set_ids`
  - `surface_set_ids`
- 确认 [map_edit.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map_edit.rs) 的 `validation_catalog()` 能把这些 ID 加入 validator catalog
- 如果新增内容会被地图直接引用：
  - 检查对象 `props.visual.prototype_id`
  - 检查建筑 `props.building.tile_set.wall_set_id`
  - 检查建筑 `props.building.tile_set.floor_surface_set_id`
  - 检查地块 `cell.visual.surface_set_id`

当前实现下还要知道：

- `bevy_map_editor` 的 `generation_context` 会在每次生成 proposal 前重新加载 `world tiles`。
- 只要 JSON 已落盘且 loader 成功，下一次 AI proposal 就应该能看到新 ID。
- 代表性地图样例仍然有价值，但它现在是增强项，不再是让 AI“看见”新 tile 的唯一手段。

### B. 新增或修改 pickup / item

适用范围：

- `data/items`

必须执行：

- 更新 item 数据
- 确认 item loader 能读到新增 `item_id`
- 确认 [map_edit.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map_edit.rs) 的 `validation_catalog()` 能把新增 `item_id` 加入 `item_ids`
- 确认 [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs) 的 `generation_context.available_content.item_ids` 会在下一次 proposal 时包含该 ID
- 若地图对象会使用该物品：
  - 检查 `props.pickup.item_id`
  - 检查 `props.container.initial_inventory[*].item_id`

当前实现下：

- 新增 `item_id` 不需要手工改 prompt 文案才能被 AI catalog 看见。
- 如果这是高频或强语义物品，仍然建议补一张代表性地图样例，帮助模型更稳定地理解用途。

### C. 新增或修改 AI spawn character

适用范围：

- `data/characters`

必须执行：

- 更新角色数据
- 确认 character loader 能读到新增 `character_id`
- 确认 [map_edit.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map_edit.rs) 的 `validation_catalog()` 能把新增 `character_id` 加入 `character_ids`
- 确认 [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs) 的 `generation_context.available_content.character_ids` 会在下一次 proposal 时包含该 ID
- 若地图对象会使用该角色：
  - 检查 `props.ai_spawn.character_id`

当前实现下：

- 新增 `character_id` 不需要手工改 prompt 文案才能被 catalog 枚举。
- 若这是一个模型容易误用的角色，建议同时补少量代表性地图样例或更明确的用户指令。

### D. 新增或修改 container visual

适用范围：

- 当前实现位于 [container_visuals.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/container_visuals.rs)

必须执行：

- 更新 `ContainerVisualRegistry::builtin()`
- 确认新增 `visual_id` 能通过 `ContainerVisualRegistry::ids()` 被枚举到
- 确认 [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs) 的 `generation_context.available_content.container_visual_ids` 会在下一次 proposal 时包含该 ID
- 若地图中已有容器使用该视觉：
  - 检查 `props.container.visual_id`

当前实现下：

- 容器视觉 ID 虽然不在 `game_data`，但已经会自动进入地图 AI prompt catalog。
- 因为 validator 目前只校验 `visual_id` 非空，不校验 registry 成员关系，所以运行时/预览抽查仍然必要。

### E. 新增或修改参考地图 / 样例地图

适用范围：

- `data/maps/*.json`

必须执行：

- 保存并通过现有地图校验
- 确认该地图能够在 `bevy_map_editor` 中正常加载和预览

当前实现下，这一步的定位是：

- 用来帮助模型理解“这些内容通常怎么组合和摆放”
- 不是用来补齐内容目录缺失

因此如果新增内容具有较强结构约束，例如复杂建筑、特殊容器组合或 AI spawn 编排，仍然建议补一张结构清晰的代表性地图。

## 哪些会自动同步，哪些不会

### 当前会自动同步的部分

- 新增 `item_id`
  - 只要 item loader 能读取，validator catalog 和 AI `generation_context` 都会在下一次构建时看到
- 新增 `character_id`
  - 只要 character loader 能读取，validator catalog 和 AI `generation_context` 都会在下一次构建时看到
- 新增 `prototype_id / wall_set_id / surface_set_id`
  - 只要 `load_world_tile_library()` 能读取，validator catalog 和 AI `generation_context` 都会在下一次构建时看到
- 新增 `container visual_id`
  - 只要 `ContainerVisualRegistry::builtin()` 更新，AI `generation_context` 就会在下一次构建时看到

### 当前不会自动同步的部分

- 新的 `MapObjectKind`
- 新的 `MapObjectProps` payload
- 新增字段对应的组合约束
- 新的 placement 语义或对象使用规则
- 需要额外程序逻辑支持的新 catalog 字段

### 当前绝对不能只改数据的情况

遇到以下情况，不能只改内容数据：

- 新增 `MapObjectKind`
- 给 `MapObjectProps` 增加新 payload
- 新增 placement 字段
- 新增 object kind 与 `props.*` 的约束关系

这类变更必须同步更新：

- [types.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map/types.rs) 的 schema
- [validation.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map/validation.rs) 的约束
- [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs) 的 AI guidance / payload
- 必要时补代表性示例地图

## 代码同步点索引

内容同步失败时，优先检查以下入口。

### AI prompt / payload

- [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs)
  - `build_map_ai_generation_context()`
  - `load_available_content()`
  - `build_map_prompt_payload()`

### 地图 validator catalog

- [map_edit.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map_edit.rs)
  - `validation_catalog()`

### world tile ID 来源

- [world_tiles.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/world_tiles.rs)
  - `load_world_tile_library()`
  - `prototype_ids()`
  - `wall_set_ids()`
  - `surface_set_ids()`

### 容器视觉 ID 来源

- [container_visuals.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/container_visuals.rs)
  - `ContainerVisualRegistry::builtin()`
  - `ContainerVisualRegistry::ids()`

### Map schema / validator 约束

- [types.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map/types.rs)
- [validation.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map/validation.rs)

## 推荐验证步骤

每次新增或修改地图相关内容后，至少执行下面这套检查。

1. 检查新增数据是否被 loader / registry 读取

- `world tiles`：检查 `load_world_tile_library()` 是否能读到新 ID
- `item`：检查 item loader 是否能读到新 `item_id`
- `character`：检查 character loader 是否能读到新 `character_id`
- `container visual`：检查 `ContainerVisualRegistry::ids()` 是否能看到新 `visual_id`

2. 检查 validator catalog 是否包含新增 ID

- `item_id`
- `character_id`
- `prototype_id`
- `wall_set_id`
- `surface_set_id`

3. 在 `bevy_map_editor` 中触发一次新的 AI proposal

- 当前 `generation_context` 是按次构建的
- 因此只要数据已落盘，下一次 proposal 就应重新看到新目录内容

4. 检查 proposal 行为

- 确认 proposal 开始使用新增内容
- 或至少确认 proposal 不再把新增 ID 当成未知值乱写

5. 检查 preview / apply / validate

- 对 tile / building 相关内容，检查 preview 渲染是否正常
- 对 pickup / ai_spawn / container，检查 apply 后是否通过现有 validator

## 常见失败模式

### 1. 新增了 tile，但 AI 还是不会用

优先排查：

- [world_tiles.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/world_tiles.rs) 是否已读到该 ID
- [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs) 的 `generation_context.available_content` 是否已包含该 ID
- 当前用户指令是否明确要求使用该内容
- 是否缺少代表性地图样例，导致模型知道 ID 但不知道应该怎么摆

### 2. proposal 里引用了新 ID，但 apply / validate 报 unknown

优先排查：

- [map_edit.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map_edit.rs) 的 `validation_catalog()`
- 对应 ID 是否真的从正确数据源读取成功
- 是否修改了磁盘数据但 proposal 使用前没有重新触发一次新生成

### 3. 新增了 container visual，但模型仍然只生成旧 visual

优先排查：

- [container_visuals.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/container_visuals.rs) 是否已加新 `visual_id`
- `ContainerVisualRegistry::ids()` 是否已经包含它
- [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs) 的 `generation_context.available_content.container_visual_ids` 是否已包含它
- 当前地图样例是否提供了该 visual 的合理使用参考

### 4. 新 schema 已加，但 AI 仍按旧结构输出

优先排查：

- [types.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map/types.rs) 是否已更新
- [validation.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/map/validation.rs) 是否已更新
- [map_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_map_editor/src/map_ai.rs) 的 object kind guidance / placement rules 是否已更新
- 当前示例地图是否仍全部是旧结构

## 维护建议

维护地图 AI 对新内容的同步时，优先遵守以下顺序：

1. 先保证 loader / registry 正常
2. 再保证 validator catalog 和 AI catalog 都能枚举到新 ID
3. 最后再视需要补代表性示例地图或细化 prompt guidance

不要把“改 prompt 文案”当成普通数据新增的主同步手段。

- 对“新增数据”，默认应先走自动 catalog 同步
- 对“新增 schema”，应把 AI context builder 当成 schema 维护的一部分一起更新
