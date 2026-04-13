# Instanced Tile-Based 3D World 完整框架线

## 背景

当前项目已经完成了这条路线上的前置基础：

- 建筑墙已经从旧 `box` 语义迁到 `building_wall_tiles`
- `bevy_debug_viewer` 和 `bevy_map_editor` 已统一复用 shared `game_bevy::world_render`
- tile prototype 已支持从 glTF scene flatten 成多 primitive runtime batch
- `Standard` tile 已接入 shared custom instancing backend
- 建筑墙也已接入 shared batch / instanced render，同时 viewer 保留单格 pick / outline / occlusion 粒度

现在的下一阶段目标，不再是“只修建筑墙”，而是把整套世界静态渲染能力收口成一个可长期演进的 **tile-based 3D world framework**。

本文定义这条“完整框架线”的剩余 5 个阶段。

## 总目标

形成一套统一框架，使以下内容都通过共享 tile/prototype/placement 体系表达和渲染：

- 建筑墙
- 建筑地板
- 地表与高低起伏
- 环境物件
- 可交互场景物件的静态态
- overworld 地块

并满足以下约束：

- `Rust / Bevy` 是唯一长期实现基准
- `bevy_debug_viewer` 和 `bevy_map_editor` 不保留独立世界内容渲染链
- 正式静态世界主渲染尽量不依赖 `StaticWorldBoxSpec`
- runtime 允许一部分实例从 instanced 静态态“升格”为独立动态实体
- 资产来源长期统一为 `rust/assets + game_data prototype definitions`

## 当前完成位置

当前已经完成的是“建筑墙专用链 + shared batch / instancing 基础打通”。

从完整框架视角看，当前相当于：

- 已完成建筑墙的专用 shared 渲染收口
- 已完成 instanced tile runtime 的第一版批次骨架
- 尚未完成地表 / floor / prop / 动态升格 / 资产流水线 / 最终收口

因此，完整框架线还剩 5 个阶段。

---

## 阶段 1：静态世界内容全面并入 Tile World

### 目标

把当前仍然散落在 `box` / ground patch / 独立实体路径中的静态世界内容，统一并入 shared tile world。

### 范围

- 建筑地板从 `BuildingFloor box` 改成 surface tile placement
- 地表与高低起伏改成 surface tile placement
- 环境静态物件统一走 prop prototype placement
- overworld 地块尽可能转到 surface / prototype placement

### 这一步完成后应满足

- 静态世界的主要可见内容都来自 `TileWorldSceneSpec`
- `resolve_tile_world_scene()` 成为大部分静态世界几何的主入口
- `spawn_world_render_scene()` 中的通用 `spawn_box()` 只剩少量过渡/调试职责

### 主要实施点

- 在 `game_data` 明确 surface set / elevation / slope 的权威字段
- 在 `game_bevy::tile_world` 新增地表解析规则
- 在 `game_bevy::world_render` 中为 surface / prop prototype 扩大 instanced batch 覆盖面
- map editor / viewer 不单独加私有地表渲染逻辑

### 验收标准

- 同一张地图中，建筑墙、建筑地板、地表、箱子/柜子等 prop 都来自 shared tile scene
- `scene.boxes` 不再承载正式静态主可见内容，只剩少量辅助语义
- `cargo check`
- `cargo test -p game_bevy -p bevy_debug_viewer`

### 阶段 1 实施拆解

阶段 1 不建议作为一个大改动一次性推进，而应拆成 4 个连续子阶段。拆分原则是：

- 先收口 tactical map 内部最确定的建筑地板
- 再把 map cell 的 surface / elevation / slope 并进来
- 然后把环境静态物件全部统一到 prototype placement
- 最后再处理 overworld，因为它仍残留最多旧 `StaticWorldMaterialRole` 语义

### 1.1 建筑地板 tile 化

#### 目标

把当前建筑内部 `BuildingFloor` 逐格 box 输出，改成 surface tile placement 输出；让“建筑地板”和“普通地表”开始共享同一套 surface 解析链。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_data\src\map.rs`](D:/Projects/cdc-survival-game/rust/crates/game_data/src/map.rs) 已有 `MapBuildingTileSetSpec.floor_surface_set_id`
- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\static_world.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/static_world.rs) 仍在输出 `StaticWorldMaterialRole::BuildingFloor`
- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\tile_world.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/tile_world.rs) 目前还没有“从 building floor 生成 surface placement”的共享 resolver

#### 改动范围

- `game_bevy::static_world`
- `game_bevy::tile_world`
- `game_data::map`
- `game_bevy::world_render`

#### 实现要点

- 在 shared scene 中新增“建筑地板 surface placement 输入”，不要再把它压回 `StaticWorldBoxSpec`
- 解析规则直接复用 `floor_surface_set_id + walkable_cells`
- 每个 floor cell 生成一个 surface placement，首版不做矩形合并
- floor 的语义继续绑定原建筑 map object，避免 viewer 的 pick / tooltip / occlusion 信息丢失
- 建筑地板的 world transform 应与当前 `floor_top` 定义保持一致，避免和墙底、门底出现接缝
- 如果 `floor_surface_set_id` 缺失，首版策略建议保持“该建筑不生成 floor placement”，不要偷偷回退成 `BuildingFloor box`

#### 验收标准

- `StaticWorldMaterialRole::BuildingFloor` 不再承载正式可见建筑地板
- 同一栋建筑的墙 tile 和 floor tile 都来自 shared tile scene
- viewer / map editor 中建筑地板与墙的相对高度保持一致

#### 风险与非目标

- 本子阶段不处理 slope floor，不引入室内坡道规则
- 本子阶段不碰 door behavior，只处理地板静态表现

### 1.2 地表 / elevation / slope tile 化

#### 目标

把 tactical map cell 的地表从 ground patch / 普通 box 语义转成 `surface_set_id + elevation_steps + slope` 驱动的 tile placement。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_data\src\map.rs`](D:/Projects/cdc-survival-game/rust/crates/game_data/src/map.rs) 已有 `MapCellVisualSpec { surface_set_id, elevation_steps, slope }`
- [`D:\Projects\cdc-survival-game\rust\crates\game_data\src\world_tiles.rs`](D:/Projects/cdc-survival-game/rust/crates/game_data/src/world_tiles.rs) 已有 `WorldSurfaceTileSetDefinition`
- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\tile_world.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/tile_world.rs) 目前还没有 tactical surface resolver

