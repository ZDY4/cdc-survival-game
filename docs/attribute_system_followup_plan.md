# 角色属性系统后续优化与功能开发计划

## 摘要
- 当前项目已经完成“统一属性容器 + 统一快照 API + 清理旧离散字段”的主切换。
- 下一阶段的重点不再是继续搬迁旧字段，而是把这套属性框架补成真正可持续扩展、可调试、可验证、可策划化的数据系统。
- 本计划把后续工作拆成四条主线：
  - 框架稳固化
  - 编辑器与策划工作流
  - 玩法能力扩展
  - 平衡性与可观测性
- 建议按“先补基础设施，再接玩法扩展”的顺序推进，避免在缺少可视化和验证工具的情况下继续堆内容。

## 当前系统仍可优化的点
- 属性定义已经数据化，但 definitions 仍主要由程序消费，缺少完整的作者视角校验和调试反馈。
- `AttributeSystem` 已统一快照解析，但对“某个最终数值是如何算出来的”还缺少可追踪的 source breakdown。
- 属性修改来源已经有 `source` 概念，但还没有统一的优先级、生命周期、冲突处理规范。
- 资源属性目前主要围绕 `hp/max_hp`，还没有抽象出更通用的资源模板，例如耐力、护盾、感染值、弹药池。
- 角色编辑器已经能消费 catalog/set/rules，但还缺少 definitions 本身的维护工具与预览工具。
- 运行时现在按需解析快照，但对大量 NPC 同屏、频繁 modifier 变更的性能边界还没有明确压测和缓存策略。
- 技能、装备、状态效果已经接入统一属性，但很多系统仍然只把属性当数值，不支持更细粒度的标签、来源、上下文条件。
- 存档已切到新 schema，但还没有正式的 schema version、数据升级策略和离线批处理规范。

## 目标
- 让属性系统成为角色成长、战斗计算、装备加成、状态效果、技能门槛的统一底座。
- 新增属性、新增属性集、新增派生规则时，优先通过数据配置完成，而不是改核心代码。
- 为策划和内容制作提供足够的编辑、校验、预览和排错能力。
- 为后续复杂玩法预留接口，例如多资源、抗性体系、元素伤害、职业模板、敌人词缀、关卡局部修正。

## 第一阶段：框架稳固化

### 1. 属性 schema 版本化
- 在 `player_attributes` 和角色 `attributes` 容器上增加显式 schema version。
- `AttributeSystem` 只接受当前版本，版本不匹配时给出明确错误，而不是隐式兜底。
- 保留离线升级脚本入口，后续 schema 变化统一通过脚本批量升级。

### 2. 属性变更来源标准化
- 为 modifier source 建立统一约定，例如：
  - `equipment:<slot>`
  - `skill:<id>`
  - `effect:<instance_id>`
  - `story:<flag>`
  - `difficulty:<mode>`
- 定义统一的生命周期接口：
  - 注册
  - 更新
  - 清除
  - 批量清除
- 约束 source 命名与清理规则，避免 runtime modifier 泄漏。

### 3. 快照分解能力
- 在 `AttributeSystem` 增加调试接口，例如：
  - `get_actor_attribute_breakdown(actor_or_id, key)`
  - `get_actor_full_breakdown(actor_or_id)`
- breakdown 至少展示：
  - catalog default
  - authored sets
  - rules 派生
  - equipment modifiers
  - skill/effect modifiers
  - clamp 结果
  - resource reconciliation 结果
- 这会极大降低后续查数值问题的成本。

### 4. 运行时缓存与脏标记扩展
- 现在玩家已有 snapshot cache，后续可把 NPC 也纳入统一缓存。
- 为非玩家 actor 建立：
  - container dirty
  - modifier dirty
  - snapshot dirty
- 避免战斗中每次查询都完整重算全部属性。

### 5. 统一事件流
- 增加更细粒度信号：
  - `actor_attributes_changed(actor_id, changed_keys)`
  - `actor_resource_changed(actor_id, resource_key, current, max)`
  - `actor_modifier_changed(actor_id, source)`
