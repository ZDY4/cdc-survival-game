# Test Godot Profile Workflow

## Purpose

这个 workflow 负责 Godot game 侧的 runtime profiling：重复真实运行时操作，记录帧耗时、FPS、节点/渲染计数、路径搜索指标和关键 GDScript 函数耗时，用于发现随操作次数增长的性能退化。

## When To Use

- 用户描述帧率随着重复移动、交互、等待或战斗逐渐下降。
- smoke 测试能通过，但需要定位哪条 runtime 链路变慢。
- 修改 `game_root`、输入控制器、回合 runner、world sync、HUD refresh、actor view 或 pathfinding 后，需要量化性能趋势。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/test-godot-profile.ps1 -Scenario MovementClickRepeat -Iterations <n>`。
2. 查看脚本输出的 summary，重点关注 `first_half_*` 与 `last_half_*` 指标是否明显扩大。
3. 打开 `.local/agent-smoke/godot_profile/<timestamp>/<Scenario>.profile.json`，查看 `function_summary` 中 `*.total_ms` / `*.avg_ms` / `*.max_ms` 的热点函数。
4. 若 profiling 显示退化，优先结合 `node_count`、`render_count`、`pathfinding_time_ms` 和热点函数判断是节点/渲染泄漏、路径搜索、输入拾取、runner/snapshot 深拷贝还是 world sync/HUD refresh 问题。

## Notes

- Godot 命令解析优先级为：显式 `-Godot` 参数、环境变量 `GODOT`、PATH 中的 `godot` / `godot.exe` / `godot.cmd`、`D:\godot\godot.cmd`。
- 当前默认场景是 `MovementClickRepeat`，会加载真实 `godot/scenes/game/game_root.tscn`，在启动地图上发真实 Godot 鼠标输入事件，等待玩家控制角色移动到目标格，再重复。
- 默认以可见 Godot 窗口运行，因为输入事件、相机、physics picking 和帧循环更接近交互 runtime；需要 headless 环境时可加 `-Headless`。
- 当前启动 runtime 默认地图是 `survivor_outpost_01`。`-Map` 参数用于校验期望地图；后续若启动参数支持任意地图，可复用同一入口扩展。
- 该 workflow 用于性能趋势和热点定位，不替代 `test-godot-game.ps1` 的正确性 smoke。
