extends Node
## EnemySystem - 敌人管理系统
## 负责加载敌人数据、生成敌人、管理战斗中的敌人实例

class_name EnemySystem

# ========== 信号 ==========
signal enemy_spawned(enemy_id: String, enemy_instance: Node)
signal enemy_died(enemy_id: String, killer_id: String)
signal enemy_damaged(enemy_id: String, damage: int, current_hp: int)
signal enemy_healed(enemy_id: String, amount: int, current_hp: int)
signal loot_dropped(enemy_id: String, loot: Array)

# ========== 数据 ==========
var enemy_database: Dictionary = {}  # enemy_id -> EnemyData
var active_enemies: Dictionary = {}  # instance_id -> enemy_instance

# ========== 生成设置 ==========
var spawn_cooldown: float = 0.5  # 生成冷却时间
var _last_spawn_time: float = 0.0

# ========== 初始化 ==========
func _ready():
	print("[EnemySystem] 敌人系统初始化")
	_load_enemy_database()

func _load_enemy_database():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		enemy_database = data_manager.get_data("enemies")
		print("[EnemySystem] 从DataManager加载了 %d 个敌人数据" % enemy_database.size())

# ========== 敌人数据查询 ==========

## 获取敌人数据
func get_enemy_data(enemy_id: String) -> EnemyData:
	var data = enemy_database.get(enemy_id, {})
	if data.is_empty():
		return null
	
	var enemy_data = EnemyData.new()
	enemy_data.deserialize(data)
	return enemy_data

## 获取所有敌人ID
func get_all_enemy_ids() -> Array:
	return enemy_database.keys()

## 获取指定等级的可生成敌人
func get_spawnable_enemies(player_level: int, location: String = "") -> Array:
	var result = []
	
	for enemy_id in enemy_database.keys():
		var data = enemy_database[enemy_id]
		var min_level = data.get("min_spawn_level", 1)
		var max_level = data.get("max_spawn_level", 99)
		var spawn_locations = data.get("spawn_locations", [])
		
		# 检查等级
		if player_level < min_level or player_level > max_level:
			continue
		
		# 检查地点（如果指定）
		if not location.is_empty() and not spawn_locations.is_empty():
			if not spawn_locations.has(location):
				continue
		
		result.append(enemy_id)
	
	return result

## 随机选择敌人（根据权重）
func select_random_enemy(enemy_ids: Array) -> String:
	if enemy_ids.is_empty():
		return ""
	
	var total_weight = 0
	var weights = []
	
	for enemy_id in enemy_ids:
		var weight = enemy_database.get(enemy_id, {}).get("spawn_weight", 10)
		total_weight += weight
		weights.append({"id": enemy_id, "weight": weight})
	
	if total_weight <= 0:
		return enemy_ids[randi() % enemy_ids.size()]
	
	var random_value = randi() % total_weight
	var current_weight = 0
	
	for item in weights:
		current_weight += item.weight
		if random_value < current_weight:
			return item.id
	
	return enemy_ids[0]

# ========== 敌人生成 ==========

## 在指定位置生成敌人
## @param enemy_id: 敌人ID
## @param position: 生成位置
## @param difficulty_scale: 难度倍率（1.0 = 正常）
func spawn_enemy(enemy_id: String, position: Vector2 = Vector2.ZERO, difficulty_scale: float = 1.0) -> Node:
	# 检查冷却
	var current_time = Time.get_time_dict_from_system()["second"]
	if current_time - _last_spawn_time < spawn_cooldown:
		return null
	
	var enemy_data = get_enemy_data(enemy_id)
	if not enemy_data:
		push_error("[EnemySystem] 敌人数据不存在: %s" % enemy_id)
		return null
	
	# 创建敌人实例（这里简化处理，实际需要实例化场景）
	var instance_id = "%s_%d" % [enemy_id, Time.get_ticks_msec()]
	var enemy_instance = _create_enemy_instance(enemy_data, instance_id, difficulty_scale)
	
	if enemy_instance:
		enemy_instance.position = position
		active_enemies[instance_id] = enemy_instance
		_last_spawn_time = current_time
		
		enemy_spawned.emit(enemy_id, enemy_instance)
		print("[EnemySystem] 生成敌人: %s (实例ID: %s)" % [enemy_id, instance_id])
	
	return enemy_instance

## 批量生成敌人
func spawn_enemy_group(enemy_id: String, count: int, center_position: Vector2, radius: float = 100.0) -> Array:
	var spawned = []
	
	for i in range(count):
		var angle = randf() * 2 * PI
		var distance = randf() * radius
		var offset = Vector2(cos(angle), sin(angle)) * distance
		var enemy = spawn_enemy(enemy_id, center_position + offset)
		if enemy:
			spawned.append(enemy)
	
	return spawned

