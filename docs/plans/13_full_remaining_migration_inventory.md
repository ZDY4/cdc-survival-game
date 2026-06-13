# Godot 剩余迁移清单

本文只保留仍未完成、待补齐或待等价复核的迁移事项。已完成的实现记录、smoke 覆盖说明和阶段流水账不再放在这里维护。

## 使用边界

- 当前工程运行时和开发主线为 `Godot 4.6.3 + GDScript`。
- Godot 工程目录为 `godot/`，命令行入口固定为 `D:\godot\godot.cmd`。
- 地图权威是 `godot/scenes/maps/*.tscn`；`data/maps/*.json` 只作为迁移期兼容备份和等价复核来源。
- 非地图内容权威仍是 `data/` JSON，由 `godot/scripts/data` 统一读取、校验、查询、格式化和安全写回。
- 玩法结果必须落在 `godot/scripts/core` 或明确的 core service；UI 和 world 只能提交输入、展示 snapshot 或调用数据服务。
- 旧参考工程只作为行为、参数和资源组织的只读来源，不把 Rust、Cargo、Bevy、WGSL 运行时代码重新放回当前主线。

## Godot 原生优先原则

- 表现、输入、UI、动画、音频、碰撞、导航、资源导入和场景组织优先使用 Godot 原生节点、资源和编辑器工作流；项目自研层只保留玩法规则、数据 schema、存档、确定性模拟和跨系统编排。
- UI 不再发展自研 widget / modal / tooltip / drag 系统；优先使用 `Control`、`PopupPanel`、`AcceptDialog`、`ConfirmationDialog`、`Theme`、`_make_custom_tooltip()` 和 Godot 原生 drag/drop 回调。
- 地图、门、容器、入口点、触发器和工作台优先表达为 `.tscn` 子场景、`Node3D`、`Area3D`、`CollisionShape3D` 与 `@export` 元数据；JSON 只保留非地图内容或迁移期复核来源。
- 交互命中、hover、遮挡和对象选择优先通过 `Camera3D` ray、`PhysicsRayQueryParameters3D`、collision layer / mask、`Area3D` 实现；项目逻辑只负责多命中排序和业务 reason。
- 移动和空间规则若必须保持格子制，可继续保留 core topology；但阻挡、楼梯、门洞、场景尺寸、视觉碰撞和导航来源应尽量从 Godot scene、physics 和 navigation 数据派生。
- 动画和动作表现由 `AnimationPlayer`、`AnimationTree`、`Tween`、`GPUParticles3D`、`AudioStreamPlayer3D` 等资源 / 节点承载；`WorldActionPresenter` 只做事件到表现资源的编排。
- 资源导入、uid、材质、碰撞体和资源引用优先使用 Godot import preset、`.import`、`ResourceUID`、`PackedScene` 和必要的 `EditorImportPlugin`；agent 脚本负责审计和报告，不替代 Godot 导入系统。

## 文档关系

- `docs/plans/10_godot_migration_architecture.md`：Godot 迁移架构、目录职责和阶段边界。
- `docs/3d_asset_format_policy.md`：正式 3D 资产格式和导入规则。
- `docs/agent-workflows/*.md`：agent 工具、内容编辑、地图复核和 smoke / validate 工作流。
- `docs/narrative/**`：剧情、角色、地点、物品和世界观内容来源。
- `docs/plans/09_mainline_followup_polish.md`：主线剧情打磨待办，不作为运行时迁移总账。

## 0. 内容、Schema 和来源

### 0.1 来源覆盖

- [ ] 每个迁移项都要能追溯旧来源、Godot 落点和验收方式，避免只迁显眼玩法而漏掉工具、表现、诊断或数据默认值。
- [ ] `content_tools` 的 summarize、references、format、diff-summary、changed、validate、content edit CLI 行为需要继续逐项对齐。
- [ ] `game_core` 的 Simulation、turn / AP、movement、interaction、combat、economy、quest、dialogue、skills、crafting、AI、GOAP、overworld、vision、building、survival 规则需要持续做等价复核。
- [ ] `game_data` 的内容 schema、默认值、校验、引用、预览、编辑服务、原子写回、map schema、appearance、AI、dialogue、quest、recipe、skill 需要持续补齐。
- [ ] `game_bevy` 的相机、tile / world render、门表现、fog、UI snapshot、picking、asset path、debug 视觉、NPC life sync 只转译为 Godot 实现。

### 0.2 内容数据和 Schema

