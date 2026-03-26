# Bevy Debug Viewer 遮挡半透方案

## 文档定位

本文用于落地 `rust/apps/bevy_debug_viewer` 的“遮挡半透”能力：当当前观察目标玩家被静态场景物体挡住时，让挡在相机与玩家之间的静态盒体立即切换为半透明；当遮挡解除时立即恢复不透明。

这项改动属于当前迁移路线中的 `Bevy Debug Viewer` 可视化增强，主要服务于：

- 提升 `bevy_debug_viewer` 在调试楼层、多障碍和室内地图时的可读性
- 继续把表现层调试能力建设在 `Bevy` 侧，而不是回流到 `Godot`
- 保持改动只落在 viewer 内部，不新增跨 crate 共享接口，也不改变 `game_core / game_data / game_protocol` 的职责边界

它不承担核心规则，不改变运行时模拟结果，只是 viewer 内部的显示策略优化，因此符合“逻辑、表现、编辑逐步拆开”的方向，也不会增加新的跨端耦合。

## 目标与固定规则

本方案默认规则已经固定，不在第一版内开放策略分叉：

- 遮挡目标：优先 `selected_actor`，且该 actor 必须是 `ActorSide::Player`
- 回退规则：若当前未选中玩家，则回退到 `current_level` 上第一个 `ActorSide::Player`
- 透明变化：立即切换，不做渐变、不做插值
- 生效范围：仅对当前 `current_level` 的静态世界物体生效
- 排除对象：不影响 actor、UI、grid overlay、路径线、标签、HUD
- 代码边界：不新增跨 crate 公共接口，改动集中在 viewer 内部，主要位于 `render.rs`、`geometry.rs`、`state.rs`

第一版的判断标准不是“美术上是否好看”，而是“调试时能否稳定看见当前玩家，且实现足够可维护、可测试、可回退”。

## 现状分析

当前 `bevy_debug_viewer` 的静态世界由 [`render.rs`](G:\Projects\cdc_survival_game\rust\apps\bevy_debug_viewer\src\render.rs) 中的 `rebuild_static_world` 负责一次性重建，重建结果只在 `StaticWorldVisualState` 中保存 `Vec<Entity>`。这意味着：

- viewer 知道哪些静态实体被生成了，但不知道它们各自对应什么类型的世界对象
- viewer 没有保存这些实体的材质句柄、原始颜色、透明状态和空间包围盒
- 一旦需要“按条件局部切换透明度”，现有数据结构无法支持按帧增量更新

同时，当前相机与标签系统已经具备本方案所需的两个关键基础：

- `update_camera` 能稳定给出当前相机 `Transform`
- `actor_label_world_position` 已经定义了“角色头顶位置”的 viewer 语义

因此，第一版不需要引入复杂渲染特效或后处理，只需要在现有静态盒体绘制链路中补齐可追踪元数据，并在每帧根据“相机到角色头顶”的遮挡关系更新材质透明度。

## 非目标

以下能力不在本方案范围内：

- 不处理 actor 挡 actor
- 不处理半透明渐变、淡入淡出或脉冲效果
- 不做描边、高亮、X-Ray 或 stencil 类效果
- 不扩展到“所有友方单位”或“所有玩家单位同时可见”
- 不处理当前楼层以外的物体
- 不改动 `game_core` 中的视线规则，也不把遮挡判断下沉到共享规则层

这是一个纯 viewer 表现问题，保持在 viewer 内部解决最符合当前架构边界。

## 方案总览

整体方案拆成三件事：

1. 把“静态世界实体列表”升级为“带空间信息和材质信息的 occluder 记录”
2. 每帧解析当前应被观察的玩家目标，并计算哪些静态盒体挡住了该目标
3. 对命中的 occluder 直接切换材质 `alpha` 和 `alpha_mode`，未命中的立即恢复

对应结果是：

- 静态世界仍然按现有逻辑重建
- actor、UI、gizmo overlay 保持完全不变
- 半透只发生在静态盒体上，且是可逆、即时、局部的

## 遮挡对象范围

### 纳入半透判定的对象

只把真正可能挡住视线的“静态体积盒体”纳入 occluder 集合：

- `map_cells` 中实际绘制出立方体体积的阻挡地形
- `static_obstacles` 生成的障碍盒体
- `map_objects` 生成的建筑、拾取物、交互物、刷怪点盒体

