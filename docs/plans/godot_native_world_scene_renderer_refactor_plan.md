# WorldSceneRenderer Godot 原生激进重构方案

本文定义 `godot/scripts/world/world_scene_renderer.gd` 的激进拆分路线。目标不是兼容式瘦身，而是把运行时世界表现迁到真正的 Godot scene/node 架构：地图、地面、交互体、actor、相机、灯光和 overlay 都由明确的场景节点负责，旧 `WorldSceneRenderer` 不再作为长期入口，也不要求旧 smoke 原样保留。

本方案接受一次结构性破坏：可以删除 fallback 渲染、可以重写旧 smoke、可以替换 `render_world()` 调用点。验收标准从“旧路径还能跑”改为“新 Godot 原生路径稳定、可编辑、可运行、可验证”。

## 当前问题

- `WorldSceneRenderer` 是一个巨型 `RefCounted`，却在做多个 Godot 节点应该承担的事情。
- 地图 `.tscn` 已经存在，但运行时仍会生成 fallback ground、fallback object visual、fallback actor visual 和拾取代理。
- 交互、视觉、相机、灯光、状态标记混在同一个类里，导致地图 scene 无法成为真正的运行时表现权威。
- 旧 smoke 直接调用 `WorldSceneRenderer.new().render_world()`，把临时迁移入口固化成了测试契约。
- 运行时会清空并重建 `GeneratedWorld`，这和 Godot 中稳定 node、局部同步、信号驱动的常规做法冲突。

## 目标

- 删除 `WorldSceneRenderer` 的长期入口地位。
- 让 `WorldRoot` 挂载一个真实的 `WorldRuntimeRoot` 场景。
- 地图视觉只来自 `godot/scenes/maps/*.tscn`，不再运行时补地面或补建筑视觉。
- 地图对象节点自己声明交互、拾取、碰撞和业务 metadata，运行时只同步状态。
- actor、corpse、状态标记、相机、灯光各自进入独立 scene/node。
- 新增面向新架构的 smoke，旧 `WorldSceneRenderer` smoke 可以删除或重写。
- 运行时刷新从“整棵树重建”改为“稳定节点局部同步”。

## 非目标

- 不改规则层事实来源：Simulation、map definition、interaction target schema 仍然是 gameplay 权威。
- 不把地图改成 `GridMap`、`MeshLibrary` 或 ECS。
- 不保留旧 fallback 行为作为验收要求。
- 不保留旧 `GeneratedWorld` 命名作为兼容要求。
- 不要求旧 `scene_smoke` 断言继续成立。

## 核心原则

- `.tscn` 是视觉和空间节点权威，snapshot 只同步状态。
- 缺资源、缺地面、缺拾取体是内容错误，不是运行时 renderer 的兜底责任。
- 运行时 controller 只绑定数据和状态，不临时发明地图结构。
- actor node 稳定存在，移动、朝向、动画由节点和 Tween/AnimationPlayer 执行。
- 测试跟随目标架构重写，不用旧测试约束新设计。

## 目标场景结构

新增运行时世界场景：

```text
godot/scenes/world/world_runtime_root.tscn
```

建议节点结构：

```text
WorldRuntimeRoot
  MapSceneSlot
  InteractionController
  ActorLayer
  CorpseLayer
  WorldMarkerLayer
  CameraRig
  LightRig
  DebugOverlayLayer
```

对应脚本建议放在：

```text
godot/scripts/world/runtime/
```

## 目标节点职责

### WorldRuntimeRoot

替代 `WorldSceneRenderer` 的主入口，是一个真实 `Node3D`。

职责：

- 持有当前 map scene 实例。
- 管理 runtime 子层。
- 接收 world snapshot 和 runtime snapshot。
- 分发状态同步。
- 发出地图切换、世界刷新、同步完成等 signal。

建议接口：

```gdscript
signal world_synced(summary: Dictionary)
signal map_scene_changed(map_id: String)

func load_map(map_id: String) -> void
func sync_world(world_snapshot: Dictionary, runtime_snapshot: Dictionary = {}) -> Dictionary
func clear_world() -> void
func snapshot() -> Dictionary
```