- [ ] 内容安全写回补更多自动修复种类和外部 IO 异常 fixture。
- [ ] JSON path 定位补批量 `validate changed` 的更多坏例 fixture 和 editor dock 定位跳转。
- [ ] `changed` / `diff-summary` 补旧工具全部输出字段兼容和更多真实仓库 deleted / renamed fixture。
- [ ] 跨 domain 引用校验补更多 legacy JSON 字段和更广的地图 asset id 映射。
- [ ] Schema migration 补按 domain 的业务旧字段迁移器、JSON 行列号和迁移日志持久化。
- [ ] `data/json` 下 ammo、attribute、balance、camp relations、clues、effects、encounters、scavenge、structures、tools、weather 等继续判定是否仍为权威或需要合并进正式 domain。

### 0.3 内容域账本

- [ ] `data/ai`：GOAP facts、行为模块、profile、settlement NPC group、后台日程。
- [ ] `data/appearance`：character model、装备覆盖、socket、fallback 模型、运行时绑定。
- [ ] `data/bootstrap`：初始地图、entry、玩家 actor、初始背包、任务、world flags、相机。
- [ ] `data/characters`：玩家、友方 NPC、中立 NPC、敌人、商人、医生、任务角色、loadout、AI、dialogue / shop 绑定。
- [ ] `data/dialogue_rules` 和 `data/dialogues`：节点、选项、条件、动作、任务接取 / 推进 / 交付、交易打开、fallback、结束。
- [ ] `data/items`：武器、装备、消耗品、材料、工具、任务物品、货币、模型、效果、价格、重量、堆叠。
- [ ] `data/maps`：只做迁移期备份和 scene 等价复核，不再作为新地图编辑入口。
- [ ] `data/overworld`：地点解锁、旅行、遭遇、入口、返回。
- [ ] `data/quests`：collect / kill / dialogue / turn-in、奖励、失败、互斥、world flag。
- [ ] `data/recipes`：材料、产物、工具、工作台、技能、解锁、XP、队列。
- [ ] `data/settlements`：据点成员、角色、锚点、服务、日程。
- [ ] `data/shops`：库存、资金、价格倍率、权限、补货。
- [ ] `data/skill_trees` 和 `data/skills`：树布局、节点、前置、主动 / 被动、目标策略、效果、hotbar。
- [ ] `data/world_tiles`：surface、wall、prop、container prototype 与 Godot 资产映射。

### 0.4 地图 Scene 逐图核对

每张地图都要确认 entry point、actor spawn、map object、footprint、blocking、LOS、door、transition、container、pickup、NPC、敌人、模型资源、比例、旋转、重叠、picking、相机初始视角、fog、任务 / 对话 / 商店锚点。

- [ ] `factory.tscn`
- [ ] `forest.tscn`
- [ ] `hospital.tscn`
- [ ] `ruins.tscn`
- [ ] `school.tscn`
- [ ] `street_a.tscn`
- [ ] `street_b.tscn`
- [ ] `subway.tscn`
- [ ] `supermarket.tscn`
- [ ] `survivor_outpost_01.tscn`
- [ ] `survivor_outpost_01_interior.tscn`
- [ ] `survivor_outpost_01_perimeter.tscn`

## 1. 资产和表现

- [ ] 字体补富文本 fallback、CJK fallback 和截图级缺字回归；运行时 UI 优先通过 Godot `Theme` / `.tres`、`RichTextLabel` 和字体 fallback 配置处理。
- [ ] 容器模型补真实 `CollisionShape3D` / `Area3D`、hover outline 视觉 polish、`AnimationPlayer` 打开 / 关闭动画和更细容器子场景类型表现。
- [ ] 角色、装备、武器补 Godot skeleton bone attachment、`AnimationTree` / `AnimationPlayer`、材质 override、手部 IK / 持握动画、reload 动画、`GPUParticles3D` muzzle flash、弹壳模型、弹道材质和 hotbar 图标最终美术。
- [ ] 地表、建筑墙和 prop tile 补 scene 子资源中的旋转 footprint、local offset、scale、阻挡、LOS、材质、遮挡和 hover；阻挡与 picking 来源优先读取 Godot collision layer / mask。
- [ ] UI icon / portrait / thumbnail 补真实美术替换、更细分图标表现、存档截图、尺寸规范、缓存策略和真实缩略图布局；图标和缩略图优先作为 Godot `Texture2D` / resource 引用管理。
- [ ] 地图专属资产补真实 glTF collision 资源、scale / rotation / origin 校准、shadow / visibility 策略、`ResourceUID` 细节复核和人工审阅流程。
- [ ] `.bin`、`.import`、`.uid` 守护补人工审阅流程和资源引用变更差异复核；导入权威保持 Godot import preset / `.import` / `ResourceUID`。
- [ ] 旧 data 中 UI icon / portrait legacy `assets/...` 路径补正式资源落地与迁移。
- [ ] 真实音频资源、真实音乐 / 环境声素材、3D 衰减听感校准、更多跨面板 UI 控件反馈和更多材质 / 武器 / 门类型音色；播放和混音优先使用 `AudioStreamPlayer`、`AudioStreamPlayer3D`、Audio Bus Layout 和 `AudioServer`。