#### 改动范围

- `game_bevy::tile_world`
- `game_bevy::static_world`
- `game_bevy::world_render`
- 必要时补充 `game_data` 默认内容

#### 实现要点

- 新增 tactical surface resolver，输入至少包含：
  - `MapDefinition`
  - `current_level`
  - `grid_size`
  - `WorldTileLibrary`
- 解析流程按“top tile 优先，cliff/ramp 为附加 placement”设计，不要把 surface 限死成“每格只能一个 prototype”
- `TileSlopeKind::Flat` 走 `flat_top_prototype_id`
- `TileSlopeKind::{North, East, South, West}` 走对应 `ramp_top_prototype_ids`
- `elevation_steps` 的邻格差异用于决定是否补 cliff side / inner corner / outer corner placement
- 地表 placement 的语义应优先落到 cell 级别，而不是伪装成 map object
- tactical map 的 ground 可见层一旦 tile 化，就不再继续扩充 `StaticWorldGroundSpec` / ground patch 语义

#### 验收标准

- 带 `surface_set_id` 的普通地图 cell 会生成 surface tile placement
- ramp 和平地 prototype 能按 `TileSlopeKind` 正确分派
- 有高差的相邻 cell 会生成 cliff 侧面或角块 placement
- 地表主可见几何不再依赖 `StaticWorldGroundSpec`

#### 风险与非目标

- 本子阶段的 `elevation_steps` 只先服务视觉，不同步改写 pathfinding / movement
- 首版 cliff 逻辑可以先只覆盖最常见拓扑，不要求一次做完所有复杂边角

### 1.3 Prop placement 全量并入 Tile World

#### 目标

把环境静态物件统一成 `prototype_id` 驱动的 placement，收掉剩余“普通 box 表现物件”和 viewer 私有 visual override 语义。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_data\src\map.rs`](D:/Projects/cdc-survival-game/rust/crates/game_data/src/map.rs) 已有 `MapObjectVisualSpec`
- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\tile_world.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/tile_world.rs) 已有 `resolve_map_object_visual_placements()` 和 `resolve_snapshot_object_visual_placements()`
- 但 shared static world / viewer 仍保留部分普通 box / accent box / trigger box 视觉语义

#### 改动范围

- `game_bevy::tile_world`
- `game_bevy::static_world`
- `game_bevy::world_render`
- `bevy_debug_viewer`

#### 实现要点

- 明确 prop 分类：
  - 纯视觉静态物件：直接 tile placement
  - 带 pick / hover / outline 的物件：tile placement + pick proxy
  - 后续可交互会升格的物件：当前阶段先仍作为静态 placement 表达，但保留语义句柄
- 逐步减少 `PickupBase`、`InteractiveBase`、`AiSpawnBase` 这类“用 box 代替正式模型”的主可见职责
- viewer 若仍需要 debug accent，可保留 proxy / overlay，但不能再承担正式世界外观
- 门保持共享 prototype / behavior 方向，不回到 viewer 私有几何
- 对多格 footprint 的 prop，placement transform 继续以 footprint center 为基准；不要为迁就 instancing 改坏已有对象朝向与对齐规则

#### 验收标准

- 箱子、柜子、路障、公交残骸等已有 `prototype_id` 的环境物件都来自 tile placement
- viewer 中这些物件即使保留 hover / outline，也不再依赖普通 box 作为主视觉
- map editor 与 viewer 对同一个 prop 的 prototype、旋转、偏移一致

#### 风险与非目标

- 本子阶段不实现“实例升格”为动态实体，那属于阶段 3
- 仍允许极少数尚无 prototype 资产的物件临时保留 debug box，但必须标注为过渡项，不再扩散

### 1.4 Overworld 地表与地点标记并入 Tile World

#### 目标

把 overworld 的地表和地点标记从一组独立 `StaticWorldMaterialRole::*` 颜色盒子，迁到 surface/prototype placement 体系。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_data\src\overworld.rs`](D:/Projects/cdc-survival-game/rust/crates/game_data/src/overworld.rs) 已有 `OverworldCellVisualSpec { surface_set_id, elevation_steps, slope }`
- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\static_world.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/static_world.rs) 仍大量输出：
  - `OverworldGroundRoad/Plain/Forest/River/Lake/Mountain/Urban`
  - `OverworldLocation*`
  - `OverworldBlockedCell`
- [`D:\Projects\cdc-survival-game\rust\apps\bevy_debug_viewer\src\render\world\static_world.rs`](D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/render/world/static_world.rs) 还保留这些 role 的颜色映射

