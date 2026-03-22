extends "res://core/base_module.gd"

const GridNavigatorScript = preload("res://systems/grid_navigator.gd")

const OUTDOOR_ROOT_SCENE_PATH: String = "res://scenes/locations/game_world_root.tscn"

signal travel_started(from: String, to: String)
signal travel_completed(location_id: String)
signal location_unlocked(location_id: String, location_data: Dictionary)
signal path_calculated(path_data: Dictionary)

var _connections: Dictionary = {}
var _distances: Dictionary = {}
var _risks: Dictionary = {}
var _scene_transition_in_progress: bool = false
var _navigator: GridNavigator = GridNavigatorScript.new()

func _ready() -> void:
	print("[MapModule] 地图模块已初始化")
	_load_map_data_from_manager()

func _load_map_data_from_manager() -> void:
	var dm = get_node_or_null("/root/DataManager")
	if dm:
		_connections = dm.get_map_connections()
		_distances = dm.get_map_distances()
		_risks = dm.get_map_risks()

	if _connections.is_empty() or _distances.is_empty() or _risks.is_empty():
		push_warning("[MapModule] 无法从 DataManager 加载地图数据")

func get_world_root_scene_path() -> String:
	return OUTDOOR_ROOT_SCENE_PATH

func get_location_descriptor(location_id: String) -> Dictionary:
	return _get_location_data().get(location_id, {})

func get_all_location_data() -> Dictionary:
	return _get_location_data()

func get_outdoor_location_ids() -> Array[String]:
	var result: Array[String] = []
	for location_id_variant in _get_location_data().keys():
		var location_id := str(location_id_variant)
		if is_outdoor_location(location_id):
			result.append(location_id)
	result.sort()
	return result

func get_outdoor_locations_for_overworld() -> Array[String]:
	var result: Array[String] = []
	for location_id in get_outdoor_location_ids():
		if not is_location_visible_on_overworld(location_id):
			continue
		result.append(location_id)
	return result

func get_location_kind(location_id: String) -> String:
	var location_data := get_location_descriptor(location_id)
	return str(location_data.get("location_kind", "outdoor")).strip_edges().to_lower()

func is_outdoor_location(location_id: String) -> bool:
	return get_location_kind(location_id) == "outdoor"

func is_subscene_location(location_id: String) -> bool:
	return not is_outdoor_location(location_id)

func get_parent_outdoor_location_id(location_id: String) -> String:
	var location_data := get_location_descriptor(location_id)
	return str(location_data.get("parent_outdoor_location_id", "")).strip_edges()

func get_location_scene_path(location_id: String) -> String:
	var location_data := get_location_descriptor(location_id)
	return str(location_data.get("scene_path", "")).strip_edges()

func get_location_entry_spawn_id(location_id: String) -> String:
	var location_data := get_location_descriptor(location_id)
	return str(location_data.get("entry_spawn_id", "default_spawn")).strip_edges()

func get_location_return_spawn_id(location_id: String) -> String:
	var location_data := get_location_descriptor(location_id)
	return str(location_data.get("return_spawn_id", "default_spawn")).strip_edges()

func get_location_overworld_cell(location_id: String) -> Vector2i:
	return _read_vector2i_variant(get_location_descriptor(location_id).get("overworld_cell", Vector2i.ZERO))

func get_location_world_origin_cell(location_id: String) -> Vector2i:
	var location_data := get_location_descriptor(location_id)
	var origin_variant: Variant = location_data.get("world_origin_cell", location_data.get("overworld_cell", Vector2i.ZERO))
	return _read_vector2i_variant(origin_variant)

func get_location_world_size_cells(location_id: String) -> Vector2i:
	var location_data := get_location_descriptor(location_id)
	var size_variant: Variant = location_data.get("world_size_cells", [12, 12])
	return _read_vector2i_variant(size_variant, Vector2i(12, 12))

func get_location_proxy_scene_path(location_id: String) -> String:
	var location_data := get_location_descriptor(location_id)
	return str(location_data.get("proxy_scene_path", "")).strip_edges()

func is_location_visible_on_overworld(location_id: String) -> bool:
	var location_data := get_location_descriptor(location_id)
	return bool(location_data.get("overworld_visible", is_outdoor_location(location_id)))

func get_location_name(location_id: String) -> String:
	var location_data := get_location_descriptor(location_id)
	return str(location_data.get("name", location_id))