## 2. 运行时、命令和回合

### 2.1 Runtime Snapshot

- [ ] runtime snapshot 补目标预览视觉参数、更细 debug-only 诊断字段和 HUD polish。
- [ ] 运行时事件 payload 补完整失败反馈、禁用原因和 UI 刷新 payload。
- [ ] deterministic seed 补 AI 随机选择、技能随机效果、任务随机奖励和跨系统 seed 命名策略。

### 2.2 命令入口

- [ ] 命令 reject 补更完整领域 reason 和 UI 禁用态视觉 polish。
- [ ] 可取消命令补 quantity modal 和关闭优先级 HUD polish。
- [ ] 命令审计扩展到更多 UI controller 直接 root 调用矩阵，并补跨系统禁用 reason 文档。

### 2.3 探索回合

- [ ] 补 Rust `PendingProgressionStep` 式分帧推进，避免所有恢复逻辑都同步挤在单次 command 中。
- [ ] AP / action cost 补更完整配置表和不同状态、装备、技能对 AP 参数的叠加规则。
- [ ] 玩家行动后自动结束回合策略补更多 UI 入口展示 polish。
- [ ] 长按 Space 连续等待补更细 key repeat 诊断、用户设置化间隔和 HUD 提示 polish。
- [ ] 自动推进保护补 UI 提示 polish、pending 清理策略和异常恢复流程。

### 2.4 战斗回合

- [ ] 战斗 HUD 补完整布局、队列可视化和目标选择 polish。
- [ ] 战斗内 AP / NPC 回合补更细逐 actor 调度状态和完整战斗 UI 队列表现。
- [ ] 战斗参与者补友军 / 中立加入规则调参和真正的 initiative 队列执行。
- [ ] 战斗退出补对话或任务强制退出、战后 HUD / targeting 视觉恢复和回合 UI 顺序。

## 3. 输入、选择和 UI 状态机

- [ ] Esc 关闭链路补 quantity modal 更细策略；modal 优先用 `PopupPanel`、`AcceptDialog`、`ConfirmationDialog` 的可见性和 focus 状态驱动。
- [ ] 数字键补菜单内数量输入与快捷动作冲突处理。
- [ ] Space 等待补更细长按节奏配置和 modal 冲突策略。
- [ ] Tab / free observe 补鼠标选择视觉 polish、更完整诊断、多层地图显隐、楼梯 / 跨层路径和遮挡规则。
- [ ] 面板拖拽补 quantity modal 更细策略、真实拖拽视觉 polish、滚动条拖拽、跨面板 hover 高亮、拖拽后一次性 suppress click 和不支持拖放目标的显式诊断策略；实现优先复用 `_get_drag_data()`、`_can_drop_data()`、`_drop_data()` 和 Godot drag preview。
- [ ] UI mouse blocker 补 debug selection panel 显示、inventory quantity 和更多 drag hover 高亮；阻塞语义优先来自 `Control.mouse_filter`、focus 和 Popup 可见状态。
- [ ] Modal / tooltip / context menu 补完整优先级矩阵、屏幕位置、延迟、显隐生命周期、场景切换 / 库存 / 容器 / 交易 / 制作按钮覆盖和 layer 阻塞 / 关闭优先级；tooltip 优先使用 `_make_custom_tooltip()`，菜单优先使用 `PopupMenu` / `PopupPanel`。
- [ ] Toast / feed 补更完整 reason 映射和视觉 polish；视觉状态优先通过 `Theme`、`AnimationPlayer` 或 `Tween` 实现。

## 4. 移动、路径、空间与地图规则

### 4.1 网格和路径

- [ ] 复核 Godot 网格数学与旧实现等价：cell distance、对角移动、禁止穿角、同层限制、bounds、levels。
- [ ] 补 generated building stairs 跨层 pathfinding、楼梯端点、楼层切换和目标楼层显示；楼梯和跨层连接优先来自地图 scene 中的楼梯节点 / `Area3D` / export 元数据。
- [ ] 动态阻挡补门阻挡诊断、楼梯跨层和更完整 UI 文案映射；阻挡来源优先从 Godot collision、door scene 状态和 navigation 数据派生，再同步到 core topology。
- [ ] 路径预览补路径线 polish、更丰富多格路径着色和跨回合动画表现；视觉优先使用 `MeshInstance3D` / `ImmediateMesh` / `Line2D` 类 Godot 渲染节点，而不是自研绘制缓存。