#### 改动范围

- `game_data::overworld`
- `game_data::world_tiles`
- `game_bevy::static_world`
- `game_bevy::tile_world`
- `bevy_debug_viewer`

#### 实现要点

- overworld ground 直接复用 surface set，不再单独维护 terrain kind 到颜色 box 的主渲染映射
- `OverworldTerrainKind` 保留 gameplay / 语义价值，但视觉分派以 `OverworldCellVisualSpec.surface_set_id` 为权威
- overworld 地点标记单独设计成 prototype placement，不再用程序化 marker box/billboard 作为长期主路径
- `OverworldBlockedCell` 优先降级为 debug / proxy 语义，而不是正式视觉层
- 如果某些地点标记短期还没有正式 prototype，可允许保留临时 marker prototype，但也要进入 tile prototype catalog，而不是继续塞 `StaticWorldMaterialRole`

#### 验收标准

- overworld 地表主可见层来自 surface placement
- overworld location marker 来自 prototype placement
- viewer 中旧 `OverworldGround*` / `OverworldLocation*` 色块语义不再承担正式外观

#### 风险与非目标

- 本子阶段不要求 overworld UI tooltip 或 travel prompt 重写，只改可视层主链
- 如果 location marker 仍需文字 label，可暂时保留 label 作为辅助 overlay，但不再承担主体体块

### 阶段 1 推荐施工顺序

建议按以下顺序执行，不要并行乱拆：

1. 先做 1.1 建筑地板 tile 化，因为它和现有建筑墙链最接近，回归面最小。
2. 再做 1.3 prop placement 收口，因为 `MapObjectVisualSpec` 和 shared prototype 流程已经存在，收益最高。
3. 然后做 1.2 地表 / elevation / slope tile 化，因为这一步会引入 surface resolver 和高差拓扑，改动面更大。
4. 最后做 1.4 overworld，因为它依赖前面 surface/prototype 主链稳定后再统一替换旧色块语义。

这样排的原因是：

- 建筑地板和 prop 都是当前 schema 已较明确的内容，适合作为 tile world 扩面第一批
- tactical surface 和 overworld surface 共享大量解析概念，但 overworld 旧残留更多，适合压轴清理
- 如果先碰 overworld，容易把阶段 1 拖成“同时重构两套世界模式”

### 阶段 1 完成判定

满足以下条件时，阶段 1 才算真正完成，而不是“加了几个 prototype 字段就算过”：

- tactical map 中建筑墙、建筑地板、普通地表、主要环境 prop 已全部可由 `resolve_tile_world_scene()` 统一产出 batch
- `bevy_debug_viewer` 和 `bevy_map_editor` 对上述内容都只消费 shared tile world，不再有私有主渲染链
- `StaticWorldSceneSpec.boxes` 剩余内容主要是 pick proxy、debug proxy、少量明确标注的过渡项
- `StaticWorldMaterialRole::BuildingFloor`、大部分 `OverworldGround*`、大部分 `OverworldLocation*` 不再承担正式主可见职责
- 阶段 2 可以在不改内容 schema 的前提下开始清理剩余 fallback 路径

---

## 阶段 2：清理剩余 Box / Fallback 主渲染路径

### 目标

把 shared / viewer / editor 中剩余“能回退成普通 box 渲染正式世界内容”的路径清理掉。

### 范围

- 清理 shared `StaticWorldBoxSpec` 中不再需要的正式主渲染语义
- 清理 viewer 对 shared box 的老兼容分支
- map editor 继续只依赖 shared world render，不新增私有回退能力

### 保留的 box 用途

本阶段结束后，`box` 只应承担以下职责：

- pick proxy
- outline proxy
- 临时调试可视化
- 少量尚未 tile 化的过渡辅助

### 这一步完成后应满足

- 正式世界几何不再依赖 `spawn_box()` 作为主路径
- “某个建筑/地表/物件因为 fallback 被渲染成普通长方体”不再是默认可发生情况

### 主要实施点

- 缩减 `StaticWorldMaterialRole` 中仅为老 box fallback 服务的分支
- viewer `collect_static_world_box_specs()` 只保留真正的 proxy / debug 内容
- 清理无调用方的旧 helper

### 验收标准

- viewer / editor 中建筑墙、地板、地表、环境物件都不会再退回普通 box 外观
- `cargo check`
- 手动 smoke：shared render 和 viewer/editor 显示一致

### 阶段 2 实施拆解

阶段 2 的核心不是“把 box 全删掉”，而是把 box 从“正式主渲染路径”彻底降级为 proxy / debug 辅助。这个阶段建议拆成 3 个子阶段，按 shared 收口、viewer/editor 适配、最后删旧 helper 的顺序做。

### 2.1 Shared `StaticWorldMaterialRole` 与 box 语义收口

#### 目标

先在 shared 层明确哪些 `StaticWorldMaterialRole` 仍然允许存在于正式世界内容，哪些只保留给 proxy/debug，避免 viewer/editor 还继续接受旧语义。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\static_world.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/static_world.rs) 仍保留大量面向旧 box 主渲染的 role
- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\world_render\spawn.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/world_render/spawn.rs) 仍有 `spawn_box()` 主路径
- `default_color_for_role()` 仍承担不少正式世界内容的颜色定义

#### 改动范围

- `game_bevy::static_world`
- `game_bevy::world_render`

#### 实现要点