- UI、AI、战斗日志、调试面板都可以直接订阅，而不是主动轮询。

## 第二阶段：编辑器与内容工作流

### 1. 属性 definitions 校验工具
- 新增 editor/tool 脚本校验以下内容：
  - catalog 中属性键是否重复
  - set definition 是否引用不存在属性
  - rule 的 source/target/resource 是否合法
  - resource link 是否指向合法 max attribute
  - clamp 范围是否与 catalog 冲突
- 校验结果应能在编辑器中直接展示，而不是只靠启动时报错。

### 2. 属性 definitions 编辑器
- 当前角色编辑器已经能消费 definitions，下一步应增加专门的 definitions 编辑器。
- 编辑器应支持：
  - 新增属性
  - 编辑类型、默认值、范围、显示名、分类标签
  - 配置属性集分组
  - 配置有限规则
  - 即时预览一个示例角色的最终快照
- 目标是让“新增一个属性”完全变成内容配置工作，而不是程序改动。

### 3. 角色属性模板
- 增加角色模板或 archetype 概念，例如：
  - `civilian`
  - `soldier`
  - `zombie_fast`
  - `boss_mutant`
- 模板用于提供默认属性集和值，再由具体角色覆盖少量差异项。
- 这样可减少角色 JSON 重复，并降低整体维护成本。

### 4. 编辑器中的数值解释面板
- 在角色编辑器预览区除了显示最终值，还显示“来源解释”。
- 例如 `max_hp = authored 50 + constitution rule + equipment + effect`。
- 这能帮助策划理解为什么配置值和最终表现不一致。

### 5. 批量校验与批量修复
- 增加一键扫描：
  - 所有角色属性容器合法性
  - 所有技能 attribute requirements 合法性
  - 所有装备属性修正键合法性
- 提供可选的批量修复动作，例如补齐必选 set、删除未知属性键。

## 第三阶段：玩法能力扩展

### 1. 通用资源体系
- 把 `hp` 之外的资源也纳入资源层，优先考虑：
  - `stamina`
  - `mental`
  - `infection`
  - `shield`
  - `ammo_capacity` 对应的动态资源
- 每种资源应支持：
  - 当前值
  - 上限链接
  - 比例保留
  - clamp
  - UI 是否可见

### 2. 抗性与伤害类型体系
- 新增一套更系统化的属性目录：
  - `physical_resistance`
  - `bleed_resistance`
  - `infection_resistance`
  - `fire_resistance`
  - `poison_resistance`
- 战斗系统后续可以逐步从单一 `defense` 演进到“伤害类型 + 对应抗性”的结构。

### 3. 命中链路细化
- 当前 `accuracy/evasion/crit/speed` 已接入战斗，但还可以继续展开：
  - 命中前摇修正
  - 部位命中修正
  - 武器熟练度修正
  - 疲劳/负重/状态异常修正
- 建议把这些修正都通过统一 modifier 或规则管线进入属性快照，而不是散落在战斗公式中。

### 4. 条件型属性修正
- 在现有有限规则之外，引入受控的条件修正模型，例如：
  - 低血量时加暴击
  - 夜间提高潜行
  - 雨天降低命中
  - 背包超重降低速度
- 不建议直接开放任意脚本。
- 建议使用受控条件枚举 + 参数化配置。

### 5. 职业、标签与派系修正
- 结合角色标签或 gameplay tags，为属性引入条件分组。
- 例如：
  - `tag:undead` 获得毒抗
  - `faction:military` 初始 accuracy 更高
  - `class:scavenger` 基础 carry_weight 更高

### 6. 装备词缀与敌人词缀
- 把装备随机词缀、敌人词缀都收敛成属性 source。
- 例如：
  - 装备词缀 `精准` -> `accuracy +8`
  - 敌人词缀 `狂暴` -> `attack_power +20%, speed +10%`
