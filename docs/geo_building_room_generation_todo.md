# 使用 `geo` 生成建筑和房间的开发 TODO

本文档将“使用 `geo` 在共享 Rust 层生成建筑、房间、墙体几何，并由 `bevy_debug_viewer` 消费结果”收口成可执行的分阶段 backlog。

该项改动属于三端分离中的“继续强化 `Rust / Bevy` 权威实现”阶段，目标是把建筑几何权威链路从当前 `cell-first` 方案迁移到 `Rust game_core` 的 `polygon-first` 方案，同时保留一段时间的 grid 兼容输出，避免一次性打断现有运行时与 viewer。

---

## 1. 当前仓库基线

以下状态已经按当前代码核对，可作为本 TODO 的起点：

- [x] `rust/crates/game_core/src/building.rs` 仍以 `shape_cells` 为主要输入，输出 `rooms.cells`、`wall_cells`、`walkable_cells`
- [x] 当前房间生成仍是基于 cell 的 rectilinear BSP / 切分流程
- [x] `rust/crates/game_data/src/map.rs` 的 `MapBuildingLayoutSpec` 仍只有 `shape_cells`、房间参数、楼梯、`visual_outline`
- [x] `rust/crates/game_core/Cargo.toml` 尚未引入 `geo`
- [x] `rust/crates/game_core/src/lib.rs` 尚未导出独立的建筑几何模块
- [x] 仓库中尚不存在 `building_geometry.rs` / `room_layout.rs`
- [x] `rust/apps/bevy_debug_viewer/src/render.rs` 仍通过 `merge_cells_into_rects(...)` 与 `collect_story_wall_segments(...)` 生成建筑可视化
- [x] 当前 viewer 主渲染仍是“floor rect + wall segment box”路径，而不是 polygon triangulation / extrusion mesh

这意味着本任务不是“补一点 viewer 表现”，而是一次明确的共享 Rust 权威链路迁移。

---

## 2. 目标收口

完成后应满足以下结果：

- [ ] 建筑外轮廓、房间、墙体、门洞的权威数据生成位于 `rust/crates/game_core`
- [ ] `game_data` 提供建筑 polygon footprint 与几何参数的权威 schema
- [ ] `GeneratedBuildingStory` 同时承载 polygon 权威结果与 grid 兼容输出
- [ ] `bevy_debug_viewer` 只消费几何结果生成 mesh，不再以 cell wall segment 作为主渲染来源
- [ ] 现有 grid world、阻挡、寻路暂时继续通过回采样结果兼容
- [ ] 不在 Godot 侧新增同类功能实现

---

## 3. 第一版边界与明确决策

为避免范围失控，第一版直接固定以下边界：

- 第一版权威几何坐标统一使用建筑局部 2D 平面坐标 `(x, z)`，标量类型使用 `f64`；楼层仍由 `level: i32` 单独表示
- 第一版 `footprint` 仅接受“单个连通、无自交、无 hole”的简单 polygon
- 如果 `shape_cells` union 得到多连通结果或带 hole 结果，第一版直接返回验证错误，不隐式修补
- 第一版允许两种输入来源：
  - 显式 polygon footprint
  - 旧 `shape_cells` 自动走 cell-union 兼容路径
- 第一版房间切分仍保持轴对齐思路；即“polygon-first 输入 + 轴对齐切分规则”，不引入任意斜切房间分割
- 第一版门洞只支持 wall-aligned opening；不做任意角度门洞
- 第一版 `geo-clipper` 只作为兜底预留，不进入主路径
- 当前 `visual_outline.diagonal_edges` 继续视为 viewer/表现层辅助数据，不把它提升为第一版几何权威输入

生成失败时的降级策略也直接固定：

- `footprint` 非法时：返回显式验证错误，不做沉默 fallback
- 房间切分失败时：退化为“单房间 = 建筑可行走内部区域”
- 墙 buffer / opening difference 失败时：返回显式几何错误，不切回旧 Godot 或 viewer 本地生成逻辑

---

## 4. 权威链路目标形态

目标权威链路应为：

`MapBuildingLayoutSpec` -> `game_core::building_geometry` -> `game_core::room_layout` -> `GeneratedBuildingStory` polygon 权威结果 -> polygon/grid 双输出 -> `bevy_debug_viewer` mesh 消费

需要明确的长期职责：