这些对象已经在 [`render.rs`](G:\Projects\cdc_survival_game\rust\apps\bevy_debug_viewer\src\render.rs) 中由 `spawn_box` 统一生成，适合继续沿用现有 box mesh 表现。

### 不纳入半透判定的对象

以下对象保持现状，不参与遮挡半透：

- 地面 tile
- actor 胶囊体
- hover/current-turn/path 等 gizmo overlay
- actor label、interaction menu、dialogue panel、HUD

这样可以避免两个常见问题：

- 整张地图地面频繁进入半透明，导致画面发灰
- 调试辅助元素也被一起淡化，反而降低可读性

## 目标角色解析规则

遮挡半透的目标角色固定为“当前应被观察的玩家角色”，解析顺序如下：

1. 若 `viewer_state.selected_actor` 对应 actor 存在，且 `side == ActorSide::Player`，使用它
2. 否则，从当前 `current_level` 的 actor 列表中找到第一个 `ActorSide::Player`
3. 若仍找不到，则本帧不做遮挡半透，并清空所有已半透对象

这里显式要求“必须是玩家”，是为了避免用户点中敌人或中立单位后，viewer 把半透逻辑错误地转移到非玩家目标上。

目标点坐标使用 `actor_label_world_position` 对齐的角色头顶位置，而不是角色中心点。原因有两个：

- 当前 viewer 的“是否看得见一个角色”更接近“是否能看见其上半身和头顶”
- 标签系统已经在使用这个位置，沿用同一语义能降低实现分歧

## 几何判定方案

### 判定输入

每帧获取：

- 相机世界坐标：来自 `ViewerCamera` 的 `Transform.translation`
- 目标点世界坐标：目标玩家的 `actor_label_world_position`
- 候选 occluder 的 world-space AABB

### 判定方式

对每个候选 occluder 执行“相机到角色头顶的线段 vs AABB 相交测试”。

只有满足以下条件时才视为遮挡：

- occluder 与线段相交
- 命中位置位于相机与目标点之间
- occluder 位于 `current_level`

允许多个 occluder 同时命中；命中的全部切为半透明。

### 为什么选线段 vs AABB

第一版固定使用这个算法，是因为它有几个直接优势：

- 与当前 viewer 的盒体渲染方式天然匹配
- 不需要引入 Bevy picking、物理世界或额外加速结构
- 逻辑简单，单元测试容易补
- 对当前 debug viewer 的对象规模已经足够

相比“按 grid 离散格子射线采样”或“按屏幕空间投影遮罩”：

- 更贴近实际渲染体积
- 不依赖后处理
- 更容易直接复用静态盒体生成时的尺寸和位姿

## 数据结构设计

### 现有问题

当前 `StaticWorldVisualState` 只保存：

```rust
pub(crate) struct StaticWorldVisualState {
    key: Option<StaticWorldVisualKey>,
    entities: Vec<Entity>,
}
```

这不足以支持“只更新候选 occluder 的透明状态”。

### 新的静态世界可视状态

建议把静态世界记录拆成“全部静态实体”和“可半透 occluder”两个层次：

```rust
pub(crate) struct StaticWorldVisualState {
    key: Option<StaticWorldVisualKey>,
    entities: Vec<Entity>,
    occluders: Vec<StaticWorldOccluderVisual>,
}
```

其中 `StaticWorldOccluderVisual` 至少包含：

- `entity: Entity`
- `material: Handle<StandardMaterial>`
- `base_color: Color`
- `base_alpha: f32`
- `alpha_mode_opaque: AlphaMode`
- `aabb_center: Vec3`
- `aabb_half_extents: Vec3`
- `kind: StaticWorldOccluderKind`
- `currently_faded: bool`

建议补一个轻量分类枚举：

```rust
enum StaticWorldOccluderKind {
    BlockingCell,
    SightCell,
    StaticObstacle,
    MapObject(game_data::MapObjectKind),
}
```

这个分类第一版主要用于调试和未来扩展，不要求立刻做差异化透明策略，但保留后续按类别细分透明度的余地。

### floor tile 与 occluder 分离

静态 world 仍然统一由 `rebuild_static_world` 重建，但记录时要分开：

- floor tile 继续只加入 `entities`
- 只有可能遮挡视线的盒体加入 `occluders`

这样后续每帧只扫描 `occluders`，而不用把所有静态实体都拿来做遮挡判定。

## 材质切换策略

### 固定策略

遮挡时：

- 将材质 `alpha_mode` 切到 `AlphaMode::Blend`
- 将 `base_color.alpha` 直接改为固定半透明值