### MapSceneSlot

只负责加载和持有地图 scene。

职责：

- 加载 `res://scenes/maps/<map_id>.tscn`。
- 要求根节点是 `MapSceneRoot` 或暴露 `map_id`。
- 校验地图 scene 必须包含地面、对象层和必要入口点。
- 加载失败直接报错给上层，不生成 fallback 地图。

建议接口：

```gdscript
func load_map_scene(map_id: String) -> Node3D
func current_map_root() -> Node3D
func validate_loaded_map() -> Array[Dictionary]
```

### InteractionController

只负责把 scene 中已有的 typed map object 绑定到运行时交互状态。

职责：

- 扫描 `MapTransitionTrigger3D`、`MapDoor3D`、`MapContainer3D`、`MapPickup3D`、`MapStaticProp3D`。
- 要求可交互对象自带 `Area3D` 或可拾取 `CollisionObject3D`。
- 同步 door open/locked、container open/empty、pickup available 等状态。
- 设置 `interaction_target` metadata。
- 不再为缺失对象生成 fallback mesh 或 fallback collider。

建议接口：

```gdscript
func bind_map_objects(map_root: Node, interaction_targets: Dictionary) -> Dictionary
func sync_target_state(object_id: String, target_data: Dictionary) -> void
func interactive_nodes() -> Array[Node]
```

### ActorLayer

负责 actor view 的稳定生命周期。

职责：

- 为 actor 创建或复用 `ActorView3D`。
- 同步 grid position、facing、health/AP/status snapshot。
- 与 `ActorViewController` 合并或改造成同一条主线。
- 移动表现走 Tween/AnimationPlayer，不通过整树重绘。

建议接口：

```gdscript
func sync_actors(actors: Array) -> Dictionary
func actor_view(actor_id: int) -> Node3D
func remove_missing_actors(active_actor_ids: PackedInt64Array) -> void
```

### CorpseLayer

负责 corpse view 的稳定生命周期。

职责：

- 根据 corpse snapshot 创建 `CorpseView3D`。
- 尸体资源缺失时报内容错误。
- 不再生成通用 fallback 方块。

### WorldMarkerLayer

负责世界空间标记，而不是把这些标记塞进 actor 生成流程。

职责：

- actor 名字、血条、AP 条。
- 状态效果 icon。
- 任务标记。
- 战斗飘字。
- 交互 hover 高亮。

标记跟随目标节点，不参与地图结构生成。

### CameraRig

负责相机节点和跟随逻辑。

职责：

- 跟随 actor view 或指定 grid/world position。
- 支持手动 pan、zoom、focus。
- 不由 world renderer 临时创建。

### LightRig

负责场景灯光。

职责：

- 默认灯光作为 scene 资产存在。
- 按地图或时间状态同步灯光参数。
- 不由 renderer 每次刷新重新生成。

### DebugOverlayLayer

负责 debug overlay。

职责：

- debug grid、path、vision、interaction bounds。
- 与正式 runtime layer 分离。
- 可以在 smoke 或 editor review 中打开。

## 地图 scene 新要求

所有运行时地图 scene 必须满足：

- 根节点是 `MapSceneRoot` 或等价 typed map root。
- 地面是 scene 中真实节点，不依赖运行时生成。
- 建筑、墙、地板、入口 marker 是 scene 中真实节点。
- 可交互对象使用 typed node。
- 可交互对象自带拾取区或碰撞体。
- `Visuals` 不再只是可选装饰，而是对象视觉权威。
- 缺少必要节点时，validator 报错，不进入运行时 fallback。

## 删除的旧行为

以下行为不再保留：

- `_spawn_ground()` fallback ground。
- `_add_map_object_fallback_visual()` fallback object。
- actor fallback capsule / box 作为正式表现。
- corpse fallback mesh 作为正式表现。
- 运行时为 scene object 临时补完整视觉。
- 以 `GeneratedWorld` 作为稳定测试断言。
- 直接调用 `WorldSceneRenderer.new().render_world()` 的 smoke。

迁移期间可以短暂保留旧代码，但不得作为主路径，也不得新增依赖。

