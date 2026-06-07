# 3D 资产格式规范

本项目仓库内的正式 3D 资产格式固定为 `.gltf + .bin + 外部贴图`。

目录职责：

- `godot/assets/` 是 Godot 运行时权威资产目录；地图 scene、GDScript、Godot smoke 和运行时加载路径必须使用 `res://assets/...`
- 根目录 `assets/` 只作为源资产池或迁移期备份，不作为 Godot 运行时引用来源
- 从根目录 `assets/` 更新运行时资产时，必须同步到 `godot/assets/` 下相同相对目录，并让 Godot 生成 / 更新对应 `.import` 和 uid 信息
- 运行验证以 `godot/assets/` 为准：`Scene` smoke 负责 glTF / `.bin` / `.import` / `.uid` 完整性，`mainline_migration_guard.gd` 负责阻止运行脚本、scene 和工具入口引用根目录 `assets/`

正式内容规则：

- `godot/assets/` 下正式入库的 3D 资产主文件统一使用 `.gltf`
- 几何、骨骼或动画使用外部 buffer 时，配套产物统一为 `.bin`
- 贴图保持外部文件引用，不内嵌到 `.gltf`
- `data/` 和 Godot 内容加载层中所有正式 3D 资产路径只允许引用 `.gltf`
- `.glb` 和 `.fbx` 只允许作为临时导入源，不允许作为正式内容引用进入仓库 schema

运行时和工具链约定：

- 动画、骨骼和场景层级继续通过 glTF 承载
- Godot 运行时和 editor 预览通过导入后的 glTF 资源加载 `.gltf`
- placeholder bake、preview placeholder、world tile 等工具默认输出 `.gltf`，并将 `.bin` 视为标准配套产物

AI 修改边界：

- AI 允许直接修改 `.gltf` 的结构层、引用层和元数据层
- `.bin` 中的二进制几何、复杂动画采样和原始 buffer 字节不作为直接 patch 目标
- 若外部 DCC 或生成流程产出 `.fbx` / `.glb`，必须先转换为 `.gltf + .bin + 外部贴图` 再进入正式资产目录