### 4.2 门和建筑

- [ ] 将现有地图建筑门洞批量改为真实 Godot 门子场景，使用 `Node3D`、`Area3D`、`CollisionShape3D` 和 `@export` 属性承载门 id、锁、钥匙、工具和交互元数据；`props.door` 只作为兼容迁移输入。
- [ ] 锁门补逐件 / 多 stack 工具耐久、失败概率和更完整开锁表现。
- [ ] 自动开门补 GOAP planner 路径自动开门、`AnimationPlayer` 开合状态更新和 `AudioStreamPlayer3D` 声音占位。
- [ ] 建筑 footprint 阻挡补复杂 footprint、多层 story、door opening、wall visual、floor visual 和路径阻挡一致；优先由 scene collision / navigation 区域生成或校验。
- [ ] 门表现补真实门模型、`CollisionShape3D`、`Area3D` 交互区、交互提示 polish 和声音占位。

### 4.3 地图切换和 Overworld

- [ ] Scene transition 补确认 prompt 视觉 polish 和更完整 overworld 进入 / 返回提示；transition 入口优先用 `Area3D` / trigger 子场景和 `@export` 目标 map / entry 元数据。
- [ ] Overworld 补最近到达地点、显式路线规划、返回 prompt 和无法进入原因 UI；地图面板图形优先用 `Control._draw()` 或 Godot UI 节点绘制。
- [ ] 地图切换补更细过渡动画、已探索 / 可见格平滑混合和 overworld prompt polish；过渡优先使用 `AnimationPlayer` / `Tween` / `CanvasLayer`。
- [ ] 所有 `godot/scenes/maps/*.tscn` 与旧 JSON 备份做字段等价复核：size、levels、entry points、objects、footprints、rotations、props、triggers；复核后权威落到 Godot scene 节点和 export 属性。

## 5. 交互系统

### 5.1 目标解析

- [ ] 输入层 picking 多命中补可视化优先级诊断和 UI 文案 polish；命中检测优先使用 `Camera3D` ray + `PhysicsRayQueryParameters3D`，项目层只处理排序和业务 reason。
- [ ] Friendly / neutral / hostile 交互补 trade、heal、inspect、关系分数和脚本化 NPC 权限。
- [ ] Target visibility 补雾中探索态、遮挡 target preview 和 UI 文案。
- [ ] Interaction range 补动态 AP / 距离配置、特殊对象权限、路径预览和 UI 文案映射；对象范围优先读取 `Area3D`、collision shape 或 scene export 元数据。
- [ ] Prompt snapshot 补完整 target display、动态 AP cost 来源、更多可见性禁用、权限禁用和 UI 文案映射。

### 5.2 交互行为

- [ ] 每种交互行为补完整失败反馈、禁用原因和 UI 刷新点。
- [ ] Pickup 补部分拾取、数量弹窗、拾取失败细分、拾取音效和 UI 提示 polish；地图拾取对象优先用拾取子场景 / `Area3D` / export 元数据表达。
- [ ] Container interaction 补商店 / 任务容器与普通容器的深度权限差异、部分拿取数量弹窗 polish、真实容器音频资源和真实 hover / open 动画表现；容器表现优先由容器子场景、`AnimationPlayer` 和 `AudioStreamPlayer3D` 承载。
- [ ] Talk 补 schedule / on_shift 真实时间判定、fallback 台词生成和对话 UI 文案 polish。
- [ ] Scene transition 补确认 prompt 视觉、overworld 进入 / 返回 prompt 和更完整地图切换 UI polish。
- [ ] Wait self interaction 补更完整 modal 冲突策略和视觉 polish。

## 6. 战斗、目标和伤害

### 6.1 攻击校验

- [ ] Friendly fire 补 UI 二次确认弹窗、犯罪 / 目击 / 阵营联动和 UI 文案 polish。
- [ ] 攻击空间校验补楼梯 / 高低差、特殊武器例外和技能共用射程策略。
- [ ] LOS 扩展补技能共用空间失败原因，以及墙体、门、楼层、中心点遮挡的旧版细节。
- [ ] 范围扩展补特殊武器例外、更多数据内容标注和技能射程共用策略。
- [ ] 攻击预览补门 / 楼层例外下的可攻击格精确过滤和视觉 polish。

### 6.2 武器、弹药和伤害