解除遮挡时：

- 恢复原始 `base_color`
- 恢复 `alpha_mode = AlphaMode::Opaque`

第一版统一使用单一目标透明度：

- 推荐 `target_alpha = 0.28`

### 为什么直接改材质

这是当前 viewer 最小、最稳的实现方式：

- 不需要更换 mesh
- 不需要重建实体
- 不需要引入额外 shader
- 与“立即切换、不做渐变”的产品规则完全一致

### 材质共享注意事项

要保证每个 occluder 使用的 `StandardMaterial` 句柄可被安全单独修改。当前 `spawn_box` 已经为每个盒体 `materials.add(StandardMaterial { ... })`，天然满足“单实体独立材质”的要求，因此不需要额外拆分共享材质池。

## 系统接入与执行顺序

### 新增系统

建议新增独立系统：

- `update_occluding_world_visuals`

职责是：

- 解析当前玩家目标
- 读取当前相机位置
- 计算当前命中的 occluder
- 增量更新 occluder 材质透明度

### 推荐调度顺序

放在相机更新之后、标签同步之前：

1. `update_camera`
2. `update_occluding_world_visuals`
3. `sync_actor_labels`
4. `update_hud / UI / draw_world`

原因：

- 遮挡判定依赖当前帧相机位置，必须在 `update_camera` 之后
- 标签显示通常是“玩家可见性”的直接反馈之一，半透更新早于标签同步，调试时更容易观察一致性
- `draw_world` 仍负责世界构建与 gizmo 绘制；透明度更新则专注于材质状态变化，职责更清晰

### 与静态世界重建的关系

静态世界仍沿用现有重建触发条件：

- `map_id`
- `current_level`
- `topology_version`

当这些值变化时：

- 先销毁旧静态实体
- 重建 floor 和 occluder
- 重置所有 occluder 为不透明状态

重建后再由 `update_occluding_world_visuals` 在后续帧重新判断是否需要半透。

## 代码落点建议

### `render.rs`

主要改动集中在：

- 扩展 `StaticWorldVisualState`
- 在 `rebuild_static_world` 中把 occluder 元数据同步构造出来
- 新增 `update_occluding_world_visuals`
- 新增用于生成 occluder 记录的辅助函数

同时建议把 `spawn_box` 拆成更适合记录材质与包围盒的返回形式，例如返回：

- `Entity`
- `Handle<StandardMaterial>`

或返回一个小结构体，避免 `rebuild_static_world` 里重复手工回填元数据。

### `geometry.rs`

建议新增以下几类几何辅助：

- 当前遮挡目标玩家解析函数
- world-space AABB 构造辅助
- 线段与 AABB 相交测试
- 目标前后关系判断辅助

推荐函数方向：

```rust
pub(crate) fn resolve_occlusion_target(...)
pub(crate) fn aabb_from_center_half_extents(...)
pub(crate) fn segment_intersects_aabb(...)
pub(crate) fn occluder_blocks_target(...)
```

这样 `render.rs` 可以只负责编排，不把几何细节堆进渲染文件。

### `state.rs`

`ViewerState` 不需要新增面向用户的复杂开关；第一版不建议把这个功能做成可切换配置项。

`state.rs` 可能只需要承载：

- 若干新的 viewer 内部状态结构定义

如果这些结构只在 `render.rs` 内使用，也可以继续保持在 `render.rs` 私有作用域，避免把状态定义过度上提。

## 实施步骤

建议按下面的小步顺序落地，便于随时回退：

1. 扩展 `StaticWorldVisualState`，让静态世界重建后能拿到 occluder 记录
2. 给 `rebuild_static_world` 中的三类遮挡体补齐 `AABB + material + base_color` 元数据
3. 在 `geometry.rs` 增加目标解析和线段/AABB 判定函数，并先补单元测试
4. 新增 `update_occluding_world_visuals`，只做“命中即半透、未命中即恢复”
5. 把系统插入 `app.rs` 的 `Update` 调度链，放在 `update_camera` 之后
6. 最后做 viewer smoke test，确认切层、改选中目标、多障碍同时遮挡等行为都符合预期

这个顺序符合当前仓库的渐进迁移原则：

- 是小步改动
- 不改变核心规则
- 不推翻现有 viewer 结构
- 失败时可直接回退到“无半透”的旧表现

## 验证方案

### 几何单测