- 给 `StaticWorldMaterialRole` 做一次分类：
  - 正式保留的 box role
  - 仅 proxy/debug 保留的 box role
  - 已迁入 tile world 后可以删除的旧 role
- 对已迁入 tile world 的建筑地板、overworld ground、overworld location marker，shared 层不再继续提供正式色块语义
- `StaticWorldSceneSpec.boxes` 的注释和约束要同步更新，明确它不再是正式主内容容器
- `default_color_for_role()` 保留给 debug/proxy 的内容应尽量最小，不再作为长期“世界默认美术”

#### 验收标准

- shared API 层面对“什么还能以 box 主渲染存在”有清晰边界
- 已 tile 化内容不再拥有对应的正式 box role

#### 风险与非目标

- 本子阶段先不碰 viewer hover/outline 逻辑，只改 shared 边界
- 不要求一次删尽所有 role，但必须把它们标成 proxy/debug 或待删除

### 2.2 Viewer / Map Editor 清理 box fallback 主链

#### 目标

让 `bevy_debug_viewer` 和 `bevy_map_editor` 即使收到 shared scene，也不会再把正式世界内容回退成普通 box。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\apps\bevy_debug_viewer\src\render\world\static_world.rs`](D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/render/world/static_world.rs) 仍保留 `collect_static_world_box_specs()` 和大量 role 映射
- `bevy_map_editor` 虽已主要走 shared render，但仍会被 shared fallback 语义影响

#### 改动范围

- `bevy_debug_viewer`
- `bevy_map_editor`
- 必要时调整 `game_bevy::world_render` 对外 API

#### 实现要点

- viewer 的 box 收集逻辑只保留：
  - pick proxy
  - 需要独立 outline 盒的 proxy
  - debug draw / warning / trigger overlay
- 对已 tile 化的墙、地板、surface、prop，不再保留 “SharedRole -> 普通 box 样式” 映射
- map editor 继续只走 shared `spawn_world_render_scene()`；如果 editor 还有对 shared box role 的显式假设，一并去掉
- viewer 的材质 fade/occlusion 系统要确认只作用在真正仍存在的 box proxy 和 tile instance 上，不再为旧主渲染 box 保留特判

#### 验收标准

- viewer 中 `collect_static_world_box_specs()` 的产物主要是 proxy/debug，不再混入正式主几何
- map editor 视觉不再依赖 shared fallback box role
- 同一地图在 viewer/editor 里不出现“shared tile 成功，但 editor/viewer 还套一层 box”的双层显示

#### 风险与非目标

- 本子阶段不重写 editor 渲染，只做 shared 入口收口后的最小整理
- viewer 的 hover 轮廓允许继续依赖 proxy，但不是正式可见体块

### 2.3 删除无调用方旧 helper 与最终 fallback 分支

#### 目标

在前两步稳定后，删掉已无意义的 fallback helper、旧 shader/material routing 和不再被引用的兼容分支。

#### 当前状态

- `spawn_box()`、部分 role color、部分静态世界 helper 仍兼容旧主渲染语义
- 某些 helper 已不再承担真正运行职责，但还保留在 API 面上

#### 改动范围

- `game_bevy::world_render`
- `game_bevy::static_world`
- `bevy_debug_viewer`

#### 实现要点

- 清理“如果没有 prototype 就临时画 box”的长期兼容思路
- 删除已不可能再被正常路径触达的 building/ground/location fallback 分支
- 把剩余 `spawn_box()` 的调用点限制在 proxy/debug 范围内，并更新命名或注释
- 为“仍未 tile 化的过渡内容”建立明确清单，避免隐藏在 shared helper 里继续扩散

#### 验收标准

- 删除后，shared/world_render/viewer 不再保留正式世界内容的 box 兼容后门
- 阶段 3 可以在一个明确的 instanced/tile 世界基础上开始做实例升格

#### 风险与非目标

- 本子阶段不追求 API 最终美化，目标是先删掉结构性双轨
- 若仍有极少量过渡对象依赖 box，必须显式标注，不允许默默保留通用 fallback

### 阶段 2 推荐施工顺序

1. 先做 2.1 shared role 收口，先把边界说清。
2. 再做 2.2 viewer/editor 适配，让消费端真正停止回退。
3. 最后做 2.3 删 helper 和后门，避免删早了影响排查。

### 阶段 2 完成判定

- `StaticWorldBoxSpec` 已明确退化为 proxy/debug 容器
- viewer/editor 的正式世界内容不再存在 box fallback 主链
- shared 中与建筑地板、地表、地点标记对应的旧正式 box role 已删除或不再被主路径引用
- 从这个点开始，“box 主渲染”应被视为 bug 或过渡项，而不是允许存在的默认行为

---

## 阶段 3：实例升格为独立动态实体

### 目标

解决“instanced 静态世界”和“可交互 / 可动画 / 可破坏 / 可物理模拟对象”之间的运行时冲突。

### 核心原则

不是所有对象都永久 instanced。

正确模型是：

- 静态时：作为 instanced placement 存在
- 激活时：从 batch 中脱离，升格为独立实体
- 动作结束后：可选择保持独立，或回收到 batch

### 需要支持的对象类型

- 箱子 / 柜子打开
- 门类动画
- 可破坏物件
- 进入物理模拟的对象
- 有独立 runtime state 的环境机关

### 建议的实例状态分类

- `StaticInstanced`
  - 永远 batch
- `ReactiveInstanced`
  - 默认 batch，交互时升格
- `DynamicUnique`
  - 从一开始就是独立实体

### 主要实施点

- 在 shared runtime 引入“实例句柄 -> 动态实体”的切换机制
- 让 viewer / game runtime 能隐藏指定 batch instance
- 为 prototype definition 增加 behavior / upgrade policy 元数据
- 为动态实体保留与原 map object / tile instance 的语义绑定

### 这一步完成后应满足

- 可交互静态物件默认走 instanced
- 触发动画或破坏时，实例可无缝切到独立实体
- pick / outline / occlusion / interaction 语义在切换前后保持稳定

### 验收标准

- 一个 instanced 柜子可被交互，交互后变成独立动态实体
- 一个可破坏场景物件可从静态实例切为破坏态实体
- viewer 中 hover / outline 不因升格丢失目标语义

### 阶段 3 实施拆解

阶段 3 需要把“静态实例”和“动态实体”之间的切换机制独立成 shared runtime 能力，而不是散落在 viewer 或单个对象类型里。建议拆成 4 个子阶段。

### 3.1 定义实例生命周期模型与句柄体系

#### 目标

先建立“一个 tile/prop instance 在 runtime 中如何被识别、隐藏、升格、回收”的统一模型。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\world_render\tile_assets.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/world_render/tile_assets.rs) 已有 `WorldRenderTileInstanceHandle`
- 当前 handle 主要服务渲染批次和 viewer 单格语义映射，还不是完整生命周期句柄

#### 改动范围

- `game_bevy::world_render`
- `game_bevy` shared runtime state
- 必要时扩展 `game_data` behavior schema

#### 实现要点

- 明确实例 identity：
  - `batch_id + instance_index` 只是渲染句柄
  - 还需要一个更稳定的“内容语义句柄”，用于跨重建/重批次保持对象身份
- 定义实例生命周期状态：
  - 在 batch 中可见
  - 在 batch 中隐藏但语义仍存在
  - 已升格为独立实体
  - 已销毁或已替换
- 设计 shared 升格接口，不让 viewer 私自操作实例集合

#### 验收标准

- 可以稳定表达“哪个实例被升格了”
- shared 层有统一数据结构追踪实例生命周期

#### 风险与非目标

- 本子阶段先定义模型，不直接接入所有对象类型
- 不要求先解决 save/load，只解决当前 session runtime 切换

### 3.2 Shared 批实例隐藏 / 替换机制

#### 目标

让 instanced batch 支持按实例隐藏、替换 tint/fade，作为升格前后的可见层基础。

#### 当前状态

- 当前 instancing backend 已支持 per-instance `fade_alpha`、`tint`
- 但“被升格实例从 batch 中彻底隐藏并避免继续参与逻辑拾取”的机制还未被框定成统一能力

#### 改动范围

- `game_bevy::world_render`
- `bevy_debug_viewer` 交互层

#### 实现要点

- shared 层增加“实例可见性/替换状态”资源或组件，不让 viewer 直接改底层 batch 列表
- 被升格实例至少需要：
  - 渲染隐藏
  - pick proxy 迁移或禁用
  - occluder 数据同步迁移到动态实体
- 保持 tile batch 同步系统能稳定处理“某些实例暂时不可见”的状态

#### 验收标准

- 单个实例能从 instanced batch 中隐藏，而同 batch 其他实例不受影响
- hover / occlusion 不会继续命中一个已升格隐藏的静态实例

#### 风险与非目标

- 本子阶段不处理复杂动画，只提供切换所需的基础可见性控制
- 不要求 batch 热重排，首版允许隐藏实例仍占用索引位

### 3.3 动态实体升格管线

#### 目标

建立从静态实例到独立动态实体的统一 spawn/replace 流程，供门、柜子、破坏物等复用。

#### 当前状态

- 门已有部分 shared behavior schema 基础，但其运行时动态切换还没被抽象成统一模式
- prop placement 已有 prototype + semantic 绑定，但“升格后如何接动态表现”还未成体系

#### 改动范围

- `game_bevy::world_render`
- `game_core` 与 runtime 集成层
- `bevy_debug_viewer`

#### 实现要点

- 统一升格输入应至少包含：
  - 源实例语义句柄
  - 目标 prototype / scene / behavior
  - 初始世界变换
  - 是否承接 occluder / pick / outline 资格
- 升格后动态实体需要保留对原语义对象的引用，避免 tooltip/hover 断链
- 首批接入对象建议按难度排序：
  - 门
  - 柜子/箱子
  - 可破坏 prop

#### 验收标准

- 一个带门行为的实例能切到独立动态门实体
- 一个柜子实例能在交互时切到独立实体并播放动画或切换状态

#### 风险与非目标

- 本子阶段不要求所有动态对象共用一套动画系统
- 不把物理模拟细节硬塞进 tile world，本阶段只做切换边界

### 3.4 回收 / 持久独立 / 状态同步策略

#### 目标

补完“升格后是否回收、何时回收、如何保持状态”的策略，不让 runtime 进入只升不管的失控状态。

#### 当前状态

- 目前尚无统一“回收到 batch”或“永久离开 batch”的 shared 策略

#### 改动范围

- `game_bevy` runtime
- `game_core` state/query 层
- 必要时扩展 `game_data` behavior metadata

#### 实现要点

- 为不同对象定义最小策略：
  - 门通常可回收
  - 被破坏物件通常不回收，而是进入替换态
  - 已产生独立持久 state 的容器通常保持独立或替换为“已打开”静态态
- 同步策略要区分：
  - 纯视觉临时动画
  - 会影响 gameplay 的真实状态变化
- 明确 viewer 重建世界时如何重新关联已升格或已替换对象

#### 验收标准

- 动态实体不会在一次交互后遗失身份
- viewer 重建或切图后，已改变状态的对象不会错误回到原始静态实例外观

#### 风险与非目标

- 本子阶段不做完整存档系统设计，只要求 runtime 生命周期自洽

### 阶段 3 推荐施工顺序

1. 先做 3.1 生命周期模型。
2. 再做 3.2 实例隐藏与可见性控制。
3. 然后做 3.3 升格管线，并先接门和柜子。
4. 最后做 3.4 回收/替换策略，避免早期过度设计。

### 阶段 3 完成判定

- shared runtime 已具备实例句柄、隐藏、升格、替换的统一能力
- 至少门和一类容器 prop 已走通完整升格链
- viewer hover/outline/occlusion 在切换前后保持稳定
- 阶段 4 可以在已明确的行为模型之上扩展 schema，而不是反向驱动 runtime

---

## 阶段 4：补完整 Prototype / TileSet / Behavior Schema

### 目标

把当前“够用但还偏首版”的 prototype 内容模型，补成长期稳定 schema。

### 需要补充的结构方向

- prop prototype metadata
- wall set / surface set 的完整约定
- prototype bounds / pivot / facing 规范
- 可交互行为入口
- 动画资源绑定入口
- 破坏态/替换态入口
- pick proxy / occluder policy

### 设计原则

- 内容权威放在 `game_data`
- runtime 只消费 schema，不做 viewer 私有推断
- 新增 prototype / set 不要求改 shared 渲染框架 API

### 主要实施点

- 扩展 `WorldTilePrototypeDefinition`
- 扩展 wall/surface set 内容定义
- 为 map object visual spec 和 building tile set spec 补完整字段
- 加强内容校验和引用完整性检查

### 这一步完成后应满足

- 新增一种墙体、地表或环境物件，不需要再改 renderer 结构
- 内容数据可以显式描述对象是静态实例、可升格实例还是独立动态对象

### 验收标准

- `game_data` 中 prototype / set / behavior 的 schema 能覆盖现有世界内容
- 缺失引用、无效 prototype id、非法组合都会在加载时明确报错

### 阶段 4 实施拆解

阶段 4 不是单纯“多加几个字段”，而是把目前首版能跑通的 prototype/tile set 模型补成长期可演进的内容协议。建议拆成 4 个子阶段。

### 4.1 Prototype 元数据补全

#### 目标

先把单个 prototype 自身应描述的元数据补齐，避免 runtime 继续从 viewer 或美术约定里猜。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_data\src\world_tiles.rs`](D:/Projects/cdc-survival-game/rust/crates/game_data/src/world_tiles.rs) 当前 `WorldTilePrototypeDefinition` 只包含 source、bounds、shadow、door_behavior 等基础字段

