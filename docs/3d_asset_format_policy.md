# 3D 资产格式规范

本项目仓库内的正式 3D 资产格式固定为 `.gltf + .bin + 外部贴图`。

正式内容规则：

- `assets/` 下正式入库的 3D 资产主文件统一使用 `.gltf`
- 几何、骨骼或动画使用外部 buffer 时，配套产物统一为 `.bin`
- 贴图保持外部文件引用，不内嵌到 `.gltf`
- `data/` 和共享 Rust schema 中所有正式 3D 资产路径只允许引用 `.gltf`
- `.glb` 和 `.fbx` 只允许作为临时导入源，不允许作为正式内容引用进入仓库 schema

运行时和工具链约定：

- 动画、骨骼和场景层级继续通过 glTF 承载
- Bevy 运行时继续使用现有 `GltfAssetLabel` 与 `AssetServer` 加载 `.gltf`
- placeholder bake、preview placeholder、world tile 等工具默认输出 `.gltf`，并将 `.bin` 视为标准配套产物

AI 修改边界：

- AI 允许直接修改 `.gltf` 的结构层、引用层和元数据层
- `.bin` 中的二进制几何、复杂动画采样和原始 buffer 字节不作为直接 patch 目标
- 若外部 DCC 或生成流程产出 `.fbx` / `.glb`，必须先转换为 `.gltf + .bin + 外部贴图` 再进入正式资产目录