建议补在 [`geometry.rs`](G:\Projects\cdc_survival_game\rust\apps\bevy_debug_viewer\src\geometry.rs)：

- 线段与 AABB 相交时返回命中
- 线段不接触 AABB 时返回未命中
- occluder 在 actor 前方时判定为遮挡
- occluder 在 actor 后方时不判定为遮挡
- 当前没有可用玩家目标时，不返回遮挡对象
- `selected_actor` 不是玩家时，会回退到当前层第一个玩家

### viewer 层单测

建议补在 [`render.rs`](G:\Projects\cdc_survival_game\rust\apps\bevy_debug_viewer\src\render.rs) 或相邻测试模块：

- 静态 world 重建后，occluder 元数据只包含非地面遮挡体
- `map_cells / static_obstacles / map_objects` 都能被正确登记为 occluder
- floor tile 不进入 occluder 列表
- 新重建的 occluder 默认不是半透状态

### 手动 smoke test

最小手动验证场景：

- 建筑或障碍挡住玩家时，挡住的盒体立即半透
- 玩家走出遮挡后，物体立即恢复不透明
- 多个物体同时挡住时，多个盒体都会半透
- 切层后只处理当前层 occluder
- 没有玩家目标或玩家不在当前层时，所有静态物体保持不透明
- 选中敌人或中立角色时，会自动回退到当前层玩家目标，而不是围绕敌人做半透

### 建议验证命令

优先做 viewer 局部验证：

```powershell
cargo fmt --check -p bevy_debug_viewer
cargo check -p bevy_debug_viewer
cargo test -p bevy_debug_viewer
```

如果 workspace 其他 crate 存在已知编译问题，应至少保证 `bevy_debug_viewer` 本 crate 的 check / test 可单独通过。

## 风险与边界

### 性能风险

第一版按帧遍历当前楼层全部 occluder 做线段/AABB 判定。在 debug viewer 当前规模下这是可以接受的，但若后续某些地图静态盒体数量明显增大，可能需要：

- 先做粗筛，例如只判断包围盒中心到线段的投影区间
- 或者按楼层进一步维护轻量空间索引

第一版先不引入额外复杂度。

### 透明排序风险

`AlphaMode::Blend` 在 3D 渲染中天然存在透明排序问题。但本 viewer 的 occluder 都是简单盒体，且只是调试用途，第一版可接受少量排序伪影。若后续出现明显可用性问题，再考虑：

- 改用 `AlphaMode::Premultiplied`
- 或进一步限制哪些类型允许进入半透

### 目标切换抖动风险

如果玩家频繁切换层或 `selected_actor` 指向非玩家，目标解析会发生回退。为了保持行为稳定，本方案明确规定：

- 永远优先“选中的玩家”
- 否则回退到“当前层第一个玩家”
- 两者都不存在时，全部恢复不透明

这样不会留下“上一帧半透残留”。

## 为什么不下沉到共享 Rust 层

尽管项目整体优先建设共享 `Rust` 基础层，但本功能不适合现在就迁移到 `game_core` 或 `game_bevy`：

- 它依赖 viewer 的相机位置和 3D 盒体表现
- 它使用的是 viewer 特有的“角色头顶显示点”语义
- 它不属于稳定复用的核心规则，而是纯调试显示策略

因此保持在 `bevy_debug_viewer` 内部实现，反而更符合当前架构边界，不会制造新的共享层污染。

## 后续最自然的下一步

如果第一版落地稳定，后续最自然的迭代顺序是：

1. 先把 occluder 判定和透明切换实现完成
2. 再视使用体验决定是否按 `MapObjectKind` 细分透明度
3. 若地图规模继续增长，再补轻量空间筛选
4. 若 debug viewer 后续出现更强的观测需求，再评估“描边 + 半透”组合方案

不建议一开始就把渐变、后处理、描边、所有单位可见性等需求捆在一起，否则会让这个本来很清晰的小功能重新变成一次性大改。

## 结论

本方案选择用“相机到玩家头顶线段 vs 静态盒体 AABB”的方式，在 `bevy_debug_viewer` 内部实现局部、即时、可回退的遮挡半透。

它的优点是：

- 只改 viewer 内部，不引入跨端耦合
- 不侵入核心逻辑与共享协议层
- 与现有静态盒体渲染实现天然兼容
- 可通过局部单测和 smoke test 明确验证

这是一项典型的“小步、可验证、可回退”的 viewer 表现增强，符合当前仓库的实施优先级，也不会增加未来三端分离迁移的成本。