## 新测试方向

旧 smoke 需要替换成面向新架构的测试。

### 新 scene smoke

目标：验证真实 map scene 可以作为运行时表现权威。

检查：

- 每个 map scene 可加载。
- map root 类型正确。
- 必须存在地面节点。
- 必须存在对象层。
- transition trigger、door、container、pickup 等 typed node 有拾取区。
- 引用资源可加载。

### 新 runtime world smoke

目标：验证 `WorldRuntimeRoot` 可以同步 snapshot。

检查：

- 可加载指定 map scene。
- actor view 创建并稳定复用。
- interaction metadata 绑定到已有 scene node。
- 地图切换会卸载旧 map scene 并加载新 map scene。
- 同步不会整树重建 actor view。

### 新 interaction smoke

目标：验证点击和 hover 走 typed scene node。

检查：

- trigger 点击命中 scene 中的入口 marker。
- door/container/pickup 点击命中自身 Area3D 或 CollisionObject3D。
- 没有 fallback collider 时仍可正常交互。

### 新 visual review

目标：验证主据点、室内、警戒区等地图是真实可见场景。

检查：

- 地面存在且建筑不悬空。
- trigger 不再是紫色圆盘。
- 建筑块和家具材质来自真实资源。
- 相机、灯光、比例符合手动 review 预期。

## 迁移阶段

### 阶段一：建立新运行时世界根

新增：

- `godot/scenes/world/world_runtime_root.tscn`
- `godot/scripts/world/runtime/world_runtime_root.gd`
- `map_scene_slot.gd`
- `interaction_controller.gd`

同时让 `WorldRoot` 使用 `WorldRuntimeRoot`，不再直接实例化 `WorldSceneRenderer`。

验收：

- 一个代表地图可以通过新 root 加载。
- 新 root 能同步 interaction metadata。
- 新 smoke 不调用 `WorldSceneRenderer`。

### 阶段二：地图 scene 内容补齐

补齐所有 map scene 必需节点：

- 地面。
- typed objects。
- picking Area3D / CollisionObject3D。
- door/container/trigger 的真实视觉和状态节点。

验收：

- scene validator 不允许缺地面或缺拾取体。
- 旧 fallback 删除后地图仍可见、可点击。

### 阶段三：ActorLayer 和 MarkerLayer 接管表现

新增：

- `ActorView3D` scene。
- `ActorLayer`。
- `WorldMarkerLayer`。

迁移：

- actor 创建、血条、AP 条、状态、任务、战斗反馈从 `WorldSceneRenderer` 移出。
- actor 移动由稳定 actor node 执行。

验收：

- actor view 在普通移动中不被重建。
- 相机可跟随 actor view。
- 战斗/状态标记跟随 actor view。

### 阶段四：CameraRig 和 LightRig 场景化

新增或迁移：

- `CameraRig` scene。
- `LightRig` scene。

迁移：

- 相机不再由 renderer 每次生成。
- 灯光不再由 renderer 每次生成。

验收：

- 地图切换后相机保持可控。
- 光照随 scene 或 runtime state 同步。

### 阶段五：删除 WorldSceneRenderer

完成调用点替换后：

- 删除 `world_scene_renderer.gd`。
- 删除或重写所有直接依赖它的 smoke。
- 删除旧 fallback helper。

验收：

- `rg "WorldSceneRenderer|render_world\\(" godot/scripts docs` 不再出现主路径依赖。
- 新 static、runtime、interaction、editor smoke 通过。

## 验证命令

静态验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly
```

新 runtime scene 验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Scene
```

新交互验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Interaction
```

地图视觉复核：

```powershell
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1
```

最终检查：

```powershell
git diff --check
```

## 实施判断

如果某张地图没有地面、某个 trigger 没有拾取体、某个 actor 没有正式 view，不再由 renderer 临时补一个东西让它“看起来能跑”。这些都应该变成内容或场景错误，并由 validator、editor review 或 smoke 暴露。

这条路线更激进，但更接近 Godot 原生开发：场景负责场景，节点负责自身表现，controller 负责同步状态，测试验证目标架构，而不是保护迁移期的大型临时代码。