- `game_data`
  - 建筑 footprint schema
  - 几何参数 schema
  - 参数默认值与输入校验
- `game_core`
  - footprint 生成与校验
  - 房间 polygon 布局
  - 墙中心线、墙 polygon、门洞、楼梯裁切
  - polygon -> grid 回采样
  - snapshot/debug state 透传
- `bevy_debug_viewer`
  - triangulation / extrusion mesh
  - polygon / wall / opening debug 可视化
  - 新旧路径切换与对比

---

## 5. 模块与数据结构落点

### 5.1 `game_core` 新模块

- [ ] 新增 `rust/crates/game_core/src/building_geometry.rs`
- [ ] 新增 `rust/crates/game_core/src/room_layout.rs`
- [ ] 在 `rust/crates/game_core/src/lib.rs` 导出上述模块

### 5.2 共享几何结构

第一版需要至少定义以下引擎无关结构：

- [ ] `GeometryPoint2`
- [ ] `GeometrySegment2`
- [ ] `GeometryPolygon2`
- [ ] `GeometryMultiPolygon2`
- [ ] `BuildingFootprint2d`
- [ ] `GeneratedRoomPolygon`
- [ ] `GeneratedWallStroke`
- [ ] `GeneratedDoorOpening`
- [ ] `GeneratedWallPolygons`
- [ ] `GeneratedWalkablePolygons`
- [ ] `GeneratedBuildingGeometryDebugState`
- [ ] `BuildingGeometryValidationError`

要求：

- [ ] 所有结构保持 `serde` 可序列化
- [ ] 所有结构保持引擎无关，不引入 Bevy/Godot 类型
- [ ] `geo` 类型只作为内部算法实现细节；snapshot/debug state 暴露自己的稳定结构

---

## 6. `game_data` schema 扩展

需要在 `rust/crates/game_data/src/map.rs` 补齐建筑几何输入与参数配置。

### 6.1 footprint 输入

- [ ] 增加显式 polygon footprint 结构
- [ ] 支持 outer ring 顶点列表
- [ ] 第一版显式禁止 hole
- [ ] 与旧 `shape_cells` 兼容共存
- [ ] 明确优先级：显式 polygon 优先，缺失时再走 `shape_cells`

建议的 schema 方向：

- [ ] 新增 `MapBuildingFootprintPolygonSpec`
- [ ] 新增 polygon ring 顶点结构，优先复用或扩展 `RelativeGridVertex`

### 6.2 几何参数

- [ ] 增加 `wall_thickness`
- [ ] 增加 `wall_height`
- [ ] 增加 `door_width`
- [ ] 增加 `min_room_area`
- [ ] 增加 `min_room_width`
- [ ] 增加 `min_room_height`
- [ ] 保留 `target_room_count`
- [ ] 保留 `max_room_size`

### 6.3 校验

- [ ] 为新增字段补默认值
- [ ] 为非法 polygon 补验证错误类型
- [ ] 为非法几何参数补验证错误类型
- [ ] 明确 polygon 顶点方向与闭合规则
- [ ] 明确 polygon 坐标是否允许负值以及相对锚点的约束

---

## 7. 里程碑 M1：引入 `geo` 与共享几何基础

### 7.1 依赖与导出

- [ ] 在 `rust/crates/game_core/Cargo.toml` 引入 `geo`
- [ ] 预留 `geo-clipper` feature flag，但不接入主路径
- [ ] 确认新增 geometry 结构可进入 snapshot/debug state 的 `serde` 链路

### 7.2 内部转换工具

- [ ] 增加共享结构到 `geo::Polygon` / `geo::MultiPolygon` / `geo::LineString` 的转换 helper
- [ ] 增加 `geo` 结果回转共享结构的 helper
- [ ] 对坐标精度、方向、闭合做统一归一化入口

### 7.3 M1 验收

- [ ] `game_core` 可以编译通过并导出空实现或最小实现的 geometry 模块
- [ ] snapshot/debug state 可以序列化新增 geometry 结构
- [ ] 尚未接 viewer 也不影响当前主链路

---

## 8. 里程碑 M2：footprint 权威化

### 8.1 从 `shape_cells` 到 polygon