- [ ] 命中、闪避、格挡和护甲补 NPC 命中体验调参、更多装备效果、详细战斗日志面板和旧版完整公式复核。
- [ ] 伤害类型、抗性、弱点等旧数据如果存在，需要完整应用。
- [ ] Reload 补装填动画、弹匣 UI polish、更多武器 / 弹药类型、多武器 / 换武器策略和特殊弹药策略。
- [ ] On-hit 效果补 UI 日志和更细状态特效 polish。
- [ ] 攻击装备成本补消耗品、特殊弹药效果消耗、装备损坏 UI 和修理闭环。
- [ ] 伤害反馈补动画飘字生命周期、详细战斗日志面板、受击 / 攻击动画占位、命中特效和音效占位。

### 6.3 击杀和尸体

- [ ] 尸体掉落补单件耐久状态、掉落随机公式与旧实现完整复核、尸体容器 UI 展示装备来源。
- [ ] 尸体表现补专用尸体姿态 / 动画、美术模型、装备来源 UI 标记和尸体清理表现。
- [ ] 击杀后 AI / combat state / quest / relationship / event feedback 的顺序一致性需要复核。

### 6.4 技能目标和 AOE

- [ ] 技能目标选择补鼠标 / 键盘确认提示和目标选择音效。
- [ ] AOE / 技能目标 LOS 补技能友军伤害实际后果、中心到命中格的旧版边缘细节。
- [ ] Typed targeting policy 补 object target、容器 / 门 / 机关目标和脚本化目标类型。
- [ ] 目标预览 UI 补鼠标 / 键盘确认提示和目标选择音效。

## 7. NPC、AI、阵营和生活模拟

### 7.1 战斗 AI

- [ ] Hostile AI 补丢失目标、重规划、绕障、AP 分配和失败结束回合。
- [ ] NPC reload / weapon policy 补低于最小射程时的后退 / 换位战术、多武器选择、换武器、NPC 特殊弹药策略和 reload 动画 / 反馈。
- [ ] 补 NPC 技能使用、逃跑、治疗、保护友军、呼叫增援。
- [ ] AI debug 补统一 debug panel 展示 polish。

### 7.2 Settlement Life / GOAP

- [ ] Settlement life 补地图 route polish、最终状态美术反馈和截图级动画验收。
- [ ] GOAP / planner 补更多报警 / 服务 executor 的细粒度状态。
- [ ] 在线 / 后台同步补更复杂上线 / 下线冲突策略、跨地图服务产出调度和更完整 HUD / debug 展示。

### 7.3 关系和阵营

- [ ] Relationship scores 补敌对状态动态切换和关系历史。
- [ ] 关系驱动敌对判定补更多对话分支的关系 / 阵营影响，以及敌对状态变化的 UI 提示 polish。
- [ ] 补治疗、雇佣、跟随、队友、护送、敌对转中立等脚本化 NPC 互动。

## 8. 背包、装备、容器和交易

### 8.1 背包

- [ ] 背包上下文菜单补更完整 polish。
- [ ] 数量控制补 Inventory 主面板更多上下文菜单 polish。
- [ ] 物品使用补 buff / debuff、持续效果、任务交付限制和更完整反馈。
- [ ] 拖拽补筛选 / 搜索视图下的拖拽提示、drag preview 和 hover 高亮 polish。
- [ ] 背包容量补更多 UI 展示和极端容量边界复核。

### 8.2 装备

- [ ] 装备槽 tooltip 补属性变化对比和排版 polish。
- [ ] 装备视觉补替换 body region、武器挂点精调和更多装备槽视觉验证。
- [ ] 装备效果补更复杂卸下失败规则、完整 effect runtime / stacking / 持续时间。

### 8.3 容器

- [ ] 容器类型补商店容器、任务容器特化表现。
- [ ] 容器权限补逐件 / 多 stack 工具耐久、NPC 目击 / crime system / 阵营敌对联动和权限预览 polish。
- [ ] 容器 UI 补跨面板拖拽视觉 polish。

### 8.4 交易

- [ ] 交易拖拽补更多跨面板 hover 高亮 polish。
- [ ] 交易权限补对话分支中权限原因展示和更细致的商店权限 UI polish。

## 9. 技能、热栏和进度