#### 改动范围

- `game_data::world_tiles`
- `game_bevy::world_render`

#### 实现要点

- 补充 prototype 级元数据方向：
  - facing / canonical orientation
  - pivot 约定
  - 可选的 pick proxy policy
  - 可选的 occluder policy
  - 可选的 interaction/upgrade class
- 原则是让 renderer/runtime 消费清晰 schema，而不是继续在调用点散写规则

#### 验收标准

- world render 不再需要为同类 prototype 写一堆硬编码推断
- prototype 元数据足以覆盖现有墙、门、基础 prop

#### 风险与非目标

- 本子阶段不追求一步到位覆盖未来所有美术需求，先覆盖当前系统真正要消费的字段

### 4.2 Wall Set / Surface Set 约定补全

#### 目标

把墙体和地表 tile set 的“拓扑到 prototype”的映射约定补完整，确保新 set 不需要改 renderer。

#### 当前状态

- 当前 wall set 已有 6 个 archetype 原型引用
- current surface set 已有 flat/ramp/cliff 的基础入口，但约定仍偏首版

#### 改动范围

- `game_data::world_tiles`
- `game_bevy::tile_world`
- 内容校验层

#### 实现要点

- 明确 wall set 约定：
  - archetype 数量固定还是可扩展
  - 是否允许某些 archetype 缺失
  - 默认朝向与旋转规则
