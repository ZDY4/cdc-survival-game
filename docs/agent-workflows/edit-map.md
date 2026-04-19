# Edit Map Workflow

## Scope

适用于：

- 修改现有地图
- 新增地图
- 调整格子、对象、入口、层级、AI spawn 相关配置

## Primary Files

- `data/maps/*.json`

常见依赖：

- `data/overworld/*.json`
- `data/world_tiles/*.json`
- `data/characters/*.json`

## Agent Steps

1. 定位目标 map 文件。
2. 先读取地图摘要、关键入口和当前校验状态。
3. 修改 JSON。
4. 跑最小校验。
5. 输出本次操作摘要。
6. 默认要求再用 `bevy_map_editor` 做空间复核。

## Validation

当前优先使用：

- `cargo run -p content_tools -- locate map <id>`
- `cargo run -p content_tools -- summarize map <id>`
- `cargo run -p content_tools -- references map <id>`
- `cargo run -p content_tools -- format map <id>`
- `cargo run -p content_tools -- validate map <id>`

保底编译基线：

- `cargo check -p bevy_map_editor -p content_tools`

如需进入 editor 复核或手工精修：

- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Map <id>`

## Review Policy

地图改动默认不是“改完即结束”。

必须明确说明：

- 改了哪些对象/格子/入口
- 是否影响 selected map 的可达性或诊断
- 是否建议打开 `bevy_map_editor` 复核