- [ ] 在 `rust/crates/game_core/src/building.rs` 中把 `shape_cells` 转为 cell square polygons
- [ ] 对所有 cell squares 做 union
- [ ] 输出单个 `footprint_polygon`
- [ ] 对面积做校验
- [ ] 对方向做归一化
- [ ] 对有效性做检查

### 8.2 明确异常策略

- [ ] union 结果为空时返回错误
- [ ] union 结果多连通时返回错误
- [ ] union 结果带 hole 时返回错误
- [ ] 显式 polygon 输入非法时返回错误

### 8.3 M2 验收

- [ ] 没有显式 polygon 的旧建筑，可自动走 cell-union 兼容路径
- [ ] 合法 `shape_cells` 能稳定得到单一 `footprint_polygon`
- [ ] 非法输入能得到稳定错误，而不是 silently fallback

---

## 9. 里程碑 M3：房间布局切到 polygon-first

### 9.1 新的布局入口

- [ ] 在 `rust/crates/game_core/src/room_layout.rs` 实现 polygon-first 房间布局
- [ ] 输入改为 `footprint_polygon`
- [ ] 输出改为 `room_polygons`

### 9.2 规则保持

- [ ] 保留最小房间面积限制
- [ ] 保留最小房间宽度限制
- [ ] 保留最小房间高度限制
- [ ] 保留小建筑不切分规则
- [ ] 保留目标房间数上限
- [ ] 保留最大房间尺寸约束

### 9.3 结果正确性

- [ ] 每次切分后做 polygon 有效性检查
- [ ] 保证房间 polygon 不重叠
- [ ] 保证房间 polygon 不超出 footprint
- [ ] 保证房间 union 覆盖建筑内部
- [ ] 为房间结果生成稳定排序，避免 snapshot 抖动

### 9.4 降级策略

- [ ] 切分失败时退化为单房间结果
- [ ] 退化结果仍需保持 polygon 有效

### 9.5 M3 验收

- [ ] `GeneratedBuildingStory` 已能拿到权威 `room_polygons`
- [ ] 旧规则语义仍在 Rust 侧可验证
- [ ] snapshot 相同 seed 下房间排序稳定

---

## 10. 里程碑 M4：墙、门洞、楼梯几何

### 10.1 房间与边界关系

- [ ] 从 `room_polygons` 计算共享边
- [ ] 区分外墙边与内墙边
- [ ] 从共享边构造内墙中心线
- [ ] 从外轮廓边构造外墙中心线
- [ ] 为每条墙中心线保留所属房间或边界信息

### 10.2 墙体 polygon

- [ ] 从 `wall_strokes` 组装 `LineString` / `MultiLineString`
- [ ] 使用 `geo` buffer 生成墙体 2D 轮廓
- [ ] 配置 join style
- [ ] 配置 cap style
- [ ] 对 buffer 结果做 union / dissolve
- [ ] 对结果做有效性检查
- [ ] 处理墙厚导致的自交或碎片
- [ ] 预留切换到 `geo-clipper` 的接口层

### 10.3 门洞 / 开口

- [ ] 将 interior/exterior door 从 cell 表达迁移为 wall-aligned opening
- [ ] 把 opening 表达为 segment 与 polygon 两种视图
- [ ] 使用 opening polygon 对 `wall_polygons` 做 difference
- [ ] 保证门洞宽度可配置
- [ ] 保证门洞方向和所属墙一致
- [ ] 处理门靠近拐角的裁切约束
- [ ] 处理多个门洞落在同一面墙上的情况

### 10.4 楼梯与其他结构

- [ ] 把楼梯占用区域转成 polygon
- [ ] 从房间 walkable polygon 中裁掉楼梯实体区域
- [ ] 第一版若楼梯穿墙，返回显式错误或明确不支持，不做隐式修复
- [ ] 为后续平台、栏杆、边界预留结构

### 10.5 M4 验收

- [ ] `GeneratedBuildingStory` 已能拿到权威 `wall_strokes`
- [ ] `GeneratedBuildingStory` 已能拿到权威 `wall_polygons`
- [ ] `GeneratedBuildingStory` 已能拿到权威 `door_openings`
- [ ] 门洞从墙体中扣除后的 polygon 结果稳定可序列化

---

## 11. 里程碑 M5：从 polygon 回采样为 grid 兼容输出

本阶段是兼容层，不是新的权威源。

### 11.1 兼容输出

