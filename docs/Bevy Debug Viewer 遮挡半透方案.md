Bevy Debug Viewer 遮挡半透方案
Summary
目标是在现有 3D bevy_debug_viewer 中，当“当前选中的玩家角色”被场景物体挡住时，让挡在相机与角色之间的静态物体立即切换为半透明；解除遮挡后立即恢复不透明。

默认规则已经定死：

遮挡目标：优先 selected_actor，且必须是玩家；若当前未选中玩家，则回退到当前楼层第一个 ActorSide::Player
透明变化：立即切换，不做渐变
生效范围：只对当前 current_level 的静态世界物体生效，不影响 actor、UI、grid overlay、路径线
不新增跨 crate 公共接口；改动只落在 viewer 内部，主要集中在 render.rs、geometry.rs、state.rs。

Key Changes
1. 明确“哪些物体会变透明”
纳入遮挡判定的对象：
map_cells 里实际生成了立方体体积的阻挡地形
static_obstacles 生成的障碍盒体
map_objects 生成的建筑/拾取/交互物/刷怪点盒体
不纳入的对象：
地面 tile
actor 胶囊体
hover/path/current-turn 的 gizmo overlay
文本标签和 UI
这样能保证“只让真正挡视线的静态体积退让”，不会把整个场景都洗成半透明。
2. 为静态 world visual 增加可追踪元数据
当前 rebuild_static_world 只保存 Entity 列表；需要改成保存静态可视对象记录，至少包含：
entity
material handle
base_color
base_alpha
kind/category
world-space AABB 或等价的中心点 + 半尺寸
currently_faded
floor tile 与 occluder 分开记录：
floor tile 继续只做普通静态实体
只有 occluder 进入“可半透更新集合”
这样后续每帧只更新候选 occluder 的材质透明度，不用重建静态世界。
3. 遮挡判定算法固定为“相机到角色头顶的线段与 AABB 相交”
目标点使用玩家角色头顶附近位置：
直接复用/对齐现有 label 用的 actor head world position
比角色中心更符合“是否看得见角色”的直觉
射线来源使用当前相机世界位置。
对每个 occluder，做线段 vs AABB 相交测试：
仅当 occluder 位于目标角色之前时才算遮挡
仅当前楼层参与判定
允许多个 occluder 同时命中并一起半透
几何工具放在 geometry.rs：
目标角色解析函数
world-space AABB 构造/辅助
线段与 AABB 相交测试
如果当前没有有效玩家目标，或目标不在当前楼层，则清空所有半透状态。
4. 材质切换策略固定为“直接改 alpha + alpha_mode”
遮挡时：
把 occluder 材质 alpha_mode 切到 Blend
把 base_color.alpha 改成固定半透值
不遮挡时：
恢复原始 base_color
恢复 alpha_mode = Opaque
默认透明度直接固定，不按类别分不同值，避免第一版规则过多：
推荐统一目标 alpha：0.28
如果后续需要细化，再按 Building / Obstacle / Interactive 分层，但本版不引入额外策略分叉。
5. 系统接入与刷新顺序
新增独立系统，例如 update_occluding_world_visuals
放在相机更新之后、标签同步之前：
先得到当前相机位置
再算谁挡住玩家
再更新材质和标签显示
静态 world 重建时同步刷新 occluder 元数据：
map_id / current_level / topology_version 变化时重建
重建后默认全部恢复为不透明
动态 actor 不需要为这个功能改材质或 render layer。
Test Plan
几何单测：
线段与 AABB 相交时返回命中
线段穿过 occluder 且 occluder 在 actor 前方时判定为遮挡
occluder 在 actor 后方时不判定为遮挡
当前没有玩家目标时不返回 occluder 集合
viewer 层单测：
selected_actor 为玩家时优先使用它
selected_actor 不是玩家时回退到当前楼层第一个 ActorSide::Player
静态 world 重建后 occluder 元数据只包含非地面遮挡体
手动 smoke test：
建筑或障碍挡住玩家时，挡住的盒体立即半透
玩家走出遮挡后，物体立即恢复不透明
多个物体同时挡住时都会半透
切层后只处理当前层 occluder
没有玩家目标或玩家不在当前层时，所有物体保持不透明
验证命令：
rustfmt --check 针对 viewer 改动文件
cargo check -p bevy_debug_viewer
cargo test -p bevy_debug_viewer
当前已知风险：
workspace 现有 game_core 编译错误会阻塞完整 cargo check/test，需要先清掉工作区已有问题再做最终验证
Assumptions
第一版只做“静态盒体 occluder 半透”，不处理 actor 挡 actor。
第一版只对“当前选中的玩家 / 回退玩家”做遮挡处理，不扩展到所有友方或所有玩家。
第一版采用立即切换透明度，不做时间插值、闪烁或描边混合效果。
第一版统一透明度为固定值，不按对象类型区分不同半透等级。
地面 tile 不参与遮挡半透，避免整个地图大面积频繁进入透明态。