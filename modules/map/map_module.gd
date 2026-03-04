extends BaseModule
# MapModule - 地图模块
# 数据从 DataManager 加载

signal travel_started(from: String, to: String)
signal travel_completed(location_id: String)
signal location_unlocked(location_id: String, location_data: Dictionary)
signal path_calculated(path_data: Dictionary)

# 地图数据缓存（从 DataManager 加载）
var _connections: Dictionary = {}
var _distances: Dictionary = {}
var _risks: Dictionary = {}


func _get_connections() -> Dictionary:
	return _connections


func _get_distances() -> Dictionary:
	return _distances


func _get_risks() -> Dictionary:
	return _risks


func _ready():
	print("[MapModule] 地图模块已初始化")
	_load_map_data_from_manager()


func _load_map_data_from_manager():
	var dm = get_node_or_null("/root/DataManager")
	if dm:
		_connections = dm.get_map_connections()
		_distances = dm.get_map_distances()
		_risks = dm.get_map_risks()

	if _connections.is_empty() or _distances.is_empty() or _risks.is_empty():
		push_warning("[MapModule] 无法从 DataManager 加载地图数据")


# ===== 旅行 =====


func travel_to(location_id: String) -> bool:
	var gs = get_node("/root/GameState")
	if not gs:
		return false

	# 检查是否可以移动（负重检查）
	if CarrySystem and not CarrySystem.can_move():
		DialogModule.show_dialog("你负重太重了，几乎无法移动！先丢弃一些物品。", "提示", "")
		return false

	var current = gs.player_position
	var locations = _get_location_data()

	if not locations.has(location_id) or location_id == current:
		return false

	# 计算移动消耗（时间和食物）
	var travel_cost = _calculate_travel_cost(current, location_id)

	# 检查食物是否足够
	var food_required = travel_cost.food_cost
	if not InventoryModule.has_item("food_canned", food_required):
		DialogModule.show_dialog("食物不足！需要 %d 个罐头才能到达该地点。" % food_required, "提示", "")
		return false

	# 消耗食物
	InventoryModule.remove_item("food_canned", food_required)

	travel_started.emit(current, location_id)

	# 应用移动消耗
	_apply_travel_costs(travel_cost)

	# 切换场景
	var scene_path = locations[location_id].scene_path
	get_tree().change_scene_to_file(scene_path)

	# 更新位置
	gs.travel_to(location_id)
	travel_completed.emit(location_id)

	print(
		(
			"[MapModule] 移动完成: %s -> %s (消耗时间: %.1f小时, 食物: %d)"
			% [current, location_id, travel_cost.time_hours, food_required]
		)
	)
	return true


## 计算移动消耗（时间和食物，与距离成正比）
func _calculate_travel_cost(from: String, to: String) -> Dictionary:
	var base_distance = _get_travel_distance(from, to)

	# 获取生存状态修正
	var survival_system = get_node_or_null("/root/SurvivalStatusSystem")
	var movement_modifiers = {"speed_mult": 1.0}
	if survival_system:
		var mods = survival_system.get_movement_modifiers()
		movement_modifiers.speed_mult = mods.get("speed_mult", 1.0)

	# 负重影响
	var carry_penalty = 1.0
	if CarrySystem:
		carry_penalty = CarrySystem.get_movement_penalty()

	# 计算实际时间（小时）
	var actual_time = base_distance / movement_modifiers.speed_mult * carry_penalty

	# 夜间增加时间
	if GameState and GameState.is_night():
		actual_time *= 1.2

	# 计算食物消耗：每2小时消耗1个食物
	var food_cost = maxi(1, int(actual_time / 2.0))

	# 计算体力消耗
	var stamina_cost = int(actual_time * 8)

	# 计算风险（基于两地的平均风险等级）
	var base_risk = (_get_risks().get(from, 0) + _get_risks().get(to, 0)) / 2.0
	var encounter_chance = minf(base_risk * 0.03, 0.25)  # 最高25%

	return {
		"from": from,
		"to": to,
		"distance": base_distance,
		"time_hours": actual_time,
		"food_cost": food_cost,
		"stamina_cost": stamina_cost,
		"encounter_chance": encounter_chance,
		"risk_level": base_risk
	}