- [ ] 角色进度补属性要求显示、升级弹层、更完整派生值展示、属性分配撤销 / 确认策略、详细事件日志、奖励明细弹层和升级动画占位。
- [ ] 技能树补更接近旧版的图形布局、节点连线视觉 polish、前置链路高亮动画、已学 / 可学 / 锁定 / 属性不足 / 点数不足状态视觉 polish 和失败 reason 细分；图形编辑 / 预览优先评估 `GraphEdit` / `GraphNode`，轻量展示可用 `Control._draw()`。
- [ ] 技能效果补堆叠策略、非战斗 modifier 的完整消费点、负面状态、状态 UI polish 和更完整 toggle polish。
- [ ] Hotbar 补更多组数配置、完整快捷键冲突矩阵、多组资源消耗汇总展示和组级状态 UI polish。
- [ ] Observe hotbar 补完整快捷键冲突策略和视觉 polish。

## 10. 任务、对话和剧情动作

### 10.1 对话

- [ ] 对话 resolution preview 和 action 反馈补更完整 UI polish。
- [ ] 对话目标来源补更完整异常态文案。
- [ ] 对话快捷键补菜单内快捷键冲突和更完整诊断日志。
- [ ] 对话 UI 补更完整诊断日志。

### 10.2 任务

- [ ] 补完整 objective 类型、失败 / 替代分支和可追踪目标。
- [ ] Dialogue turn-in 补奖励失败回滚和更完整失败 UI。
- [ ] 任务链奖励补互斥任务、替代分支和更复杂任务链条件。
- [ ] Journal 详情补多分支 / 替代目标状态、更完整失败反馈和更多真实任务数据矩阵。
- [ ] 地图目标 marker 补跨地图显式路线、目标优先级、完成 / 失败反馈和更完整图形 polish。
- [ ] 任务反馈补事件日志、HUD 提醒过渡、奖励动画占位和更完整失败反馈。

## 11. 制作和配方

- [ ] 配方解锁补工作台解锁源、阅读后永久解锁、消耗书籍 / 蓝图和更完整 world flag 产生点。
- [ ] 工具要求补逐件 / 多 stack 工具耐久模型和更完整 durability UI polish。
- [ ] 工作台要求补工作台工具耐久和更完整站点 UI。
- [ ] 制作 AP / 时间消耗补更完整时间表现和 UI 进度条 polish。
- [ ] 拆解补逐件 / 多 stack 工具耐久模型。

## 12. 世界表现、渲染和相机

### 12.1 动作表现队列

- [ ] 移动表现补更严格的“表现结束后再刷新最终 snapshot”动作队列时序；位置插值优先使用 `Tween` 或 `AnimationPlayer`，`WorldActionPresenter` 只负责编排。
- [ ] 攻击表现补真实近战挥击动画、真实远程开火 / 弹道 VFX、更细命中 / 未命中 / 格挡 / 暴击特效、状态 VFX polish、死亡姿态和战斗 HUD 刷新；动画、粒子、飘字和音效优先由 `AnimationTree` / `AnimationPlayer` / `GPUParticles3D` / `Label3D` / `AudioStreamPlayer3D` 承载。
- [ ] 交互表现补真实开门 / 开容器 / 对话 / 交易 / 场景切换动画，以及更多 UI / 地图刷新延后顺序；门、容器、trigger 子场景自行持有动画和音频节点。
- [ ] 表现期间 input blocker 补旧规则下的排队 / 取消策略、自动结束回合策略，以及 quantity modal、drag preview、tooltip 等 UI layer 的完整阻塞矩阵。
- [ ] 刷新时机补攻击、开门、容器 / 对话打开和跨地图切换统一由 action queue 驱动的最终刷新时序。

### 12.2 地图和 Tile 表现

- [ ] World tile instancing 补地面、坡道、悬崖、建筑墙、建筑地板、prop、container、door、trigger 的资源选择；静态重复视觉优先使用 `MultiMeshInstance3D`，交互对象保留独立 `PackedScene` 实例。
- [ ] Prototype / tile set schema 补 canonical orientation、pivot、pick proxy、occluder policy、interaction / upgrade class、wall set、surface set 和加载期校验；schema 应对齐 Godot scene / resource 字段，不再设计独立编辑器格式。
- [ ] Static instance -> dynamic entity 升级补门、柜子 / 箱子、可破坏 prop 的实例句柄、生命周期、状态同步、隐藏 / 替换和回收策略；升级目标优先是独立 `PackedScene` 实例及其脚本。
- [ ] 材质和颜色补 terrain color、wall material、prop tint、容器 tint、角色阵营颜色、选中 / hover 高亮。
- [ ] 碰撞体和 picking 体分离，避免视觉模型、阻挡碰撞、鼠标命中、交互命中互相污染；使用 collision layer / mask、`StaticBody3D`、`Area3D` 和专用 pick proxy。
- [ ] 地图对象 LOD / batch / instance 性能策略用 Godot 原生 MultiMesh 或场景实例实现，并输出 batch / instance / fallback 统计进入 MapVisual 报告和 smoke 诊断。

