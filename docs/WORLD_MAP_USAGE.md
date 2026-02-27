# 大地图系统使用说明

## 文件结构

```
scenes/ui/
├── world_map.tscn          # 大地图主场景
├── world_map.gd            # 大地图逻辑脚本

modules/map/
├── map_location.tscn       # 可拖放的地点标记 Actor
├── map_location.gd         # 地点标记逻辑

data/json/
└── map_locations.json      # 地点配置表
```

## 工作流程

### 1. 准备地图背景

放置地图背景图到 `assets/textures/map/world_map.jpg`

### 2. 在 Godot 编辑器中布置地点

1. 打开 `scenes/ui/world_map.tscn`
2. 从文件系统拖入 `modules/map/map_location.tscn` 到场景中
3. 在 Inspector 面板中设置：
   - **Location Id**: 选择对应的地点 ID（如 `safehouse`, `hospital`）
   - **Position**: 在 2D 视图中拖动到合适位置
4. 重复步骤 2-3，布置所有地点

### 3. 配置地点数据

编辑 `data/json/map_locations.json`：

```json
{
  "location_id": {
    "id": "location_id",
    "name": "地点名称",
    "description": "地点描述",
    "danger_level": 0-5,
    "scene_path": "res://scenes/locations/xxx.tscn",
    "icon": "res://assets/icons/location_xxx.png",
    "default_unlocked": true/false
  }
}
```

### 4. 在游戏中打开地图

```gdscript
# 在游戏场景中添加 WorldMap
var world_map = preload("res://scenes/ui/world_map.tscn").instantiate()
get_tree().root.add_child(world_map)
world_map.show_map()

# 监听事件
world_map.location_selected.connect(_on_location_selected)
world_map.travel_confirmed.connect(_on_travel_confirmed)
world_map.map_closed.connect(_on_map_closed)
```

### 5. 从地点场景打开地图

在安全屋或其他地点添加"查看地图"按钮：

```gdscript
func _on_map_button_pressed():
	var world_map = preload("res://scenes/ui/world_map.tscn").instantiate()
	add_child(world_map)
	world_map.show_map()
```

## MapLocation 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| location_id | String | 地点唯一标识符，对应配置表中的键 |
| icon_normal | Texture2D | 正常状态图标 |
| icon_hover | Texture2D | 悬停状态图标 |
| icon_disabled | Texture2D | 未解锁状态图标 |

## 地点配置字段

| 字段 | 类型 | 说明 |
|------|------|------|
| id | String | 地点 ID |
| name | String | 显示名称 |
| description | String | 地点描述 |
| danger_level | int | 危险等级 0-5 |
| scene_path | String | 地点场景文件路径 |
| icon | String | 图标路径 |
| default_unlocked | bool | 是否默认解锁 |

## 注意事项

1. **图标资源**：需要准备地点图标，或使用默认图标
2. **坐标系统**：地点位置使用像素坐标，基于地图背景图尺寸
3. **解锁机制**：未解锁的地点会显示为灰色半透明，无法点击
4. **数据分离**：地点数据统一在 JSON 中管理，便于策划调整