## 根据玩家等级生成适合的敌人
func spawn_appropriate_enemy(player_level: int, position: Vector2, location: String = "") -> Node:
	var spawnable = get_spawnable_enemies(player_level, location)
	if spawnable.is_empty():
		return null
	
	var enemy_id = select_random_enemy(spawnable)
	return spawn_enemy(enemy_id, position)

func _create_enemy_instance(enemy_data: EnemyData, instance_id: String, difficulty_scale: float) -> Node:
	# 这里应该实例化实际的敌人场景
	# 简化版本：创建一个基础Node并附加数据
	var enemy = Node2D.new()
	enemy.name = instance_id
	
	# 存储敌人数据
	enemy.set_meta("enemy_data", enemy_data)
	enemy.set_meta("instance_id", instance_id)
	enemy.set_meta("current_hp", int(enemy_data.get_max_hp() * difficulty_scale))
	enemy.set_meta("max_hp", int(enemy_data.get_max_hp() * difficulty_scale))
	
	return enemy

# ========== 战斗接口 ==========

## 敌人受到伤害
func damage_enemy(instance_id: String, damage: int, attacker_id: String = "") -> int:
	if not active_enemies.has(instance_id):
		return 0
	
	var enemy = active_enemies[instance_id]
	var current_hp = enemy.get_meta("current_hp", 0)
	var actual_damage = mini(damage, current_hp)
	
	current_hp -= actual_damage
	enemy.set_meta("current_hp", current_hp)
	
	enemy_damaged.emit(instance_id, actual_damage, current_hp)
	
	if current_hp <= 0:
		_kill_enemy(instance_id, attacker_id)
	
	return actual_damage

## 治疗敌人
func heal_enemy(instance_id: String, amount: int) -> int:
	if not active_enemies.has(instance_id):
		return 0
	
	var enemy = active_enemies[instance_id]
	var max_hp = enemy.get_meta("max_hp", 0)
	var current_hp = enemy.get_meta("current_hp", 0)
	
	var healed = mini(amount, max_hp - current_hp)
	current_hp += healed
	enemy.set_meta("current_hp", current_hp)
	
	enemy_healed.emit(instance_id, healed, current_hp)
	return healed

## 杀死敌人
func _kill_enemy(instance_id: String, killer_id: String = ""):
	if not active_enemies.has(instance_id):
		return
	
	var enemy = active_enemies[instance_id]
	var enemy_data = enemy.get_meta("enemy_data")
	
	# 掉落战利品
	if enemy_data:
		var loot = enemy_data.roll_loot()
		if not loot.is_empty():
			loot_dropped.emit(instance_id, loot)
	
	enemy_died.emit(instance_id, killer_id)
	
	# 延迟移除
	enemy.queue_free()
	active_enemies.erase(instance_id)
	
	print("[EnemySystem] 敌人死亡: %s" % instance_id)

## 移除所有敌人
func clear_all_enemies():
	for instance_id in active_enemies.keys():
		active_enemies[instance_id].queue_free()
	active_enemies.clear()
	print("[EnemySystem] 清除所有敌人")

# ========== 查询接口 ==========

## 获取活跃敌人数量
func get_active_enemy_count() -> int:
	return active_enemies.size()

## 获取敌人当前HP
func get_enemy_hp(instance_id: String) -> int:
	if not active_enemies.has(instance_id):
		return 0
	return active_enemies[instance_id].get_meta("current_hp", 0)

## 获取敌人数据
func get_active_enemy_data(instance_id: String) -> EnemyData:
	if not active_enemies.has(instance_id):
		return null
	return active_enemies[instance_id].get_meta("enemy_data")

## 获取范围内的敌人
func get_enemies_in_range(center: Vector2, radius: float) -> Array:
	var result = []
	for instance_id in active_enemies.keys():
		var enemy = active_enemies[instance_id]
		if enemy.position.distance_to(center) <= radius:
			result.append(instance_id)
	return result

# ========== 存档/读档 ==========

func serialize_active_enemies() -> Array:
	var data = []
	for instance_id in active_enemies.keys():
		var enemy = active_enemies[instance_id]
		var enemy_data = enemy.get_meta("enemy_data")
		
		data.append({
			"instance_id": instance_id,
			"enemy_id": enemy_data.id if enemy_data else "",
			"position": {"x": enemy.position.x, "y": enemy.position.y},
			"current_hp": enemy.get_meta("current_hp", 0),
			"max_hp": enemy.get_meta("max_hp", 0)
		})
	return data

func deserialize_active_enemies(data: Array):
	clear_all_enemies()
	
	for item in data:
		var enemy_id = item.get("enemy_id", "")
		var position = Vector2(item.get("position", {}).get("x", 0), item.get("position", {}).get("y", 0))
		var enemy = spawn_enemy(enemy_id, position)
		
		if enemy:
			enemy.set_meta("current_hp", item.get("current_hp", 0))
			enemy.set_meta("max_hp", item.get("max_hp", 0))
