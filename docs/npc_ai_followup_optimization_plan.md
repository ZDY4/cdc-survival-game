# NPC AI 后续优化建议

## 目的

本文档用于承接当前已落地的 NPC 三层 AI 架构：

- `Utility AI` 负责目标选择
- `Light GOAP` 负责短计划拆解
- `Action FSM / Executor` 负责具体执行

当前项目已经完成：

- `guard_only` 最小闭环
- `dogoap` 接入
- `SettlementDefinition` 与 `life` 数据落地
- `Utility` 从 `GOAP` 中首轮拆分

因此，后续优化重点不再是“要不要做这套架构”，而是“如何把这套架构做得更稳定、可扩展、可调试”。

## 当前状态判断

当前系统已经具备以下基础：

- 可以在 `Bevy` 侧运行据点卫兵的基本日常逻辑
- 可以按排班与需求触发目标切换
- 可以生成短动作链并执行
- 可以处理中断、预订冲突和离线持续推进

但仍存在以下典型短板：

- `utility` 仍是单文件评分逻辑，扩职业时容易继续膨胀
- action 集仍明显偏卫兵样板
- `game_bevy` 的调试可观测性还不够强
- Godot 尚未接入只读状态消费
- 编辑器尚不能配置 settlement / smart object / schedule

## 优先级建议

### P1：巩固 `Utility` 层

这是当前最优先的优化方向。

原因：

- 虽然 `Utility` 已从 GOAP 中拆出，但评分仍集中在单个模块中
- 如果此时直接扩更多职业，评分逻辑很容易再次变成一团

建议优化项：

- 将 `utility` 拆成更明确的评分函数，例如：
  - `threat_score`
  - `life_preservation_score`
  - `shift_score`
  - `meal_score`
  - `sleep_score`
  - `morale_score`
- 将职业差异从 if/else 转向“职业评分修正”
- 将据点规则影响从散落判断收敛到统一评分输入

完成标准：

- `select_goal` 只负责汇总和排序
- 各目标评分具备独立函数或独立模块
- 新职业新增时，不需要修改 GOAP 模块

### P2：扩展第二类职业样板

推荐优先顺序：

1. 厨师
2. 医生

原因：

- 这两类职业比卫兵更能验证“目标权重 + 动作集变化”的复用性
- 它们仍然属于据点生活逻辑，不需要先引入复杂战斗问题

建议厨师动作集：

- `TravelToKitchen`
- `ReserveKitchenStation`
- `PrepareMeal`
- `RestockMealService`
- `EatMeal`
- `TravelHome`
- `Sleep`

建议医生动作集：

- `TravelToClinic`
- `ReserveClinicSpot`
- `TreatPatient`
- `RestockMedicine`
- `Relax`
- `TravelHome`
- `Sleep`

完成标准：

- 第二类职业接入不需要复制一套新的 AI 系统
- 只通过新增 smart object、目标权重和动作集即可运行
- 现有卫兵行为不回归

### P3：增强调试与可观测性

当前系统已经能跑，但仍然不够“好调”。

建议增强内容：

- 在 `SettlementDebugSnapshot` 中增加：
  - 当前事实集合
  - 当前目标得分表
  - 当前计划剩余步骤
  - 当前动作阶段
  - 当前预订对象
- 在 `bevy_server` 增加最小调试输出或调试接口
- 在 `bevy_debug_viewer` 中增加 NPC AI 状态可视化

建议优先显示：

- `goal`
- `goal_scores`
- `current_action`
- `current_phase`
- `current_anchor`
- `reservations`
- `on_shift`
- `meal_window_open`

完成标准：

- 能快速回答“为什么这个 NPC 现在在做这件事”
- 能快速区分“选错目标”和“执行失败”

### P4：增强执行层真实性

当前执行层更偏“离线持续模拟优先”，适合验证逻辑闭环，但还不够接近最终运行时。

建议优化项：

- 将 travel 从纯时间结算逐步接入真实导航
- 引入在线/离线执行一致性校验
- 将 smart object 预订和路径可达性联动
- 对持续动作增加更细的中断与恢复策略

重点原则：

- 在线执行和离线执行必须共享同一套动作生命周期
- 不允许为“玩家在场”和“不在场”分别写两套 AI

完成标准：

- 同一行动链在在线和离线模式下语义一致
- 切换模式不会重置 NPC 到不合理状态

### P5：接入 Godot 只读表现同步

这是三端分离方向里的关键一步。

建议同步字段：

- 当前目标
- 当前动作
- 当前动作阶段
- 当前地点锚点
- 是否在值班
- 是否警戒
- 是否睡觉

实现原则：

- Godot 只消费状态
- Godot 不复制规划和打分逻辑
- Rust / Bevy 是唯一规则权威

完成标准：

- Godot 端 NPC 表现与 Rust 端运行状态一致
- 不在 Godot 中出现第二套行为判断

### P6：编辑器支持

当前仍依赖手写 JSON。

建议逐步支持：

- settlement 编辑
- anchor 编辑
- route 编辑
- smart object 编辑
- schedule 编辑
- service rule 编辑

建议编辑器内置校验：

- 缺失 anchor
- route 断链
- smart object 引用无效
- 排班窗口非法
- 岗位覆盖配置不足

完成标准：

- 据点生活内容可视化编辑
- 常见配置错误能在编辑期被发现

## 结构性优化建议

### 建议 1：给 `utility` 增加独立输入模型

当前 `Utility` 和 `GOAP` 仍共用 `NpcPlanRequest`。

长期建议拆成：

- `NpcUtilityContext`
- `NpcPlanningContext`

好处：

- 让上层目标选择输入更清晰
- 避免 GOAP 请求结构越长越像“全能上下文”

### 建议 2：动作定义按职业能力集组织

不要长期把所有动作平铺在一个模块里。

建议未来拆成：

- `guard_actions`
- `cook_actions`
- `doctor_actions`
- `common_life_actions`

好处：

- 新职业接入更清晰
- 不容易把样板动作互相污染

### 建议 3：预订系统抽成独立子模块

当前 reservation 已能工作，但长期建议抽成独立服务层，统一处理：

- 占位
- 释放
- 冲突检测
- 备用对象切换
- 调试查询

好处：

- 避免每个动作都重复处理预订逻辑
- 更容易扩到厨房、诊疗位、娱乐点等更多对象类型

## 风险提醒

### 不要过早把 GOAP 数据化

在第二类、第三类职业还没验证前，不建议把动作系统直接做成编辑器配置驱动。

原因：

- 行为域尚未稳定
- schema 很可能频繁变化
- 现在更适合通过代码快速验证抽象边界

### 不要让 Godot 回收目标选择职责

即使未来需要快速表现，也不要把目标选择重新写回 Godot。

原因：

- 会打破三端分离
- 会形成双份规则
- 后期调试和同步都会变难

### 不要让 `NpcPlanRequest` 无限膨胀

如果所有上下文都往里堆，它很快会变成一个巨型参数对象。

建议：

- 短期可以继续用
- 中期拆为 utility context 和 planning context

## 建议的后续开发顺序

1. 优化 `utility` 结构，拆成评分项。
2. 实现第二类职业样板，优先厨师。
3. 增强调试快照和调试 UI。
4. 提升在线执行真实性。
5. 接入 Godot 只读状态同步。
6. 最后再做编辑器支持。

## 一句话建议

当前最值得做的，不是继续把系统做得更“大”，而是先把这套三层结构做得更“稳、更清晰、更可复用”。

优先顺序应当是：

`巩固 Utility -> 扩职业样板 -> 强化调试 -> 接入客户端表现 -> 最后编辑器化`
