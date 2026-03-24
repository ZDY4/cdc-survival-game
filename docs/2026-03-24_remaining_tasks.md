# 2026-03-24 Remaining Explicit Tasks

本文件汇总原 2026-03-24 四份开发文档中，按当前仓库实现状态判断后，仍然**没有完成**、并且已经足够明确、可以直接进入开发排期的任务。

已完成并因此不再重复列入本文件的内容包括：

- item editor 的基础引用预览、`Used By` 反查、可搜索引用选择、部分字段级校验路径映射
- NPC AI 的 `utility` 分层拆分、`Cook` 最小职业样板、基础调试快照增强
- `bevy_server` 的基础 NPC AI 调试输出

## 1. Bevy 交互迁移剩余任务

### 1.1 对话运行时权威化

- 在 `rust/crates/game_data` 增加对话库加载入口
- 在 `rust/crates/game_core` 增加权威 `DialogueRuntimeState`
- 将当前节点、可选分支、分支选择、动作节点执行统一下沉到共享 Rust 层
- 改造 `bevy_debug_viewer`，不再本地推进对话分支，只消费 `SimulationEvent` / `SimulationSnapshot`

### 1.2 真实地图切换

- 在 `rust/crates/game_core` 增加地图切换命令
- 切换时刷新 `GridWorld`、地图对象、交互对象与 actor 位置
- 为 `enter_subscene` / `enter_overworld` / `exit_to_outdoor` / `enter_outdoor_location` 建立统一入口
- 将返回点、outdoor resume、subscene resume 接到共享上下文

### 1.3 角色交互配置数据化

- 在 `data/characters/*.json` 逐步补全显式 `interaction`
- 优先覆盖商人、医生、守卫等高频 NPC
- 让 `game_bevy` 组装层优先读取显式交互配置，fallback 仅用于未迁移数据

### 1.4 Godot 协议前端化

- 基于 `game_protocol` 增加交互查询 / 执行 / 对话推进传输层
- 将 Godot 端收敛为点击命中、菜单 UI、动画表现、命令发送、事件消费
- 不再恢复或扩展 GDScript 本地交互权威逻辑

### 1.5 `bevy_server` 本地 TCP transport

- 在 `rust/apps/bevy_server` 增加本地 TCP server
- 支持 world snapshot 订阅
- 支持交互 prompt 查询 / 交互执行 / 对话推进
- 支持地图切换事件推送
- 保持消息语义与 `SimulationCommand` / `SimulationEvent` 一致

### 1.6 交互调试与测试补齐

- 丰富 `bevy_debug_viewer` 交互调试面板
- 显示完整 option payload
- 显示 pending interaction / pending movement
- 在 HUD 展示 inventory、地图上下文、对话动作结果
- 为不可执行交互显示失败原因
- 增加交互专项测试：
  - 接近后自动执行 attack / talk / scene transition
  - 敌对切换时 interaction prompt 顺序变化
  - 地图对象切换后 prompt 刷新
  - 对话分支与动作节点共享运行时测试

### 1.7 清理 Godot 旧交互实现

- 明确标记 `systems/interaction_system.gd` 与 `modules/interaction/*` 为 legacy
- 停止在这些脚本中继续扩展新功能
- 在 Godot 客户端改为协议前端后，再分阶段瘦身或删除

## 2. Item Fragment Editor 剩余任务

### 2.1 引用预览能力收尾

- 为 item / effect 引用补 hover 预览
- 保持 badge 摘要、右侧 detail panel、picker 预览一致
- 继续补齐高频引用位点的详情入口

### 2.2 模板与复制工作流

- 实现 `New From Template`
- 实现 `Duplicate Current Item`
- 实现 `Clone Fragment Set`
- 提供基础材料、可堆叠消耗品、近战武器、远程武器、护甲、饰品、带配方材料模板
- 复制时自动生成新 `id`、默认改名、保留 fragments 与相关引用

### 2.3 Shared Registries / Catalog Tightening

- 先在共享 Rust 层建立 registry / catalog
- 收紧高频字符串字段：
  - `equipment slots`
  - `rarity`
  - `weapon subtype`
  - `usable subtype`
- 编辑器默认从 registry 选择
- 校验器对未知值输出 warning

### 2.4 Data Lint and Reporting

- 在共享 Rust 层增加内容质量 lint：
  - 未被任何 item 引用的 effect
  - 缺 icon 的 item
  - 缺 economy fragment 的 item
  - 可装备 item 无属性加成也无效果
  - placeholder effect 长期未补真实 payload
  - 高度重复 item 组合
- 在编辑器增加只读报告页：
  - `Items report`
  - `Effects report`
  - `Broken references`
  - `Unused content`

### 2.5 Fragment Header Quick Edit

- 在 fragment 卡片头部增加高频字段快速编辑
- 优先覆盖：
  - `economy.rarity`
  - `stacking.max_stack`
  - `equip.level_requirement`
  - `usable.use_time`
  - `weapon.damage`

### 2.6 测试补齐

- 前端测试：
  - 新建 item 并添加 `equip + usable`
  - 保存后重载字段不丢失
  - 删除 fragment 后 UI 状态与 validation 同步
  - picker 写回真实 id
  - fragment 摘要随关键字段更新
- workspace / host 集成测试：
  - `load_item_workspace` 正确返回引用数据
  - save 时按最终 item 集合做交叉引用校验
  - effect / item 引用错误能稳定映射到前端 issue

## 3. NPC AI 剩余任务

### 3.1 扩展下一类职业样板

- 在 `Cook` 之后继续实现第二个非卫兵职业，优先 `Doctor`
- 为新职业补目标偏好、动作集、样例数据、运行时验证
- 确保不是复制一套新 AI 系统，而是复用现有三层边界

### 3.2 `Utility` 与上下文边界继续收紧

- 将当前评分继续拆成更稳定的评分项 / 策略函数
- 若需要，拆分 `NpcUtilityContext` 与 `NpcPlanningContext`
- 避免 `NpcPlanRequest` 再次膨胀为全能上下文

### 3.3 职业动作与预订系统继续模块化

- 将动作定义按职业能力集组织，例如：
  - `guard_actions`
  - `cook_actions`
  - `doctor_actions`
  - `common_life_actions`
- 将 reservation 抽成独立服务层，统一处理：
  - 占位
  - 释放
  - 冲突检测
  - 备用对象切换
  - 调试查询

### 3.4 调试可视化继续补齐

- 在 `bevy_debug_viewer` 增加 NPC AI 状态可视化
- 重点展示：
  - 当前目标
  - 目标得分
  - 当前动作
  - 动作阶段
  - 当前 anchor
  - reservations
  - `on_shift`
  - `meal_window_open`

### 3.5 执行层真实性增强

- 将 travel 从纯时间结算逐步接入真实导航
- 做在线 / 离线执行一致性校验
- 将 reservation 与路径可达性联动
- 为持续动作增加更细的中断 / 恢复策略

### 3.6 Godot 只读表现同步

- 输出 NPC 当前目标、动作、动作阶段、地点锚点、值班状态、警戒状态、睡眠状态
- Godot 侧只消费状态，不复制规划逻辑

### 3.7 编辑器与工具链支持

- 在编辑器中可视化编辑 settlement
- 编辑 `smart_objects`、`routes`、`schedule`、`service rules`
- 增加内容校验：
  - 缺失 anchor
  - route 断链
  - smart object 引用无效
  - 排班窗口非法
  - 岗位覆盖不足
- 增加 AI 内容批处理检查命令 / 工具
