# WorldSceneRenderer Godot 原生拆分与重构方案

本文定义 `godot/scripts/world/world_scene_renderer.gd` 的拆分路线。目标不是把它再包装一层，而是把它从“单个巨型 RefCounted 装配器”重构为更符合 Godot 原生风格的场景化、节点化、信号化运行时世界系统。

当前 `WorldSceneRenderer` 同时负责地图场景加载、地面兜底、交互目标挂接、actor/corpse/prop 可视化、状态标记、相机、灯光和一些表现型 fallback。这个角色在迁移期能工作，但它已经同时扮演了多个 Godot 节点的职责，后续维护成本会持续上升。

## 当前问题

- 单文件过大，职责边界混杂。
- 运行时世界渲染仍以 `RefCounted` 方式组织，和 Godot 的 scene/node 组合风格不一致。
- 地图加载、对象表现、actor 表现、相机和 HUD 级标记彼此耦合。
- fallback 逻辑很多，说明真实场景节点还没有被清晰地拆到各自职责里。
- `WorldSceneRenderer` 既被 `WorldRoot` 使用，也被多个 smoke 直接调用，说明它承担了“核心运行时入口”的工作，但内部实现却不像一个稳定的入口节点。

## 目标

- 把世界渲染从单个大类拆成多个明确职责的 Godot 节点 / 控制器。
- 让运行时世界的主体变成一个可挂在场景树里的组合体，而不是一堆静态方法和 helper。
- 保持现有 world snapshot、map definition、interaction schema 和 smoke 兼容。
- 让地图视觉、actor 视觉、交互碰撞、相机和 overlay 可以独立演进。
- 继续保留 headless smoke 和 agent 可读性，不引入新的长期工具链依赖。

## 非目标

- 不改游戏规则、AI、寻路、战斗、背包、任务、对话逻辑。
- 不把地图系统改成 `GridMap`、`MeshLibrary` 或 ECS。
- 不重写地图数据 schema。
- 不一次性清空所有 fallback。
- 不把所有表现都塞回 `WorldActionPresenter`。

## 设计原则

- 用 scene/node 组合表达职责，不用一个巨型类硬拼全部流程。
- 每个节点只负责一类可视职责，并暴露清晰的 `sync_*` / `clear_*` / `snapshot()` 接口。
- 运行时状态由节点持有，编排由 root 节点持有，规则仍由 simulation 持有。
- 旧的 `WorldSceneRenderer` 先变薄，再被替换，最后删除。
- 同一层不要同时存在“数据解析者、场景装配者、视觉生成者、相机控制者、HUD 标记生成者”五种职责。

## 目标结构

建议把当前运行时世界组织成一个 Godot 场景根节点，类似：

```text
WorldRoot
  WorldSceneHost
    MapVisualHost
    GroundHost
    InteractionTargetHost
    ActorHost
    CorpseHost
    LightingHost
    CameraHost
    DebugOverlayHost
```

### WorldRoot

保留现有 `godot/scripts/world/world_root.gd` 作为 app 级世界入口，但它不再直接依赖一个巨型 `WorldSceneRenderer` 做全部事情。

职责：

- 持有 world container。
- 维护 world snapshot 的刷新入口。
- 调用子控制器同步世界。
- 记录渲染统计。

### WorldSceneHost

新增一个场景节点，作为所有 world 视觉节点的编排入口。

职责：

- 接收 world snapshot。
- 按阶段分发给各个子 host。
- 负责清理和重建的边界。
- 对外提供 `apply_world_snapshot()` / `clear_world()` / `snapshot()`。

### MapVisualHost

负责加载 `godot/scenes/maps/*.tscn` 或地图视觉子场景。

职责：

- 根据 `map_id` 加载地图 scene。
- 处理 scene 缺失时的 fallback。
- 绑定地图对象的交互元数据。
- 只管地图场景层，不管 actor、灯光、相机。

### GroundHost

负责地面和 ground picker。

职责：

- 如果地图 scene 已有地面，则不重复生成。
- 没有地面时才生成 fallback ground。
- 只做最小兜底，不承担地图几何表达。

### InteractionTargetHost

负责把地图对象、门、容器、pickup、trigger 绑定为可拾取、可交互的运行时目标。

职责：

- 扫描 scene 中的 `MapObjectNode`。
- 根据 object definition 绑定 interaction metadata。
- 生成碰撞代理和拾取代理。
- 管理门、容器等状态视觉的同步。

### ActorHost

负责 actor 运行时表现。

职责：

- 根据 actor snapshot 生成和更新 actor node。
- 挂载名字、血条、AP 条、状态效果图标、任务标记、战斗反馈。
- 与 `ActorViewController` 协作，保留 actor node 稳定性。

### CorpseHost

负责尸体表现。

职责：

- 生成尸体模型或 fallback mesh。
- 绑定尸体 meta。
- 与地图对象和 actor 表现分离。

### LightingHost

负责运行时灯光和基础环境光。

职责：

- 按世界状态生成或刷新灯光。
- 保留最少可视的世界气氛。
- 不参与地图结构和交互。

### CameraHost

负责运行时相机。

职责：

- 根据 focus position 或 actor node 设置 camera。
- 处理 viewport 尺寸、边距和跟随逻辑。
- 只做相机，不兼任地面、actor 或 world overlay。

### DebugOverlayHost

负责 debug overlay 和调试标记。

职责：

- 提供可切换的 debug 视图。
- 与 editor / smoke 保持一致。
- 不污染正式 world scene 的核心逻辑。