- 明确 surface set 约定：
  - flat/ramp/cliff/角块的最小必填项
  - 缺失某类 prototype 时运行时的允许行为
  - tactical/overworld 是否共享同一 surface set 规范
- 把这些约定写进 schema 校验，不要只留在人脑里

#### 验收标准

- 新增一个 wall set 或 surface set 时，不需要改 shared render 代码
- 缺少必要原型或方向不合法会在加载期报错

#### 风险与非目标

- 不要求这一步就支持特别复杂的自动拼缝算法，只要约定能支撑现有和近期内容

### 4.3 行为与升格 schema 接口化

#### 目标

把阶段 3 runtime 需要的行为入口正式落到 schema，而不是留在代码中的临时分支。

#### 当前状态

- 当前只看到 `door_behavior` 这种点状入口，远不足以表达容器、破坏物、替换态等

#### 改动范围

- `game_data::world_tiles`
- `game_data::map`
- `game_bevy` runtime

#### 实现要点

- 设计可扩展的 behavior schema：
  - door behavior
  - container/openable behavior
  - destructible behavior
  - reactive upgrade policy
- 让 map object / building tile set / prototype definition 之间的职责边界清晰：
  - prototype 定义“这个模型具备什么能力”
  - map object 定义“这个实例是否启用、如何绑定语义”