### 12.3 角色、装备和尸体表现

- [ ] 补模型姿态、移动插值、攻击 / 受击 / 死亡占位动画和更精细朝向来源；优先使用 `AnimationTree` / `AnimationPlayer` 和 scene 内朝向节点。
- [ ] 补真实骨骼 socket、动画绑定、精确美术校准和装备遮挡处理；装备挂接优先使用 Godot 骨骼 attachment / 子节点挂点。
- [ ] 补武器开火 / 挥击反馈、命中特效、换弹 / 攻击动画和手持模型 polish；VFX 优先使用 `GPUParticles3D`、mesh trail 或 scene 化特效资源。
- [ ] 补雾战显隐细节、专用尸体姿态 / 动画、遮挡处理和视觉 polish。

### 12.4 相机、遮挡和 Fog

- [ ] 相机补 occlusion、视觉显隐、多层地图表现、视口可见范围诊断、边界 clamp 视觉验证、多楼层聚焦细节和分辨率变化处理；优先使用 `Camera3D`、`SpringArm3D`、physics ray 和 viewport 信息。
- [ ] Occlusion 补建筑 / 墙体遮挡目标时的淡出、轮廓、选择目标 actor 的遮挡处理；遮挡检测优先使用 `RayCast3D` / physics query，表现使用材质 override 或 shader。
- [ ] Picking 优先级补 object / door / container / trigger 更精细优先级、遮挡处理和视觉 polish；命中源优先来自 physics query 和 collision layer / mask。
- [ ] Fog 补与旧 post-process fog 的视觉等价：探索区透明度、未探索区遮罩、边缘柔化和 mask blend；实现优先用 Godot shader material、`CanvasLayer` 或 `SubViewport`。
- [ ] Fog mask 补相机 / 地图坐标同步、地图切换重建、可见格变化平滑和性能优化；mask 数据可由 core vision 提供，但渲染由 Godot shader / texture 负责。

### 12.5 Debug / Overlay

- [ ] Debug viewer 补完整按钮、动作、过滤、布局、复制 / 过滤和旧命令集。
- [ ] Debug / overlay 补 hover prompt、雾中物体轮廓和已探索但不可见目标的显示策略。

## 13. 游戏 UI、菜单和反馈表现

- [ ] 主菜单和设置补更完整视觉表现，以及 Godot project / window / audio bus 的平台差异处理。
- [ ] HUD 和 overlay 补更完整状态行、战斗布局、反馈 toast / feed、上下文菜单、slot tooltip、冲突策略、统一 modal layer、tooltip / context menu / drag preview 真实视觉 polish；优先使用 Godot `Control`、`Theme`、`PopupMenu`、custom tooltip 和 drag/drop。
- [ ] Inventory 面板补完整上下文项、拆分 polish 和跨面板拖拽视觉 polish；上下文菜单优先使用 `PopupMenu`。
- [ ] Character 面板补更完整排版。
- [ ] Map 面板补更完整图形化地图目标 marker；轻量绘制优先使用 `Control._draw()`，复杂预览可用 `SubViewport`。
- [ ] Journal 面板补更完整失败反馈、更多真实任务条件数据和多分支任务状态。
- [ ] Skills 面板补技能树真实布局 / 连线视觉 polish、前置链路高亮动画和世界目标高亮细节；优先评估 `GraphEdit` / `GraphNode` 或 `Control._draw()`。
- [ ] Trade 面板补更多跨面板 hover 高亮 polish。
- [ ] Container 面板补逐件 / 多 stack 工具耐久和跨面板拖拽视觉 polish。

## 14. 内容工具和 Agent Workflow

- [ ] CLI 补批量修复、安全写回、dry-run、JSON path 定位、引用反查、跨 domain 校验和旧 `content_tools` 输出字段兼容。
- [ ] Agent workflow 文档要求：每个新脚本同步 comment-based help、`tools/agent/README.md` 和 `docs/agent-workflows/*.md`。

## 15. 存档、加载和运行入口

- [ ] 坏档恢复补自动修复策略和更完整恢复 UI。
- [ ] 保存 / 读取继续覆盖新增 runtime 状态：active map、actors、combat、turn、pending、corpse、containers、shops、quests、skills、hotbar、vision、world flags、relationships 和 active skill effects。
- [ ] 地图切换后的保存 / 读取补多段地图链路、跨地图 UI 恢复和坏档恢复策略。
- [ ] 运行入口错误提示补内容加载失败、地图缺失、资产缺失、Godot 版本不对和进入游戏后的错误 UI。

## 16. 验证缺口

### 16.1 现有 Smoke 需扩展

