# Godot 原生场景化重构计划

## 背景

当前地图已经从纯数据驱动逐步迁移到 Godot `.tscn` 场景，但仍保留了一些迁移期做法：用通用标记节点、字符串 `kind`、多行 JSON 和运行时 `metadata` 承载具体玩法语义。

这些做法能快速兼容旧数据层，但不够 Godot 原生：

- Inspector 里字段不直观，很多配置藏在 `props_json`。
- 不同类型对象共用 `MapObjectNode`，语义边界不清晰。
- 运行时依赖 `has_method("to_object_definition")`、`node.get("kind")`、`set_meta()` 之类弱约束。
- Editor 里可见的节点结构和运行时真正使用的交互、碰撞、状态表现仍有割裂。

本计划目标是把地图对象逐步迁移成更 Godot 原生的 typed scene / typed node 工作流，同时保留当前 simulation、存档和 interaction 数据结构的稳定性。

## 当前发现

### 通用地图对象节点过载

`MapObjectNode` 当前承担了多种对象职责：

- `trigger`
- `building`
- `prop`
- `pickup`
- `interactive`
- `ai_spawn`

这些对象在 `.tscn` 中都通过相同字段描述：

- `object_id`
- `kind`
- `footprint`
- `grid_rotation`
- `blocks_movement`
- `blocks_sight`
- `props_json`

问题在于 `kind` 和 `props_json` 实际决定了对象行为，但 Godot Inspector 无法明确表达这些差异。Trigger、拾取物、容器、刷怪点、静态建筑都混在同一个类中，长期会增加误配成本。

### 地图入口点仍是弱类型字符串

`MapEntryPointNode` 已经继承 `Marker3D`，方向上比较接近 Godot 原生做法，但 `facing` 仍是普通字符串。入口点没有显式校验、没有 editor 提示，也没有统一可视化方向辅助。

### TransitionMarker 仍使用字符串变体和运行时生成子节点

`TransitionMarker` 已经解决了紫色 fallback 圆盘问题，但目前仍通过：

- `marker_kind = "subscene" | "outdoor" | "overworld"`
- 脚本动态实例化 glTF / BoxMesh 子节点
- `set_meta("transition_marker", true)`

来描述视觉变体。

更 Godot 原生的形态应是可直接打开和编辑的具体场景，例如门型入口、区域入口、大地图出口各自一个 `.tscn`，而不是所有变体都藏在一个脚本分支里。

### 运行时 renderer 还在用弱反射和 metadata 拼接场景语义

`WorldSceneRenderer` 当前会：

- 扫描节点是否 `has_method("to_object_definition")`
- 读取 `node.get("object_id")` 和 `node.get("kind")`
- 给视觉节点补 `interaction_target` metadata
- 运行时生成 `PickableBody`
- 根据字典数据补 `DoorStateVisual`、`ContainerStateBadge`
- 在没有视觉子节点时生成 `MapObjectFallbackVisual`

这套逻辑适合作为迁移期兼容层，但长期看不够场景化。交互目标、拾取碰撞、门状态、容器状态都应该逐步变成明确的 Node / Area3D / 组件脚本，而不是散落在 metadata 中。

### 运行时临时表现大量依赖 metadata

输入预览、动作表现、战斗反馈、移动路径、技能范围等运行时临时节点大量使用 `set_meta()` 存诊断信息。

这类临时表现不是首要问题。它们主要服务 smoke、调试和 UI hover，不一定需要全部迁移成强类型节点。优先级应低于地图对象和交互对象的场景化。

## 目标形态

### 地图对象改为 typed node

保留一个轻量基类，例如 `MapSceneObject3D`，只负责所有地图对象共有字段：

- `object_id`
- `footprint`
- `grid_rotation`
- `blocks_movement`
- `blocks_sight`
- `to_object_definition()`

在此基础上拆出具体类型：

- `MapTransitionTrigger3D`
- `MapPickup3D`
- `MapContainer3D`
- `MapSpawnPoint3D`
- `MapStaticProp3D`
- `MapBuilding3D`
- `MapDoor3D`