func can_travel_to_outdoor(location_id: String, apply_travel_costs: bool = true) -> Dictionary:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {"success": false, "message": "GameState 不可用。"}
	if not is_outdoor_location(location_id):
		return {"success": false, "message": "该地点不属于露天世界。"}
	if not _get_location_data().has(location_id):
		return {"success": false, "message": "目标地点不存在。"}
	if not is_location_unlocked(location_id):
		return {"success": false, "message": "该地点尚未解锁。"}

	var current := str(gs.active_outdoor_location_id).strip_edges()
	if current.is_empty():
		current = str(gs.player_position).strip_edges()
	if current.is_empty():
		current = "safehouse"

	if apply_travel_costs and location_id == current:
		return {"success": false, "message": "你已经在这里了。"}

	if apply_travel_costs:
		if CarrySystem and not CarrySystem.can_move():
			return {"success": false, "message": "你负重太重了，几乎无法移动！先丢弃一些物品。"}
		var travel_cost := _calculate_travel_cost(current, location_id)
		var food_required: int = int(travel_cost.get("food_cost", 0))
		if not InventoryModule.has_item("1007", food_required):
			return {
				"success": false,
				"message": "食物不足！需要 %d 个罐头才能到达该地点。" % food_required
			}

	return {"success": true, "message": ""}

func travel_to(location_id: String, apply_travel_costs: bool = true) -> bool:
	var validation := can_travel_to_outdoor(location_id, apply_travel_costs)
	if not bool(validation.get("success", false)):
		_show_message(str(validation.get("message", "无法前往目标地点。")))
		return false

	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false

	var current := str(gs.active_outdoor_location_id).strip_edges()
	if current.is_empty():
		current = str(gs.player_position).strip_edges()
	if current.is_empty():
		current = "safehouse"

	if apply_travel_costs:
		var travel_cost := _calculate_travel_cost(current, location_id)
		var food_required: int = int(travel_cost.get("food_cost", 0))
		InventoryModule.remove_item("1007", food_required)
		travel_started.emit(current, location_id)
		_apply_travel_costs(travel_cost)
		print(
			"[MapModule] 露天旅行完成: %s -> %s (消耗时间: %.1f小时, 食物: %d)"
			% [current, location_id, float(travel_cost.get("time_hours", 0.0)), food_required]
		)
	else:
		print("[MapModule] 进入露天地点: %s" % location_id)

	var entry_spawn_id := get_location_entry_spawn_id(location_id)
	if location_id != current:
		gs.player_local_position = Vector3.ZERO
	gs.set_active_outdoor_context(location_id, entry_spawn_id)
	gs.set_world_mode(gs.WORLD_MODE_LOCAL)
	gs.set_overworld_cell(get_location_overworld_cell(location_id))
	gs.travel_to(location_id)
	travel_completed.emit(location_id)
	return true

func enter_subscene_location(location_id: String, return_spawn_id: String = "default_spawn") -> bool:
	if not is_subscene_location(location_id):
		_show_message("该地点不是室内或地牢场景。")
		return false
	var scene_path := get_location_scene_path(location_id)
	if scene_path.is_empty():
		_show_message("目标室内场景未配置。")
		return false
	if _scene_transition_in_progress:
		return false

	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false

	var outdoor_location_id := str(gs.active_outdoor_location_id).strip_edges()
	if outdoor_location_id.is_empty():
		outdoor_location_id = get_parent_outdoor_location_id(location_id)
	if outdoor_location_id.is_empty():
		_show_message("缺少室内返回的露天地点配置。")
		return false

	var scene_kind := get_location_kind(location_id)
	gs.set_active_subscene_context(location_id, scene_kind, outdoor_location_id, return_spawn_id)
	_transition_to_scene(scene_path)
	return true

func exit_current_subscene_to_outdoor() -> bool:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	if gs.active_scene_kind == gs.SCENE_KIND_OUTDOOR_ROOT:
		return false
	if _scene_transition_in_progress:
		return false

	var target_outdoor := str(gs.return_outdoor_location_id).strip_edges()
	if target_outdoor.is_empty():
		target_outdoor = get_parent_outdoor_location_id(gs.current_subscene_location_id)
	if target_outdoor.is_empty():
		target_outdoor = "safehouse"

	var target_spawn := str(gs.return_outdoor_spawn_id).strip_edges()
	if target_spawn.is_empty():
		target_spawn = get_location_return_spawn_id(gs.current_subscene_location_id)
	if target_spawn.is_empty():
		target_spawn = "default_spawn"

	gs.restore_outdoor_from_subscene()
	gs.set_active_outdoor_context(target_outdoor, target_spawn)
	gs.set_world_mode(gs.WORLD_MODE_LOCAL)
	_transition_to_scene(OUTDOOR_ROOT_SCENE_PATH)
	return true