- 这样战利品系统和敌人生成系统都能复用属性框架。

## 第四阶段：平衡性与可观测性

### 1. 平衡模拟器
- 提供一个离线平衡脚本或 editor 工具，输入角色、装备、技能、状态后输出：
  - 最终属性快照
  - 估算 DPS
  - 估算生存时间
  - 命中率与暴击率区间
- 方便快速验证平衡改动是否偏离预期。

### 2. 属性覆盖率测试
- 增加自动化测试，确保 catalog 中每个属性至少满足其一：
  - 被编辑器显示
  - 被规则消费
  - 被运行时系统读取
  - 被明确标记为保留/隐藏属性
- 避免“配置存在但永远不生效”的僵尸属性。

### 3. 性能基准测试
- 建立 50 / 100 / 200 actor 的快照解析基准。
- 记录以下指标：
  - 平均解析耗时
  - modifier 更新耗时
  - 战斗回合内属性查询次数
- 如果性能不够，再决定是否做更激进的缓存或预编译规则。

### 4. 存档自检
- 存档写入前执行 schema 自检。
- 加载时对当前 schema 做强校验，并提供可读错误信息。
- 避免“存档能读但数值已经部分损坏”的隐性问题。

### 5. 开发调试面板
- 增加运行时调试 UI，支持查看：
  - 玩家当前快照
  - 选中 NPC 当前快照
  - 每个 source 的 modifier
  - 最近一次属性变更日志
- 这会显著提升后续联调效率。

## 推荐的近期开发顺序

### Sprint 1
- 完成 attribute breakdown 调试接口。
- 完成 definitions 校验工具。
- 为非玩家 actor 增加 snapshot cache 与 dirty 标记。
- 补齐属性系统自动化测试。

### Sprint 2
- 完成角色模板系统。
- 完成 editor 中的 breakdown 预览。
- 补齐 `stamina` 与 `mental` 的资源化接入方案。

### Sprint 3
- 接入抗性体系和条件型属性修正的最小版本。
- 实现装备词缀和敌人词缀的统一 modifier 接入。
- 增加平衡模拟脚本。

### Sprint 4
- 开发 attributes definitions 编辑器。
- 推进战斗系统从单防御值向“伤害类型/抗性”演进。
- 建立完整的 schema version 与离线升级流程。

## 建议新增的测试清单
- 新增一个 catalog 属性后，不改核心代码即可在角色编辑器显示、保存、预览。
- 新增一个属性集定义后，角色可挂载该 set，并参与最终快照计算。
- 同一属性被多个 source 修正时，结果稳定且可解释。
- source 被移除后，对应修正会立即从快照消失。
- 多个资源同时存在时，resource reconciliation 互不串扰。
- 技能门槛、装备修正、状态效果都只通过统一 API 生效。
- 存档写入与读取能保持属性容器一致性。
- 角色模板叠加具体角色覆盖值时，最终 authored container 可预测。

## 风险与注意事项
- 不要过早把规则系统做成“任意表达式执行器”，否则很快会失控且难以调试。
- 不要让 AI 参数、关卡配置、剧情变量无边界并入属性 catalog，否则属性系统会退化成杂项字典。
- 新增属性时需要同步考虑：
  - catalog 展示语义
  - 是否属于某个 set
  - 是否需要派生规则
  - 是否需要 UI 呈现
  - 是否需要测试覆盖
- 如果后续引入更多资源，必须尽早定义资源刷新、回满、按比例缩放、死亡阈值等统一语义。

## 验收标准
- 属性系统可以稳定支撑新增属性、新增属性集、新增修正来源，而不需要再改核心读取接口。
- 编辑器与工具链足够让策划独立完成大部分属性配置工作。
- 开发者可以快速解释任意一个最终属性值的来源。
- 战斗、技能、装备、状态、存档、UI 对属性的读写路径保持统一。
- 新增复杂玩法时，优先扩展 definitions 和 modifier，而不是重新造一套平行属性系统。