- [ ] 从 `wall_polygons` 回采样生成 `wall_cells`
- [ ] 从 walkable polygon 回采样生成 `walkable_cells`
- [ ] 从 opening 结果回采样生成 interior/exterior door cells
- [ ] 从 `room_polygons` 回采样生成 `rooms.cells`

### 11.2 采样规则

需要在代码中固定并写入注释/测试的规则：

- [ ] `walkable_cells` 采用确定性的 polygon 采样规则
- [ ] `wall_cells` 采用确定性的 wall polygon 采样规则
- [ ] 对边界命中、浮点误差、共边情况做一致归一化
- [ ] 采样结果与原建筑 anchor / footprint 保持对齐

建议第一版采样方向：

- [ ] `walkable_cells` 以 cell center 命中作为主要规则
- [ ] `wall_cells` 使用“cell square 与 wall polygon 的交面积阈值”规则，避免薄墙中心点漏采样

### 11.3 M5 验收

- [ ] 现有 grid world、阻挡与寻路仍可消费 `wall_cells / walkable_cells`
- [ ] `rooms.cells`、`wall_cells`、`walkable_cells` 已明确是 derived compatibility output
- [ ] 不再把这些 grid 结果视为建筑权威源

---

## 12. 里程碑 M6：`GeneratedBuildingStory` / Snapshot 扩展

### 12.1 结构扩展

- [ ] 在 `rust/crates/game_core/src/building.rs` 扩展 `GeneratedBuildingStory`
- [ ] 增加 `footprint_polygon`
- [ ] 增加 `room_polygons`
- [ ] 增加 `wall_strokes`
- [ ] 增加 `wall_polygons`
- [ ] 增加 `door_openings`
- [ ] 视需要增加 `walkable_polygons`

### 12.2 兼容保留

- [ ] 保留现有 `wall_cells`
- [ ] 保留现有 `walkable_cells`
- [ ] 保留现有 `rooms.cells`

### 12.3 透传

- [ ] 在 `rust/crates/game_core/src/simulation.rs` 与 snapshot 结构中透传新增几何数据
- [ ] 确认 debug state 可以稳定查看 polygon 结果

### 12.4 M6 验收

- [ ] runtime snapshot 中可看到建筑 polygon 权威结果
- [ ] `bevy_debug_viewer` 可以仅依赖 snapshot/debug state 消费几何

---

## 13. 里程碑 M7：`bevy_debug_viewer` 改造成真正消费 geometry

### 13.1 Mesh 主路径

- [ ] 在 `rust/apps/bevy_debug_viewer/src/render.rs` 新增 polygon triangulation -> Bevy mesh 转换
- [ ] 增加墙体侧面 mesh 生成
- [ ] 增加墙体顶面 mesh 生成
- [ ] 视需要增加底面 mesh 生成
- [ ] 增加 room floor polygon mesh 渲染
- [ ] 增加门洞裁切后的墙 mesh 渲染

### 13.2 兼容与切换

- [ ] 保留旧 `wall segment -> box` 逻辑作为临时 fallback
- [ ] 增加开关对比“旧 cell path / 新 polygon path”
- [ ] 清理“墙体依赖 occluder fade 才能看见”的逻辑耦合
- [ ] 调整墙体材质，让顶面和侧面更易区分
- [ ] 调整墙 mesh 的 occluder 策略，避免再次被错误淡化

### 13.3 调试可视化

- [ ] 增加 footprint polygon 线框显示
- [ ] 增加 room polygon 线框显示
- [ ] 增加 wall stroke 中心线显示
- [ ] 增加 door opening segment/polygon 调试显示
- [ ] 增加 triangulation 调试显示
- [ ] 增加“cell 视图 / polygon 视图 / mesh 视图”切换

### 13.4 M7 验收

- [ ] viewer 的建筑主渲染已不依赖 `collect_story_wall_segments(...)`
- [ ] viewer 可以直接消费 `GeneratedBuildingStory` 中的 polygon 权威结果
- [ ] fallback 仅作为临时对照路径，不再是默认主路径

---

## 14. 里程碑 M8：旧实现退役与兼容收口