func calculate_path_cost(from: String, to: String) -> Dictionary:
	var base_time = _get_travel_time(from, to)

	var survival_system = get_node_or_null("/root/SurvivalStatusSystem")
	var movement_modifiers = {"speed_mult": 1.0, "stamina_cost_mult": 1.0}
	if survival_system:
		movement_modifiers = survival_system.get_movement_modifiers()

	var carry_penalty = 1.0
	if CarrySystem:
		carry_penalty = CarrySystem.get_movement_penalty()

	var actual_time = base_time / movement_modifiers.speed_mult * carry_penalty
	var stamina_cost = int(actual_time * 10 * movement_modifiers.stamina_cost_mult)

	var base_risk = (_risks.get(from, 0) + _risks.get(to, 0)) / 2.0
	var encounter_chance = minf(base_risk * 0.05, 0.3)
	if GameState and GameState.is_night():
		encounter_chance *= 1.5
		actual_time *= 1.2

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

func find_path(from: String, to: String) -> Array:
	if from == to:
		return [from]

	var visited = {from: null}
	var queue = [from]

	while queue.size() > 0:
		var current = queue.pop_front()
		if not _connections.has(current):
			continue
		for neighbor in _connections[current]:
			if not visited.has(neighbor):
				visited[neighbor] = current
				if neighbor == to:
					return _reconstruct_path(visited, to)
				queue.append(neighbor)

	return []

func find_overworld_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var walkable_cells := {}
	for cell in get_overworld_walkable_cells():
		walkable_cells[_cell_key(cell)] = true
	for location_id in get_outdoor_location_ids():
		walkable_cells[_cell_key(get_location_overworld_cell(location_id))] = true

	var world_path: Array[Vector3] = _navigator.find_path(
		_cell_to_world(from_cell),
		_cell_to_world(to_cell),
		func(grid_pos: Vector3i) -> bool:
			return walkable_cells.has(_cell_key(Vector2i(grid_pos.x, grid_pos.z)))
	)

	var result: Array[Vector2i] = []
	for world_pos in world_path:
		var grid_pos: Vector3i = _navigator.world_to_grid(world_pos)
		result.append(Vector2i(grid_pos.x, grid_pos.z))

	path_calculated.emit({"from": from_cell, "to": to_cell, "path": result})
	return result

func get_reachable_outdoor_locations(from_location_id: String = "") -> Array[String]:
	if from_location_id.is_empty():
		var gs = get_node_or_null("/root/GameState")
		if gs:
			from_location_id = str(gs.active_outdoor_location_id).strip_edges()
			if from_location_id.is_empty():
				from_location_id = str(gs.player_position).strip_edges()
	if from_location_id.is_empty():
		return []

	var reachable: Array[String] = []
	for loc_id in get_outdoor_location_ids():
		if loc_id == from_location_id:
			continue
		if is_location_unlocked(loc_id):
			reachable.append(loc_id)
	return reachable

func get_reachable_locations(from_location_id: String = "") -> Array[String]:
	return get_reachable_outdoor_locations(from_location_id)

func get_current_location() -> Dictionary:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {}
	return get_location_descriptor(str(gs.player_position).strip_edges())

func get_overworld_walkable_cells() -> Array[Vector2i]:
	var walkable_cells: Array[Vector2i] = []
	var dm = get_node_or_null("/root/DataManager")
	if dm == null:
		return walkable_cells
	var map_data: Dictionary = dm.get_data("map_data")
	var cells_variant: Variant = map_data.get("overworld_walkable_cells", [])
	if not (cells_variant is Array):
		return walkable_cells
	for cell_variant in cells_variant:
		walkable_cells.append(_read_vector2i_variant(cell_variant))
	return walkable_cells

func is_location_unlocked(location_id: String) -> bool:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	if location_id in gs.world_unlocked_locations:
		return true
	return bool(get_location_descriptor(location_id).get("default_unlocked", false))

func get_available_destinations() -> Array[Dictionary]:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return []

	var available: Array[Dictionary] = []
	var current := str(gs.active_outdoor_location_id).strip_edges()
	if current.is_empty():
		current = str(gs.player_position).strip_edges()

	for loc_id in get_reachable_outdoor_locations(current):
		var loc_data := get_location_descriptor(loc_id)
		var travel_cost := _calculate_travel_cost(current, loc_id)
		available.append(
			{
				"id": loc_id,
				"name": loc_data.get("name", loc_id),
				"description": loc_data.get("description", ""),
				"danger_level": loc_data.get("danger_level", 0),
				"travel_time": travel_cost.time_hours,
				"food_cost": travel_cost.food_cost,
				"stamina_cost": travel_cost.stamina_cost,
				"encounter_risk": travel_cost.encounter_chance
			}
		)
	return available

