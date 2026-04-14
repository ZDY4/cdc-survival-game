# Instanced Tile-Based 3D World 执行看板

本文档只保留当前还需要推进的内容，并压缩为执行清单。

---

## 进行中

### Tactical Surface 内容落地

- 继续把真实 tactical 地图区域写入 `visual.surface_set_id`
- 扩大 `elevation_steps + slope` 的真实使用范围
- 梳理哪些区域应进入 surface 主链，哪些仍保持普通 ground

### Prop Placement 收口

- 保持 viewer / map editor 对 prop 的旋转、偏移、pick proxy 语义一致

---

## 待做

### Overworld 迁移到 Tile World

- `OverworldTerrainKind` 回收为 gameplay / 语义层权威

### 清理剩余 Box / Fallback 主渲染路径

- 继续审计 viewer 中剩余 `spawn_box()` 调用，压缩到 proxy / debug / 少量过渡几何

### 实例升格为独立动态实体

- 定义统一实例句柄、生命周期与状态分类
- 做 shared 批实例隐藏 / 替换机制
- 打通静态实例 -> 动态实体升格管线
- 补完回收 / 持久独立 / 状态同步策略
- 首批打通对象：
  - 门
  - 柜子 / 箱子
  - 可破坏 prop

### Prototype / TileSet / Behavior Schema 补全

- 补 prototype 元数据：
  - canonical orientation
  - pivot 约定
  - pick proxy / occluder policy
  - interaction / upgrade class
- 补 wall set / surface set 约定与加载期校验
- 把实例升格需要的行为入口正式落到 schema
- 完成内容迁移与校验收口

### 资产流水线与最终切换

- 稳定 placeholder 烘焙工具
- 增加资产与 catalog 一致性校验
- 增加 batch / instance / fallback 统计
- 切换到 `tile / prototype / placement` 默认基线
- 把旧程序化 runtime builder 和旧 fallback 链降为非默认

---

## 暂后

### 当前明确不做

- 不同步改写 pathfinding / movement
- 不做复杂地形自动生成
- 不一次覆盖所有 cliff 拓扑
- 不在阶段 2 之前提前做大规模 schema 过度设计
- 不让旧客户端重建一套同类 tile world 主逻辑

---

## 推荐顺序

1. 继续扩大 tactical surface 的真实地图覆盖面
2. 继续收口 prop placement
3. 做 overworld 迁移
4. 清理 box / fallback 主链
5. 做实例升格
6. 补 schema
7. 做资产流水线和最终默认切换

---

## 里程碑

### 里程碑 A：静态世界主链稳定

- tactical map 中建筑墙、建筑地板、部分真实地表、主要环境 prop 已进入 shared tile world
- viewer / map editor 不再依赖 box fallback 才能显示这些内容

### 里程碑 B：静态与动态边界清晰

- static instance 与 dynamic entity 的生命周期边界明确
- 升格对象不再依赖临时 viewer 逻辑硬编码

### 里程碑 C：正式框架闭环

- 内容 schema、shared runtime、viewer/editor、资产流水线全部闭环
- tile-based 3D world 成为仓库默认世界构造方式