每个具体类型用明确的 exported fields 取代 `props_json` 中的关键字段。`props_json` 可以短期保留为兼容扩展字段，但不再作为主要配置入口。

### Trigger 改为 Area3D 场景

地图切换 Trigger 适合迁移成 `Area3D` 或包含 `Area3D` 子节点的 typed scene：

- 节点本身声明目标地图、目标入口点、交互文案 id。
- `CollisionShape3D` 在 Editor 里可见、可调整。
- `TransitionMarker` 作为视觉子场景挂在同一个 Trigger 场景下。
- 运行时 picking 优先使用场景内 `Area3D`，只在旧对象缺失时生成兼容 pickable proxy。

### 拾取物和容器改为具体场景

拾取物和容器应从 `kind + props_json` 迁移到独立场景：

- `MapPickup3D`：导出 `item_id`、`count`、`display_name`、`visual_scene`。
- `MapContainer3D`：导出 `container_id`、`container_type`、`loot_table_id` 或初始物品、可选锁状态。
- `PickableBody` / `Area3D` 作为场景固定子节点，而不是运行时补出来。
- 容器开启、为空、锁定等状态表现用专门子节点脚本更新。

### 刷怪点改为 Marker3D

`ai_spawn` 应改成 `MapSpawnPoint3D extends Marker3D`：

- 导出 `actor_definition_id`、`spawn_group`、`spawn_count`、`facing`。
- Editor 中用 gizmo / 小型可视化标记区分敌人、NPC、剧情刷点。
- 运行时仍导出为旧 map definition 中兼容的 spawn 数据。

### 建筑和静态物件改为可实例化 prefab

建筑、墙、家具、路障等适合成为具体 `.tscn` prefab：

- 视觉模型、材质、碰撞、遮挡、占格信息在 prefab 里声明。
- 地图场景只实例化 prefab 并设置 id / 朝向 / 少量覆盖项。
- 对纯视觉 prop，不需要进入 interaction target，也不需要运行时 fallback。

### EntryPoint 增强为可视化 Marker

`MapEntryPointNode` 可以保留 `Marker3D` 基础，但需要改进：

- `facing` 使用 `@export_enum("north", "east", "south", "west")`。
- 增加 editor-only 方向箭头或小型标记。
- 增加 entry id 为空、重复、目标引用不存在的 scene smoke 检查。

### SceneRoot 使用分组或基类收集节点

`MapSceneRoot` 不应继续只靠脚本等值判断具体类。推荐改为：

- 地图对象基类统一实现 `to_object_definition()`。
- 具体对象加入 `map_scene_object` group。
- 入口点加入 `map_entry_point` group。
- 收集时优先按 group / typed base class，兼容期再 fallback 到旧 `MapObjectNode`。

## 非目标

本计划不要求把所有核心 simulation 数据都改成 Godot 节点。

以下内容短期继续保留 Dictionary / JSON 是合理的：

- 存档 snapshot。
- simulation command / event payload。
- UI snapshot。
- 任务、物品、角色、配方等内容数据。
- smoke 中用于断言的诊断 metadata。

Godot 原生化的重点是 Editor 可摆放、可查看、可调整的世界场景对象，而不是把纯规则数据强行节点化。

## 迁移顺序

### 阶段 A：建立 typed 地图对象基础

- 新增 `MapSceneObject3D` 基类。
- 让现有 `MapObjectNode` 继承或适配该基类，保持旧场景可用。
- `MapSceneRoot` 改为优先收集 `map_scene_object` group，再兼容旧脚本。
- 增加 scene smoke，统计旧 `MapObjectNode` 和新 typed nodes 数量。

验收标准：

- 所有现有地图 scene 可加载。
- `to_definition()` 输出与迁移前保持兼容。
- 旧节点不被迫一次性改完。

### 阶段 B：先迁移地图切换 Trigger