func _apply_travel_costs(path_cost: Dictionary):
	# 消耗时间
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.advance_hours(path_cost.time_hours)

	# 消耗体力
	if GameState:
		GameState.player_stamina = maxi(0, GameState.player_stamina - path_cost.stamina_cost)

	# 根据风险触发遭遇
	if randf() < path_cost.encounter_chance:
		_trigger_travel_encounter(path_cost.risk_level)


func _trigger_travel_encounter(risk_level: float):
	var encounter_system = get_node_or_null("/root/EncounterSystem")
	if encounter_system:
		# 根据风险等级强制触发相应难度的遭遇
		var possible_encounters = []
		# 这里简化处理，实际应该查询遭遇数据库
		print("[MapModule] 移动中触发遭遇，风险等级: %.1f" % risk_level)


# ===== 路径规划 =====


## 计算路径成本
func calculate_path_cost(from: String, to: String) -> Dictionary:
	var base_time = _get_travel_time(from, to)

	# 获取生存状态修正
	var survival_system = get_node_or_null("/root/SurvivalStatusSystem")
	var movement_modifiers = {"speed_mult": 1.0, "stamina_cost_mult": 1.0}
	if survival_system:
		movement_modifiers = survival_system.get_movement_modifiers()

	# 负重影响
	var carry_penalty = 1.0
	if CarrySystem:
		carry_penalty = CarrySystem.get_movement_penalty()

	# 计算实际时间
	var actual_time = base_time / movement_modifiers.speed_mult * carry_penalty

	# 计算体力消耗
	var stamina_cost = int(actual_time * 10 * movement_modifiers.stamina_cost_mult)

	# 计算风险
	var base_risk = (_get_risks().get(from, 0) + _get_risks().get(to, 0)) / 2.0
	var encounter_chance = minf(base_risk * 0.05, 0.3)  # 最高30%

	# 夜间增加风险
	if GameState and GameState.is_night():
		encounter_chance *= 1.5
		actual_time *= 1.2  # 夜间移动更慢

	return {
		"from": from,
		"to": to,
		"time_hours": actual_time,
		"base_time": base_time,
		"stamina_cost": stamina_cost,
		"encounter_chance": encounter_chance,
		"risk_level": base_risk,
		"speed_mult": movement_modifiers.speed_mult,
		"carry_penalty": carry_penalty
	}


## 获取两地之间的距离
func _get_travel_distance(from: String, to: String) -> float:
	# 尝试通过路径查找计算距离
	var path = find_path(from, to)
	if path.size() >= 2:
		# 计算路径上所有段的距离总和
		var total_distance = 0.0
		for i in range(path.size() - 1):
			total_distance += _get_segment_distance(path[i], path[i + 1])
		return total_distance

	# 如果没有找到路径，使用直接距离（基于预定义坐标）
	return _get_direct_distance(from, to)


## 获取两地之间的直接距离（使用坐标）
func _get_direct_distance(from: String, to: String) -> float:
	# 地点坐标配置（与PathPlanningUI保持一致）
	var location_coords = {
		"safehouse": Vector2(400, 300),
		"street_a": Vector2(300, 250),
		"street_b": Vector2(500, 250),
		"supermarket": Vector2(200, 200),
		"hospital": Vector2(250, 350),
		"factory": Vector2(350, 400),
		"subway": Vector2(600, 300),
		"school": Vector2(550, 150),
		"forest": Vector2(450, 500),
		"ruins": Vector2(700, 350)
	}

	if location_coords.has(from) and location_coords.has(to):
		var from_pos = location_coords[from]
		var to_pos = location_coords[to]
		var pixel_distance = from_pos.distance_to(to_pos)
		# 将像素距离转换为游戏时间（100像素 = 1小时）
		return pixel_distance / 100.0

	# 默认距离
	return 2.0


## 获取两个相邻地点之间的距离
func _get_segment_distance(from: String, to: String) -> float:
	var key1 = from + "_" + to
	var key2 = to + "_" + from
	var distances = _get_distances()

	if distances.has(key1):
		return distances[key1]
	if distances.has(key2):
		return distances[key2]

	# 如果在distances中没有定义，使用直接距离
	return _get_direct_distance(from, to)


func _get_travel_time(from: String, to: String) -> float:
	var key1 = from + "_" + to
	var key2 = to + "_" + from
	var distances = _get_distances()

	if distances.has(key1):
		return distances[key1]
	if distances.has(key2):
		return distances[key2]

	# 默认时间
	return 1.0