## 推荐拆分顺序

### 先抽纯函数和数据处理

先从 `WorldSceneRenderer` 中抽出不依赖节点生命周期的 helper：

- 颜色和材质构造。
- 位置和尺寸计算。
- 资源路径判定。
- 视觉 profile 选择。
- 统计和汇总函数。

这些内容可以进入一个更小的纯工具模块，或者保留在新 host 内作为私有 helper。

### 再抽地图和交互

优先拆出：

- `MapVisualHost`
- `GroundHost`
- `InteractionTargetHost`

这三块最直接对应地图 scene / 交互对象 / fallback 地面，也是当前 `WorldSceneRenderer` 最重的三段逻辑。

### 再拆 actor 和 corpse

下一步拆：

- `ActorHost`
- `CorpseHost`
- `ActorViewController` 的对接面

目标是让 actor node 稳定存在，表现更新走局部同步，而不是整棵 world 重绘。

### 最后拆相机、灯光和 debug

这些职责更独立，适合后移：

- `CameraHost`
- `LightingHost`
- `DebugOverlayHost`

## 接口草案

### WorldSceneHost

```gdscript
func apply_world_snapshot(world_snapshot: Dictionary, runtime_snapshot: Dictionary = {}, options: Dictionary = {}) -> Dictionary
func clear_world() -> void
func snapshot() -> Dictionary
```

### MapVisualHost

```gdscript
func sync_map_visuals(map_snapshot: Dictionary, options: Dictionary = {}) -> Dictionary
func clear_map_visuals() -> void
func map_visual_object_ids() -> Dictionary
```

### GroundHost

```gdscript
func sync_ground(map_snapshot: Dictionary) -> Dictionary
func clear_ground() -> void
```

### InteractionTargetHost

```gdscript
func sync_targets(map_snapshot: Dictionary, visual_object_ids: Dictionary = {}) -> Dictionary
func clear_targets() -> void
```

### ActorHost

```gdscript
func sync_actors(actors: Array) -> Dictionary
func clear_actors() -> void
```

### CorpseHost

```gdscript
func sync_corpses(corpses: Array) -> Dictionary
func clear_corpses() -> void
```

### CameraHost

```gdscript
func sync_camera(map_snapshot: Dictionary, focus_position: Vector3, viewport_size: Vector2) -> Dictionary
func clear_camera() -> void
```

## 迁移阶段

### 阶段一：职责盘点和薄封装

目标是把现有 `WorldSceneRenderer` 的大函数按职责划分，但还保留原类作为外壳。

做法：

- 给每类职责提取内部 helper。
- 把 `render_world()` 改成调度多个局部同步步骤。
- 补齐每一块的统计字段。

验收：

- `WorldSceneRenderer` 体积明显下降。
- `WorldRoot.apply_world_snapshot()` 行为不变。
- `scene_smoke` 仍然可跑。

### 阶段二：引入节点化 host

把地图、ground、targets、actors、corpses、camera、lighting 拆为独立节点脚本。

做法：

- 新增 `WorldSceneHost` 场景根。
- 把各 host 作为子节点挂进去。
- 由 root 统一注入 snapshot。

验收：

- host 节点可以单独 mock。
- 运行时 world 不再依赖一个类完成全部装配。
- 任何单个 host 坏掉时，其他 host 可独立维持。

### 阶段三：替换直接调用点

把 `WorldRoot`、`scene_smoke`、`map_preview_smoke` 等调用迁移到新 host 接口。

做法：

- 保留旧入口一段时间。
- 新接口先接管主要运行路径。
- 旧 `WorldSceneRenderer` 只保留兼容壳。

验收：

- 旧 smoke 全通过。
- 新 host 路径成为主入口。

### 阶段四：删除旧巨型类

当 host 结构稳定后，把 `WorldSceneRenderer` 缩成兼容层，最后删除。

验收：

- 不再有一个文件同时承担所有世界表现职责。
- 运行时世界行为与迁移前一致或更清晰。

## 需要保留的兼容点

- `GeneratedWorld` 根节点命名先保留，避免 smoke 和 debug 断掉。
- `load_map_visuals` 这类选项先保留。
- fallback 地面、fallback actor、fallback 交互体先不删。
- 现有 `scene_smoke` 断言先不改语义，只改实现路径。

## 风险

- host 过度拆分会导致接口碎片化。
- 过早删除 fallback 会让一些地图暂时全黑或缺交互。
- actor、camera、presentation 三者之间的跟随顺序如果改错，会影响移动和动作表现。

## 缓解方式

- 先拆职责，再拆数据流。
- 保持一个总编排入口。
- 每次只迁一类 host，并跑对应 smoke。
- 所有新 host 先支持 snapshot 输入，再考虑更复杂的 signal 驱动。

## 测试计划

- `tools/agent/test-godot-static.ps1 -Scenario CheckOnly`
- `tools/agent/test-godot-game.ps1 -Scenario Scene`
- `tools/agent/test-godot-game.ps1 -Scenario Interaction`
- `tools/agent/review-godot-map-visual.ps1`
- `tools/agent/test-godot-editor.ps1`
- `git diff --check`

## 实施原则

- 只把职责拆到 Godot 风格更清楚的节点里，不引入新框架。
- 优先保留 scene/node 可视编排，而不是把它倒回纯脚本调度。
- 让每个 host 都能在编辑器和 headless 下单独验证。
- 迁移期间以稳定性优先，重构目标是“更像 Godot”，不是“更多抽象”。
