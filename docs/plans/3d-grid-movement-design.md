# 3D网格移动系统设计文档

> **日期:** 2026-03-01  
> **目标:** 将CDC生存游戏改为横屏3D项目，实现基于网格的角色移动系统

---

## 需求规格

### 核心需求
1. **3D项目 + 横屏**: 视口改为1920×1080横屏
2. **玩家角色**: 进入游戏时自动生成，使用2D Sprite并始终正对相机
3. **点击移动**: 鼠标/触屏点击地面，角色移动到对应网格点
4. **网格移动**: 1米×1米网格，一格一格平滑移动
5. **寻路支持**: A*算法，自动计算可行走路径

### 交互需求
1. **相机缩放**: 双指缩放（移动端）+ 鼠标滚轮缩放（PC端）
2. **路径预览**: PC端鼠标悬浮时显示从角色到鼠标点的路径
3. **等距视角**: 固定45度俯角，斜45度水平角度

---

## 技术架构

### 系统模块

```
GridMovementSystem (Autoload)
├── GridNavigator - A*寻路算法
├── GridMovement - 网格移动控制
└── GridWorld - 网格世界管理

PlayerController3D (场景组件)
├── CharacterBody3D - 3D物理体
├── Sprite3D - 2D角色精灵（Billboard模式）
└── GridMovementAgent - 移动代理

CameraController3D (场景组件)
├── Camera3D - 3D相机
├── IsometricController - 等距视角控制
└── ZoomController - 缩放控制

GridInteraction (输入处理)
├── RaycastHandler - 地面点击检测
├── PathPreview - 路径预览显示
└── InputHandler - 输入事件处理
```

### 数据流

```
用户输入
    ↓
GridInteraction (检测点击/悬浮位置)
    ↓
GridNavigator (计算路径)
    ↓
GridMovement (执行移动，一格一格)
    ↓
PlayerController3D (更新位置)
    ↓
EventBus (发布移动事件)
```

---

## 核心类设计

### GridNavigator (寻路)
```gdscript
class_name GridNavigator
extends RefCounted

const GRID_SIZE := 1.0

func find_path(start: Vector3, end: Vector3, grid_world: GridWorld) -> Array[Vector3]:
    # A*算法实现
    pass

func get_neighbors(pos: Vector3, grid_world: GridWorld) -> Array[Vector3]:
    # 获取相邻可通行网格
    pass
```

### GridMovement (移动控制)
```gdscript
class_name GridMovement
extends Node

signal movement_started(path: Array[Vector3])
signal step_completed(grid_pos: Vector3)
signal movement_finished
signal movement_cancelled

@export var step_duration := 0.4  # 每格移动时间

func move_along_path(path: Array[Vector3]) -> void:
    # 沿路径一格一格移动
    pass

func cancel_movement() -> void:
    # 取消当前移动
    pass
```

### PlayerController3D (玩家控制)
```gdscript
class_name PlayerController3D
extends CharacterBody3D

@onready var sprite: Sprite3D
@onready var movement: GridMovement

func _ready() -> void:
    # 初始化Sprite3D为Billboard模式
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func move_to_grid_position(grid_pos: Vector3) -> void:
    # 请求移动到网格位置
    pass
```

### CameraController3D (相机控制)
```gdscript
class_name CameraController3D
extends Node3D

@export var min_zoom := 10.0
@export var max_zoom := 50.0
@export var zoom_speed := 2.0

func _input(event: InputEvent) -> void:
    # 处理滚轮和双指缩放
    pass

func _process(delta: float) -> void:
    # 平滑跟随玩家
    pass
```

### PathPreview (路径预览)
```gdscript
class_name PathPreview
extends Node3D

@onready var line_renderer: MeshInstance3D

func show_path(path: Array[Vector3]) -> void:
    # 显示路径线条
    pass

func hide_path() -> void:
    # 隐藏路径
    pass
```

---

## 场景结构

### game_world_3d.tscn
```
Node3D (GameWorld3D)
├── DirectionalLight3D (主光源)
├── CameraController3D
│   └── Camera3D
├── GridFloor (网格地面)
│   └── StaticBody3D
│       └── CollisionShape3D (Plane)
├── PlayerController3D
│   ├── Sprite3D (角色Sprite)
│   └── CollisionShape3D
├── PathPreview (路径预览)
└── GridObstacles (障碍物)
    ├── StaticBody3D (障碍1)
    └── ...
```

---

## 配置文件更新

### project.godot 变更
```ini
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[input]
zoom_in={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"button_index":4,...)]
}
zoom_out={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"button_index":5,...)]
}
```

### Autoloads 新增
```ini
GridMovementSystem="*res://systems/grid_movement_system.gd"
```

---

## 实现计划

详见: [3D网格移动系统实施计划](3d-grid-movement-implementation-plan.md)

---

## 测试要点

1. **网格对齐**: 确保角色始终对齐到1米网格
2. **寻路准确性**: 测试复杂地形的寻路
3. **平滑移动**: 验证插值动画流畅度
4. **输入响应**: 测试鼠标、触屏、滚轮输入
5. **路径预览**: 验证悬浮路径显示正确
6. **性能**: 测试大量网格时的性能

---

## 与现有系统集成

### EventBus 事件
- `GRID_MOVEMENT_STARTED` - 移动开始
- `GRID_MOVEMENT_STEP` - 完成一格移动
- `GRID_MOVEMENT_FINISHED` - 移动完成

### GameState 数据
- `player_grid_position: Vector3` - 玩家网格坐标
- `is_moving: bool` - 是否正在移动

### 保存系统
- 保存/加载玩家网格位置
- 保存相机缩放级别

---

## 视觉规格

### 相机设置
- **位置**: (20, 20, 20) 相对玩家
- **旋转**: (-45, 45, 0) 度
- **投影**: 正交投影（等距风格）
- **初始大小**: 20单位

### 角色Sprite
- **类型**: Sprite3D
- **Billboard**: 启用（始终正对相机）
- **透明**: 启用Alpha
- **尺寸**: 根据网格比例调整

### 网格可视化
- **网格线**: 可选显示，辅助调试
- **网格颜色**: 半透明灰色
- **目标标记**: 点击位置显示高亮

---

## 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 2D转3D兼容性问题 | 高 | 逐步迁移，保留2D场景作为备选 |
| 性能问题 | 中 | 使用对象池，LOD优化 |
| 寻路算法复杂度 | 中 | 限制地图大小，使用简单的A* |
| 输入冲突 | 低 | 清晰的输入优先级处理 |

---

## 验收标准

- [ ] 游戏以横屏1920×1080运行
- [ ] 进入游戏自动生成玩家角色
- [ ] 角色是2D Sprite且始终正对相机
- [ ] 点击地面角色移动到对应网格
- [ ] 移动基于1米网格，一格一格平滑移动
- [ ] 支持寻路，自动绕过障碍物
- [ ] 支持双指缩放和鼠标滚轮缩放
- [ ] PC端悬浮显示路径预览
- [ ] 现有生存系统正常工作

---

**状态:** 设计完成，等待实施计划