- [ ] 明确 `wall_cells` 由 polygon 回采样得到
- [ ] 明确 `rooms.cells` 由 `room_polygons` 回采样得到
- [ ] 清理 viewer 中依赖 `collect_story_wall_segments(...)` 的主路径
- [ ] 清理“一段墙一个 box”的主渲染逻辑
- [ ] 清理与新方案冲突的旧测试
- [ ] 更新文档，明确“建筑和房间几何权威在 Rust `game_core`，viewer 只负责消费”

完成本阶段后，旧 cell-first 路径才可以开始真正退役。

---

## 15. 测试与验证清单

### 15.1 `game_core` / `game_data` 单测

- [ ] footprint union 单元测试
- [ ] polygon 有效性单元测试
- [ ] 非法 polygon 输入单元测试
- [ ] 小建筑不切分单元测试
- [ ] 最小房间面积限制单元测试
- [ ] 最小房间宽高限制单元测试
- [ ] 房间不重叠单元测试
- [ ] 房间覆盖率单元测试
- [ ] 内外墙提取单元测试
- [ ] door opening 裁切单元测试
- [ ] polygon -> grid 回采样单元测试

### 15.2 墙连接回归测试

- [ ] 90 度连接测试
- [ ] T 字连接测试
- [ ] 十字连接测试
- [ ] 复杂 footprint 回归测试

说明：

- 斜角连接测试不作为第一版强制门槛
- 若后续允许非轴对齐 footprint/墙体，再把斜角连接升级为强制回归项

### 15.3 Viewer 测试

- [ ] `bevy_debug_viewer` mesh 非空测试
- [ ] AABB 基本正确测试
- [ ] triangulation / topology 基本正确测试
- [ ] snapshot 几何透传测试

### 15.4 手动验证

- [ ] 启动 `bevy_debug_viewer` 检查墙体立面、拐角、门洞
- [ ] 验证地图阻挡和寻路没有因 polygon 回采样回归
- [ ] 验证不同建筑尺寸、房间数、seed 下结果稳定

---

## 16. 数据迁移与样例

- [ ] 调整现有测试建筑样例，使其同时覆盖 cell-union 路径与显式 polygon 路径
- [ ] 调整 `data/maps/survivor_outpost_01_grid.json` 的建筑 layout，适配新 geometry 输出
- [ ] 增加至少一组非矩形建筑样例
- [ ] 增加一组专门用于墙连接和门洞裁切的 demo map
- [ ] 保证旧 map 数据仍能通过兼容路径加载

---

## 17. 推荐实施顺序

按当前仓库状态，建议严格按以下顺序推进：

1. M1 `geo` 与共享几何结构
2. M2 footprint 权威化
3. M3 polygon-first 房间布局
4. M4 墙 / 门洞 / 楼梯 geometry
5. M5 polygon -> grid 回采样兼容
6. M6 `GeneratedBuildingStory` / snapshot 扩展
7. M7 viewer mesh 消费改造
8. M8 旧路径退役与文档清理

不要反过来先改 viewer mesh，再去补 `game_core` 权威几何；那会重新把表现层变成事实上的规则基准。

---

## 18. 完成定义

只有同时满足以下条件，才算该项真正完成：

- [ ] `game_data` 已支持 polygon footprint 与几何参数 schema
- [ ] `game_core` 已输出权威 `footprint_polygon / room_polygons / wall_polygons / door_openings`
- [ ] grid 相关 `wall_cells / walkable_cells / rooms.cells` 已明确来自回采样兼容层
- [ ] `bevy_debug_viewer` 默认主渲染已消费 polygon 几何结果
- [ ] 旧 `collect_story_wall_segments(...)` / “一段墙一个 box” 已不再是主路径
- [ ] 以下验证已通过：
  - [ ] `cargo test -p game_data`
  - [ ] `cargo test -p game_core`
  - [ ] `cargo test -p bevy_debug_viewer`
  - [ ] `bevy_debug_viewer` 手动 smoke test

---

## 19. 本项工作的自然下一步

如果按最小可回退改动推进，下一批代码应只做以下内容：

- [ ] 在 `game_core` 引入 `geo` 与 `building_geometry.rs`
- [ ] 在 `game_data` 增加 polygon footprint schema 与参数默认值/校验
- [ ] 先打通 `shape_cells -> footprint_polygon`，暂时不动 viewer 主路径

先把 `footprint_polygon` 权威链路做出来，再继续做 `room_polygons` 和 `wall_polygons`，这是最小、最稳、且最符合 `Rust` 权威化方向的切入点。