- 保持 schema 是 declarative 的，不把具体动画状态机塞进数据定义

#### 验收标准

- 阶段 3 的升格 runtime 可以直接消费 schema，不再依赖硬编码对象类型判断
- 新增一个可交互 prop 时，优先改内容数据而不是改 viewer 逻辑

#### 风险与非目标

- 本子阶段不把完整交互脚本语言做进 schema
- 不追求把所有 gameplay 规则都塞进 prototype definition

### 4.4 内容校验、迁移与默认内容收口

#### 目标

把新 schema 真正落到内容库中，并通过校验保证引用完整。

#### 当前状态

- `game_data` 已有一部分 world tile catalog 校验
- 但后续扩展字段、行为入口、surface/wall set 约定还未配套完整迁移与校验

#### 改动范围

- `game_data`
- 仓库内 world tile catalog 内容文件
- 必要的迁移脚本或 bootstrap 默认内容

#### 实现要点

- 更新现有 catalog/default content，补全缺失字段
- 对缺失 prototype、非法 set、行为和原型不匹配等情况增加显式报错
- 如有必要，提供一次性迁移脚本，把老内容升级为新 schema

#### 验收标准

- 现有内容都能在新 schema 下加载通过
- 故意构造的非法内容会在加载/校验阶段失败

#### 风险与非目标

- 本子阶段不要求做复杂可视化内容编辑器，只保证 schema 和现有数据闭环

### 阶段 4 推荐施工顺序

1. 先做 4.1 prototype 元数据补全。
2. 再做 4.2 wall/surface set 约定。
3. 然后做 4.3 行为与升格 schema。
4. 最后做 4.4 内容迁移与校验收口。

### 阶段 4 完成判定

- prototype / wall set / surface set / behavior schema 已形成可扩展内容协议
- 阶段 3 runtime 不再依赖大量对象类型硬编码
- 新增一种墙、地表或 prop 时，优先只需改 catalog 和内容数据
- 阶段 5 可以在稳定 schema 基础上做资产流水线，不必反复改内容格式

---

## 阶段 5：补完整离线资产流水线与最终收口

### 目标

把当前 placeholder 资产 + 首版烘焙工具，扩展成正式可持续使用的资产流水线，并做最终性能与链路收口。

### 资产流水线要求

- 程序化 placeholder 可重复离线烘焙
- 正式美术资产能无缝替换 placeholder prototype
- prototype catalog 与实际 glTF 资产一致
- pivot / bounds / scene index / primitive flatten 行为可自动校验

### 最终收口要求

- viewer / map editor / shared render 行为一致
- shared tile batch 是静态世界渲染主干
- draw call / batch 数量可观测
- occlusion / fade / hover / outline / pick proxy 行为稳定

### 主要实施点

- 完善 `bake_world_tile_placeholders` 一类工具
- 加 asset validation / catalog validation
- 为 batch / instance 统计补 profiling 指标
- 做最后一轮无用旧链清理

### 这一步完成后应满足

- placeholder 到正式美术替换只改资产和内容定义，不改运行时拼接逻辑
- 运行时不再依赖程序化生成建筑墙 mesh
- tile-based 3D world 框架成为默认世界构造方式

### 验收标准

- `cargo check`
- `cargo test -p game_data -p game_bevy -p bevy_debug_viewer`
- viewer / editor 手动 smoke
- 至少一组正式或半正式美术 prototype 能替换 placeholder 并保持同样拼接逻辑

### 阶段 5 实施拆解

阶段 5 建议拆成“烘焙工具稳定化、catalog/资产一致性校验、性能观测、最终删旧链”四段。这个阶段的目标不是继续发明新 runtime，而是把前四阶段收成可长期维护的生产链。

### 5.1 Placeholder 烘焙工具稳定化

#### 目标

把现有一次性 placeholder 烘焙入口整理成可重复运行、结果稳定、适合后续回归验证的工具。

#### 当前状态

- [`D:\Projects\cdc-survival-game\rust\crates\game_bevy\src\bin\bake_world_tile_placeholders.rs`](D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/bin/bake_world_tile_placeholders.rs) 已存在首版烘焙工具
- 当前更偏 bootstrap，用于生成墙体 placeholder glTF 与 catalog 片段

#### 改动范围

- `game_bevy` 烘焙工具
- `rust/assets/world_tiles`
- 相关文档/命令说明

#### 实现要点

- 明确输入输出目录约定
- 保证重复运行结果稳定，不产生无意义 diff
- 为墙体 archetype、默认朝向、bounds/pivot 生成结果增加最小验证
- 视情况补“只重烘某个 set”或“全量重烘”模式

#### 验收标准

- placeholder 工具可稳定重复执行
- 生成的 glTF/GLB 与 catalog 内容不会因重复运行无故漂移

#### 风险与非目标

- 本子阶段不做完整 DCC 导出链，只稳定当前 placeholder 入口

### 5.2 资产与 catalog 一致性校验

#### 目标

确保 `game_data` 中的 prototype 定义与 `rust/assets` 里的 glTF 资产真正一致，避免运行时才发现路径、scene index、bounds 错误。

#### 当前状态

- 当前 world tile catalog 已有基础引用校验
- 但还缺 asset 层面的存在性、scene index、primitive flatten、bounds/pivot 对齐校验

#### 改动范围