## 查找路径（支持中转）
func find_path(from: String, to: String) -> Array:
	# 简单的BFS路径查找
	if from == to:
		return [from]

	var visited = {from: null}
	var queue = [from]
	var connections = _get_connections()

	while queue.size() > 0:
		var current = queue.pop_front()

		if not connections.has(current):
			continue

		for neighbor in connections[current]:
			if not visited.has(neighbor):
				visited[neighbor] = current
				if neighbor == to:
					return _reconstruct_path(visited, to)
				queue.append(neighbor)

	return []  # 无路径


func _reconstruct_path(visited: Dictionary, to: String) -> Array:
	var path = [to]
	var current = to

	while visited.has(current) and visited[current] != null:
		current = visited[current]
		path.insert(0, current)

	return path


## 计算完整路径成本
func calculate_full_path_cost(path: Array) -> Dictionary:
	if path.size() < 2:
		return {"total_time": 0, "total_stamina": 0, "total_risk": 0}

	var total_time = 0.0
	var total_stamina = 0
	var max_risk = 0.0
	var path_details = []

	for i in range(path.size() - 1):
		var from_loc = path[i]
		var to_loc = path[i + 1]

		var segment_cost = calculate_path_cost(from_loc, to_loc)
		total_time += segment_cost.time_hours
		total_stamina += segment_cost.stamina_cost
		max_risk = maxf(max_risk, segment_cost.risk_level)

		path_details.append(
			{
				"from": from_loc,
				"to": to_loc,
				"time": segment_cost.time_hours,
				"stamina": segment_cost.stamina_cost,
				"risk": segment_cost.encounter_chance
			}
		)

	return {
		"path": path,
		"total_time": total_time,
		"total_stamina": total_stamina,
		"max_risk": max_risk,
		"segments": path_details
	}


## 获取所有可达地点（现在所有解锁的地点都可直达）
func get_reachable_locations(from: String = "") -> Array:
	if from.is_empty():
		var gs = get_node("/root/GameState")
		if gs:
			from = gs.player_position
		else:
			return []

	# 返回所有已解锁的地点（除了当前位置）
	var reachable = []
	for loc_id in _get_location_data().keys():
		if loc_id != from and _is_unlocked(loc_id):
			reachable.append(loc_id)

	return reachable


# ===== 查询 =====


func get_current_location():
	var gs = get_node("/root/GameState")
	if not gs:
		return {}
	return _get_location_data().get(gs.player_position, {})


func get_available_destinations() -> Array[Dictionary]:
	var gs = get_node("/root/GameState")
	if not gs:
		return []

	var available = []
	var current = gs.player_position
	var locations = _get_location_data()

	# 获取所有已解锁的地点（现在所有解锁地点都可直达）
	for loc_id in locations.keys():
		if loc_id != current and _is_unlocked(loc_id):
			var loc_data = locations[loc_id]
			var travel_cost = _calculate_travel_cost(current, loc_id)

			available.append(
				{
					"id": loc_id,
					"name": loc_data.name,
					"description": loc_data.description,
					"danger_level": loc_data.danger_level,
					"travel_time": travel_cost.time_hours,
					"food_cost": travel_cost.food_cost,
					"stamina_cost": travel_cost.stamina_cost,
					"encounter_risk": travel_cost.encounter_chance
				}
			)

	return available


func unlock_location(location_id: String):
	var gs = get_node("/root/GameState")
	if not gs:
		return

	if not gs.world_unlocked_locations.has(location_id):
		gs.world_unlocked_locations.append(location_id)
		location_unlocked.emit(location_id, _get_location_data()[location_id])


func _is_unlocked(location_id: String) -> bool:
	var gs = get_node("/root/GameState")
	if not gs:
		return false
	return location_id in gs.world_unlocked_locations


## 从配置表加载地点数据
func _get_location_data() -> Dictionary:
	var file_path = "res://data/json/map_locations.json"
	if not FileAccess.file_exists(file_path):
		push_error("[MapModule] 地图配置文件不存在: " + file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("[MapModule] 地图配置解析失败: " + json.get_error_message())
		return {}

	return json.data


# ===== 序列化 =====
func serialize() -> Dictionary:
	return {"connections": _get_connections(), "distances": _get_distances()}


func deserialize(data: Dictionary):
	# 地点连接和距离是静态配置，不需要从存档加载
	print("[MapModule] 地图数据已加载")