- 新增 `MapTransitionTrigger3D`。
- 将目标地图、目标入口、interaction kind、显示文本等从 `props_json.trigger` 提升为 exported fields。
- 让现有 `TransitionMarker` 视觉实例成为 Trigger 场景子节点。
- 为 Trigger 场景添加固定 `Area3D` / `CollisionShape3D`。
- `WorldSceneRenderer` 对新 Trigger 不再生成 pickable proxy，只同步必要 runtime state。

验收标准：

- 16 个地图切换 Trigger 不再依赖 `kind="trigger"` 和 JSON 配置表达核心语义。
- Editor 中能直接看出每个 Trigger 的目标地图和入口。
- 跳图行为不变。

### 阶段 C：迁移拾取物、容器和可交互对象

- 新增 `MapPickup3D`、`MapContainer3D`、`MapInteractiveObject3D`。
- 将拾取物的 item/count、容器的 container/loot/lock 字段从 JSON 提升到 exported fields。
- 把 `PickableBody` 改为场景子节点。
- 容器状态 badge / 门状态 visual 改为独立子节点脚本控制。

验收标准：

- 据点、医院、工厂、警戒区中的 pickup / interactive 对象可逐步迁移。
- 运行时 interaction menu 行为不变。
- 缺失视觉时仍可 fallback，但真实场景对象不再显示 fallback。

### 阶段 D：迁移刷怪点

- 新增 `MapSpawnPoint3D extends Marker3D`。
- 迁移 `ai_spawn` 对象。
- 增加 editor-only 可视化，避免刷怪点在 Editor 中不可见或难以区分。

验收标准：

- 工厂、医院、警戒区的刷怪点使用 typed Marker。
- scene smoke 能检查 spawn actor id 是否存在。

### 阶段 E：迁移建筑和静态 prop prefab

- 将建筑、墙段、家具、路障整理成可复用 `.tscn` prefab。
- prefab 内声明视觉、碰撞、遮挡、占格默认值。
- 地图 scene 只负责实例化和局部覆盖。
- 逐步减少大型地图中手写重复节点块。

验收标准：

- `survivor_outpost_01` 的建筑和家具可在 Editor 中按 prefab 管理。
- `building` / `prop` 不再大量依赖 JSON visual 配置。
- 运行时加载地图视觉时不再需要为这些对象补 fallback。

### 阶段 F：收紧 renderer 兼容层

- `WorldSceneRenderer` 从“发现弱类型节点后补一切”改为“同步 typed scene object 的 runtime state”。
- `MapObjectFallbackVisual` 只服务旧数据和 smoke synthetic world。
- `interaction_target` metadata 只作为拾取桥接，不作为场景对象主数据。
- 对 `has_method("to_object_definition")` 的依赖逐步替换为 typed base class / group。

验收标准：

- 新地图对象不依赖 metadata 保存核心配置。
- fallback 逻辑仍存在，但真实地图 scene 默认不触发。

## 验证计划

每个阶段至少运行：

- `tools/agent/test-godot-static.ps1 -Scenario CheckOnly`
- `tools/agent/test-godot-game.ps1 -Scenario Scene`
- `tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01`
- `tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01_interior`
- `tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01_perimeter`
- `git diff --check`

涉及交互对象时额外运行：

- `tools/agent/test-godot-game.ps1 -Scenario Interaction`
- 相关 pickup / container / transition smoke。

## 风险与边界

- 不要一次性把所有地图对象改完。先让旧节点和新 typed nodes 共存。
- 不要在迁移 typed scene 时修改存档 schema、interaction target schema 或 simulation command。
- 不要把纯数据层内容强行场景化。内容数据仍应保留 JSON / Resource / Dictionary 形式。
- 不要移除 fallback。fallback 仍然是旧数据、工具 smoke 和缺资源场景的安全网。
- 每次迁移一个对象类型后都要跑 scene smoke，避免 Editor 可见但运行时 definition 丢字段。

## 推荐优先级

优先级最高的是地图切换 Trigger，因为它已经开始场景化，且现有视觉改造刚完成，继续类型化收益最大。

其次是 pickup / container / interactive，因为它们直接影响玩家交互和拾取碰撞。

刷怪点和建筑 prefab 可以随后推进。运行时临时表现 metadata 暂时不作为主线重构目标。