- [ ] `Movement`：跨层楼梯、取消策略和更多复杂重规划细节；增加从 scene 楼梯 / collision / navigation 数据派生 topology 的断言。
- [ ] `PlayerInteraction`：更多复杂重叠目标和视觉 polish；增加 physics ray、collision layer / mask、`Area3D` pick proxy 的断言。
- [ ] `Combat`：高低差 / 楼梯、更多特殊武器、战斗队列 UI 和表现层 polish。
- [ ] `AI`：更复杂重规划、感知丢失细节、更复杂在线 / 离线冲突策略、最终状态美术反馈和截图级动画验收。
- [ ] `InventoryUI`：更完整上下文菜单 polish，并覆盖 `PopupMenu` / 原生 drag/drop 路径。
- [ ] `ContainerUI`：逐件 / 多 stack 工具耐久和更多跨面板拖拽视觉 polish，并覆盖原生 drag/drop 路径。
- [ ] `TradeUI`：更多跨面板 hover 高亮 polish，并覆盖原生 drag/drop 路径。
- [ ] `SkillsUI`：技能树真实布局 polish、链路高亮动画和更完整状态 UI，并覆盖 `GraphEdit` / `GraphNode` 或 `Control._draw()` 实现路径。
- [ ] `JournalUI`：更完整失败反馈、更多真实任务条件数据和多分支任务状态。
- [ ] `Save`：持续覆盖新增 runtime 字段和旧存档迁移。

### 16.2 需要新增或恢复的验证入口

- [ ] UI toggle smoke：键盘打开 / 关闭面板、Esc 关闭优先级、菜单阻塞 gameplay 输入，并断言 `PopupPanel` / `PopupMenu` / `Control.mouse_filter` 等 Godot 原生状态。
- [ ] Targeting smoke：进入技能 / 攻击目标选择、取消、预览、确认。
- [ ] Door 聚合 smoke 补更多真实门模型 / `CollisionShape3D` / `Area3D` / `AnimationPlayer` / `AudioStreamPlayer3D` 表现断言。
- [ ] Map visual smoke 补真实 glTF collision、scene 子节点、collision layer / mask 和 pick proxy 断言。
- [ ] Asset import smoke 补真实 collision、scale / origin 校准规则、Godot import preset、`.import` 和 `ResourceUID` 断言。

## 17. 建议迁移顺序

1. 战斗空间等价：LOS、跨层、AOE、友军伤害、战斗退出和目标预览。
2. 背包 / 容器 / 交易高级 UI：数量弹窗、上下文菜单、拖拽、购物车、详情和失败提示；优先收敛到 Godot `PopupMenu`、`PopupPanel`、`Theme` 和原生 drag/drop。
3. 技能和 hotbar：多槽、快捷键、目标选择、状态堆叠、非战斗 modifier 消费点、cooldown；技能树优先评估 `GraphEdit` / `GraphNode`。
4. 动作表现队列：最终 snapshot 刷新时机、表现截图级验收、quantity / drag / tooltip 等 UI layer 阻塞矩阵；动画和特效优先资源化到 `AnimationPlayer`、`AnimationTree`、`Tween` 和 `GPUParticles3D`。
5. 地图表现和门：地图对象资源实例化、门、楼层、遮挡、hover outline、雾战影响；优先把门、容器、入口和 trigger 场景化为 Godot 子场景。
6. NPC life / GOAP：更复杂在线 / 离线冲突策略、最终状态美术反馈和截图级动画验收。
7. 内容工具：补 content CLI、批量修复、引用反查、安全写回和 agent workflow 文档；资源导入审计只验证 Godot import / resource 状态，不另建导入权威。

## 18. 阶段提交与验收规则

- 每个阶段只提交本阶段相关文件；不要混入本地地图调整，除非阶段目标明确包含该地图。
- 每个功能必须明确权威层：内容读写进 `godot/scripts/data`，玩法结果进 `godot/scripts/core`，输入编排进 `godot/scripts/app`，表现进 `godot/scripts/world`，UI 展示进 `godot/scripts/ui`。
- 涉及 UI、动画、音频、碰撞、导航、资源导入、地图 scene 的任务，交付前需要说明使用了哪些 Godot 原生节点 / 资源 / editor 工作流，避免新增平行自研系统。
- 每个阶段至少跑对应 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>`；大阶段跑 `-Scenario All`。
- 涉及 Godot 工程、地图、数据或旧栈边界时跑 `cmd /c run_godot_validate.bat`。
- 文档阶段无需跑全量游戏 smoke，但需要检查 markdown 和 git diff，确认未误改功能文件。