func unlock_location(location_id: String) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	if gs.world_unlocked_locations.has(location_id):
		return
	gs.world_unlocked_locations.append(location_id)
	location_unlocked.emit(location_id, get_location_descriptor(location_id))

func serialize() -> Dictionary:
	return {"connections": _connections, "distances": _distances}

func deserialize(_data: Dictionary) -> void:
	print("[MapModule] 地图静态数据无需从存档恢复")

func _calculate_travel_cost(from: String, to: String) -> Dictionary:
	var base_distance = _get_travel_distance(from, to)

	var survival_system = get_node_or_null("/root/SurvivalStatusSystem")
	var movement_modifiers = {"speed_mult": 1.0}
	if survival_system:
		var mods = survival_system.get_movement_modifiers()
		movement_modifiers.speed_mult = mods.get("speed_mult", 1.0)

	var carry_penalty = 1.0
	if CarrySystem:
		carry_penalty = CarrySystem.get_movement_penalty()

	var actual_time = base_distance / movement_modifiers.speed_mult * carry_penalty
	if GameState and GameState.is_night():
		actual_time *= 1.2

	var food_cost = maxi(1, int(actual_time / 2.0))
	var stamina_cost = int(actual_time * 8)
	var base_risk = (_risks.get(from, 0) + _risks.get(to, 0)) / 2.0
	var encounter_chance = minf(base_risk * 0.03, 0.25)

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

func _apply_travel_costs(path_cost: Dictionary) -> void:
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.advance_hours(path_cost.time_hours)

	if GameState:
		GameState.player_stamina = maxi(0, GameState.player_stamina - int(path_cost.stamina_cost))

func _get_travel_distance(from: String, to: String) -> float:
	var path = find_path(from, to)
	if path.size() >= 2:
		var total_distance = 0.0
		for i in range(path.size() - 1):
			total_distance += _get_segment_distance(path[i], path[i + 1])
		return total_distance
	return _get_direct_distance(from, to)

func _get_direct_distance(from: String, to: String) -> float:
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
		var from_pos: Vector2 = location_coords[from]
		var to_pos: Vector2 = location_coords[to]
		return from_pos.distance_to(to_pos) / 100.0

	return 2.0

func _get_segment_distance(from: String, to: String) -> float:
	var key1 = from + "_" + to
	var key2 = to + "_" + from
	if _distances.has(key1):
		return _distances[key1]
	if _distances.has(key2):
		return _distances[key2]
	return _get_direct_distance(from, to)

func _get_travel_time(from: String, to: String) -> float:
	var key1 = from + "_" + to
	var key2 = to + "_" + from
	if _distances.has(key1):
		return _distances[key1]
	if _distances.has(key2):
		return _distances[key2]
	return 1.0

func _reconstruct_path(visited: Dictionary, to: String) -> Array:
	var path = [to]
	var current = to
	while visited.has(current) and visited[current] != null:
		current = visited[current]
		path.insert(0, current)
	return path

func _get_location_data() -> Dictionary:
	var dm = get_node_or_null("/root/DataManager")
	if dm and dm.has_method("get_all_locations"):
		return dm.get_all_locations()

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

func _transition_to_scene(scene_path: String) -> void:
	var resolved_scene_path := scene_path.strip_edges()
	if resolved_scene_path.is_empty():
		push_error("[MapModule] 目标场景路径为空")
		return
	if _scene_transition_in_progress:
		return
	_scene_transition_in_progress = true
	call_deferred("_run_scene_transition", resolved_scene_path)

func _run_scene_transition(scene_path: String) -> void:
	var root := get_tree().root
	var overlay := CanvasLayer.new()
	overlay.layer = 200
	var fade_rect := ColorRect.new()
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.add_child(fade_rect)
	root.add_child(overlay)

	var fade_in := create_tween()
	fade_in.tween_property(fade_rect, "color:a", 1.0, 0.18)
	await fade_in.finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	var fade_out := create_tween()
	fade_out.tween_property(fade_rect, "color:a", 0.0, 0.18)
	await fade_out.finished
	overlay.queue_free()
	_scene_transition_in_progress = false

func _show_message(message: String) -> void:
	if message.is_empty():
		return
	if DialogModule != null:
		DialogModule.show_dialog(message, "提示", "")

func _read_vector2i_variant(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary:
		return Vector2i(int(value.get("x", fallback.x)), int(value.get("y", fallback.y)))
	return fallback

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)

func _cell_key(cell: Vector2i) -> String:
	return "%d|%d" % [cell.x, cell.y]