- `game_data`
- `game_bevy`
- 可能新增离线检查命令

#### 实现要点

- 校验内容至少包括：
  - 资产路径存在
  - `scene_index` 合法
  - prototype bounds 与实际资产局部 bounds 没有明显背离
  - flatten 后 primitive 数非空
- 把这类校验设计成可在 CI 或本地命令里直接跑的检查，不依赖 viewer 手工打开

#### 验收标准

- 错误路径、错误 scene index、空 scene、明显错误 bounds 都会被离线检查发现
- 正式美术替换 placeholder 时有明确校验入口

#### 风险与非目标

- 本子阶段不强求全自动重写 bounds，只要求能发现错误

### 5.3 性能观测与批次统计

#### 目标

让 tile-based instanced world 的性能收益可以被观察、比较，而不是只靠体感。

#### 当前状态

- 当前 custom instancing backend 已能批渲染
- 但缺少 batch 数、instance 数、prototype 命中、回退数量等系统性统计

#### 改动范围

- `game_bevy::world_render`
- `bevy_debug_viewer` 调试 UI 或日志

#### 实现要点

- 提供最小 profiling 指标：
  - tile batch 数
  - 总实例数
  - 每类 render class 实例数
  - 被隐藏/升格实例数
  - 仍走 box/proxy 的对象数量
- viewer 中可以提供 debug overlay 或日志面板查看这些指标
- 对 placeholder 与正式美术替换前后，保留相同统计口径

#### 验收标准

- 能快速回答“当前地图有多少 batch / instance / fallback”
- 用户可以明确看到 instancing 后的 draw/batch 收敛情况

#### 风险与非目标

- 本子阶段不做复杂 GPU profiler 集成，只做框架级可观测性

### 5.4 最终删旧链与默认基线切换

#### 目标

把 tile-based 3D world 正式设为默认世界构造方式，清理不再需要的程序化运行时建模和旧调试替代链。

#### 当前状态

- 当前仍有部分程序化 builder、旧 static world box/helper、fallback material 语义留作过渡
- 文档上已把 tile world 视为主线，但代码层仍有过渡残留

#### 改动范围

- `game_bevy`
- `bevy_debug_viewer`
- `bevy_map_editor`
- 相关资产和内容默认配置

#### 实现要点

- 运行时不再依赖程序化墙格 mesh 生成，builder 只保留给离线烘焙/测试
- 把 shared tile world 设为默认世界主渲染入口
- 清理已被 placeholder/prototype/cached runtime 取代的旧 helper
- 把文档、默认内容、构建验证命令统一到新基线

#### 验收标准

- 默认运行路径不再需要旧程序化墙格 runtime builder
- viewer/editor/shared render 都以 tile/prototype/placement 为默认基线
- 剩余旧链仅存在于明确的测试或离线工具中

#### 风险与非目标

- 本子阶段不要求把所有历史调试工具都删光，但必须把它们降为非默认、非主链

### 阶段 5 推荐施工顺序

1. 先做 5.1 烘焙工具稳定化。
2. 再做 5.2 资产与 catalog 校验。
3. 然后做 5.3 性能观测。
4. 最后做 5.4 默认基线切换和删旧链。

### 阶段 5 完成判定

- placeholder 与正式美术资产都能通过统一 catalog + 校验链接入
- tile world 的 batch/instance/fallback 情况可观测
- 默认运行路径完全站在 tile/prototype/placement 基线上
- 这套框架已经从“迁移中方案”变成“仓库默认世界构造方式”

---

## 推荐实施顺序

建议严格按以下顺序推进：

1. 阶段 1：先把大多数静态世界内容并入 tile world
2. 阶段 2：再清旧 box/fallback，避免双轨长期并存
3. 阶段 3：然后补实例升格机制，解决动态对象问题
4. 阶段 4：再把 schema 补完整，避免中途频繁返工数据结构
5. 阶段 5：最后做资产流水线和全链收口

原因很直接：

- 如果先做动态升格，而静态世界本身还没统一进 tile world，会出现两套并存状态机
- 如果 schema 先过度设计，而静态渲染主干还没稳定，容易反复修改字段
- 如果太早做最终清理，容易把过渡工具链删掉导致中途施工困难

## 里程碑定义

### 里程碑 A：静态世界统一

完成阶段 1 + 阶段 2 后，达到：

- 建筑墙、地板、地表、环境物件大多走 shared tile world
- 正式世界外观基本脱离普通 box/fallback 路径

### 里程碑 B：运行时可扩展

完成阶段 3 后，达到：

- instanced 静态世界与动态交互对象可以共存
- 箱子/柜子/门/可破坏物件有稳定 runtime 路径

### 里程碑 C：正式框架闭环

完成阶段 4 + 阶段 5 后，达到：

- 内容 schema、资产流水线、shared render、viewer/editor、运行时动态切换都闭环
- 这套框架可以作为后续地图、建筑、地形、环境构造的长期基线

## 非目标

本路线默认不包括以下内容：

- Godot 端重建同样的 tile world 逻辑
- 为旧 Godot 世界内容链保留长期兼容双写
- 把所有动画都强行塞进 instancing
- 在 editor 本地重建一套私有 prototype/runtime 世界渲染逻辑

## 一句话结论

这条完整框架线的核心，不是“把所有东西都变成 instancing”，而是：

**把世界静态构造统一到 tile/prototype/placement，把运行时动态行为统一到实例升格机制，并让 shared render 成为 viewer 与 editor 的共同基线。**
