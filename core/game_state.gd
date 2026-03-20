extends Node
# GameState - 游戏全局状态管理
# 最佳实践: 不使用 class_name，直接暴露变量
const AttributeSystemScript = preload("res://systems/attribute_system.gd")
const ValueUtils = preload("res://core/value_utils.gd")
const OUTDOOR_ROOT_SCENE_PATH: String = "res://scenes/locations/game_world_root.tscn"
const SCENE_KIND_OUTDOOR_ROOT: String = "outdoor_root"
const SCENE_KIND_INTERIOR: String = "interior"
const SCENE_KIND_DUNGEON: String = "dungeon"
const WORLD_MODE_LOCAL: String = "LOCAL"
const WORLD_MODE_ZOOMING_OUT: String = "ZOOMING_OUT"
const WORLD_MODE_OVERWORLD: String = "OVERWORLD"
const WORLD_MODE_TRAVELING: String = "TRAVELING"
const WORLD_MODE_ZOOMING_IN: String = "ZOOMING_IN"

# ===== 玩家状态 =====
var _player_attributes: Dictionary = {}

func _build_default_player_attributes() -> Dictionary:
	return AttributeSystemScript.create_player_default_container()


func _ensure_player_attributes_initialized() -> void:
	if _player_attributes.is_empty():
		_player_attributes = _build_default_player_attributes()


func _get_player_attributes_container() -> Dictionary:
	_ensure_player_attributes_initialized()
	if _attr_system and _attr_system.has_method("get_player_attributes_container"):
		_player_attributes = _attr_system.get_player_attributes_container()
	return _player_attributes.duplicate(true)


func _set_player_attributes_container(container: Dictionary) -> void:
	_player_attributes = AttributeSystemScript.normalize_attribute_container(container)
	if _attr_system and _attr_system.has_method("set_player_attributes_container"):
		_attr_system.set_player_attributes_container(_player_attributes)


func _get_player_snapshot() -> Dictionary:
	_ensure_player_attributes_initialized()
	if _attr_system and _attr_system.has_method("get_actor_attributes_snapshot"):
		return _attr_system.get_actor_attributes_snapshot("player")
	return AttributeSystemScript.resolve_attribute_snapshot(_player_attributes)


func _get_player_resource_current(resource_key: String, default_value: float = 0.0) -> float:
	var container: Dictionary = _get_player_attributes_container()
	var resources: Dictionary = container.get("resources", {})
	if resources.get(resource_key, {}) is Dictionary:
		return float((resources.get(resource_key, {}) as Dictionary).get("current", default_value))
	return default_value


func _set_player_resource_current(resource_key: String, value: Variant) -> void:
	_ensure_player_attributes_initialized()
	if _attr_system and _attr_system.has_method("set_player_resource_current"):
		_attr_system.set_player_resource_current(resource_key, value)
		_player_attributes = _attr_system.get_player_attributes_container()
		return
	if not _player_attributes["resources"].has(resource_key):
		_player_attributes["resources"][resource_key] = {}
	var max_value: float = 9999.0
	if resource_key == "hp":
		max_value = float(get_player_stat("max_hp", 100.0))
	_player_attributes["resources"][resource_key]["current"] = clampf(float(value), 0.0, max_value)


func get_player_attributes_container() -> Dictionary:
	return _get_player_attributes_container()


func get_player_attributes_snapshot() -> Dictionary:
	return _get_player_snapshot()


func get_player_stat(stat_name: String, default_value: Variant = 0.0) -> Variant:
	var snapshot: Dictionary = _get_player_snapshot()
	return snapshot.get(stat_name, default_value)

func _get_player_resource_value_as_int(resource_key: String, default_value: float = 0.0) -> int:
	return ValueUtils.to_int(round(_get_player_resource_current(resource_key, default_value)))


func _get_player_attribute_value_as_int(attribute_key: String, default_value: Variant = 0) -> int:
	return ValueUtils.to_int(round(float(get_player_stat(attribute_key, default_value))))

var player_hunger: int = 100
var player_thirst: int = 100
var player_stamina: int = 100
var player_mental: int = 100
var player_position: String = "safehouse"
var player_position_3d: Vector3 = Vector3.ZERO
var player_grid_position: Vector3i = Vector3i.ZERO
var player_local_position: Vector3 = Vector3(0.5, 0.0, 0.5)
var world_mode: String = WORLD_MODE_OVERWORLD
var active_scene_kind: String = SCENE_KIND_OUTDOOR_ROOT
var active_outdoor_location_id: String = "safehouse"
var active_outdoor_spawn_id: String = "default_spawn"
var overworld_pawn_cell: Vector2i = Vector2i.ZERO
var camera_zoom_level: float = 11.0
var current_subscene_location_id: String = ""
var return_outdoor_location_id: String = ""
var return_outdoor_spawn_id: String = "default_spawn"
var outdoor_resume_mode: String = WORLD_MODE_LOCAL
var is_player_moving: bool = false

# ===== 角色装备系统 =====
signal equipment_system_ready(equipment_system: Node)
var _equipment_system: Node = null
var _pending_equipment_save_data: Dictionary = {}
var _pending_equips: Array[Dictionary] = []
var _pending_ammo: Array[Dictionary] = []

func save_3d_position(pos: Vector3, grid_pos: Vector3i) -> void:
	player_position_3d = pos
	player_grid_position = grid_pos
	player_local_position = pos

func get_saved_3d_position() -> Vector3:
	return player_position_3d

func save_local_player_position(local_pos: Vector3) -> void:
	player_local_position = local_pos

func set_world_mode(mode: String) -> void:
	world_mode = mode

func set_camera_zoom_level(value: float) -> void:
	camera_zoom_level = value

func set_overworld_cell(cell: Vector2i) -> void:
	overworld_pawn_cell = cell

func set_active_outdoor_context(location_id: String, spawn_id: String = "default_spawn") -> void:
	active_scene_kind = SCENE_KIND_OUTDOOR_ROOT
	active_outdoor_location_id = location_id
	active_outdoor_spawn_id = spawn_id
	player_position = location_id
	current_subscene_location_id = ""

func set_active_subscene_context(
	location_id: String,
	scene_kind: String,
	return_location_id: String,
	return_spawn_id: String
) -> void:
	active_scene_kind = scene_kind
	current_subscene_location_id = location_id
	return_outdoor_location_id = return_location_id
	return_outdoor_spawn_id = return_spawn_id
	outdoor_resume_mode = WORLD_MODE_LOCAL
	player_position = location_id

func restore_outdoor_from_subscene() -> void:
	active_scene_kind = SCENE_KIND_OUTDOOR_ROOT
	current_subscene_location_id = ""
	if not return_outdoor_location_id.is_empty():
		active_outdoor_location_id = return_outdoor_location_id
	if not return_outdoor_spawn_id.is_empty():
		active_outdoor_spawn_id = return_outdoor_spawn_id
	player_position = active_outdoor_location_id
	world_mode = outdoor_resume_mode

func reset_world_runtime(start_location_id: String = "safehouse", start_spawn_id: String = "default_spawn") -> void:
	active_scene_kind = SCENE_KIND_OUTDOOR_ROOT
	world_mode = WORLD_MODE_OVERWORLD
	active_outdoor_location_id = start_location_id
	active_outdoor_spawn_id = start_spawn_id
	current_subscene_location_id = ""
	return_outdoor_location_id = ""
	return_outdoor_spawn_id = start_spawn_id
	outdoor_resume_mode = WORLD_MODE_LOCAL
	overworld_pawn_cell = Vector2i.ZERO
	camera_zoom_level = 11.0
	player_position = start_location_id
	player_position_3d = Vector3.ZERO
	player_grid_position = Vector3i.ZERO
	player_local_position = Vector3(0.5, 0.0, 0.5)

func get_active_scene_path() -> String:
	if active_scene_kind == SCENE_KIND_OUTDOOR_ROOT:
		return OUTDOOR_ROOT_SCENE_PATH
	if current_subscene_location_id.is_empty():
		return OUTDOOR_ROOT_SCENE_PATH
	if MapModule != null and MapModule.has_method("get_location_scene_path"):
		return MapModule.get_location_scene_path(current_subscene_location_id)
	return OUTDOOR_ROOT_SCENE_PATH

func _deserialize_vector3(value: Variant, fallback: Vector3) -> Vector3:
	var decoded: Variant = str_to_var(str(value))
	if decoded is Vector3:
		return decoded
	return fallback

func _deserialize_vector3i(value: Variant, fallback: Vector3i) -> Vector3i:
	var decoded: Variant = str_to_var(str(value))
	if decoded is Vector3i:
		return decoded
	return fallback

func _deserialize_vector2i(value: Variant, fallback: Vector2i) -> Vector2i:
	var decoded: Variant = str_to_var(str(value))
	if decoded is Vector2i:
		return decoded
	return fallback

# ===== 货币系统 =====
var player_money: int = 0

# ===== 新系统：等级与经验值 =====
var player_level: int = 1
var player_xp: int = 0
var player_total_xp: int = 0
var player_available_stat_points: int = 0
var player_available_skill_points: int = 0

# ===== 新系统：时间 =====
var game_day: int = 1
var game_hour: int = 8
var game_minute: int = 0

# ===== 背包状态 =====
const DEFAULT_INVENTORY_GRID_WIDTH: int = 5
const DEFAULT_INVENTORY_GRID_HEIGHT: int = 4

var inventory_items: Array[Dictionary] = []
var inventory_max_slots: int = 20
var inventory_grid_width: int = DEFAULT_INVENTORY_GRID_WIDTH
var inventory_grid_height: int = DEFAULT_INVENTORY_GRID_HEIGHT
var _inventory_instance_counter: int = 1

# ===== 世界状态（保留兼容旧代码）=====
var world_time: int = 8:
	get:
		return game_hour
	set(value):
		game_hour = value

var world_day: int = 1:
	get:
		return game_day
	set(value):
		game_day = value

var world_weather: String = "clear"
var world_unlocked_locations: Array[String] = ["safehouse", "street_a", "street_b"]
var fog_of_war_by_map: Dictionary = {}

# ===== 任务状态 =====
var quest_active: Array[Dictionary] = []
var quest_completed: Array[Dictionary] = []

# ===== 系统引用缓存 =====
var _time_manager: Node = null
var _xp_system: Node = null
var _attr_system: Node = null
var _skill_system: Node = null
var _risk_system: Node = null
var _survival_status: Node = null


func apply_player_attribute_delta(source: String, values: Variant) -> bool:
	if _attr_system and _attr_system.has_method("apply_actor_attribute_delta"):
		return _attr_system.apply_actor_attribute_delta("player", source, values)
	return false


func allocate_player_attributes(delta_map: Dictionary) -> Dictionary:
	if _attr_system and _attr_system.has_method("allocate_player_attributes"):
		var result: Dictionary = _attr_system.allocate_player_attributes(delta_map)
		if bool(result.get("success", false)):
			_player_attributes = _attr_system.get_player_attributes_container()
		return result
	return {"success": false, "reason": "attribute_system_missing"}

func _resolve_item_id(item_id: String) -> String:
	if ItemDatabase:
		return ItemDatabase.resolve_item_id(item_id)
	return item_id

func set_equipment_system(system: Node) -> void:
	_equipment_system = system
	equipment_system_ready.emit(system)

func get_equipment_system() -> Node:
	return _equipment_system

func set_pending_equipment_save_data(data: Dictionary) -> void:
	_pending_equipment_save_data = data

func consume_pending_equipment_save_data() -> Dictionary:
	var data = _pending_equipment_save_data
	_pending_equipment_save_data = {}
	return data

func get_pending_equipment_save_data() -> Dictionary:
	return _pending_equipment_save_data.duplicate(true)

func queue_equip(item_id: String, slot: String) -> void:
	_pending_equips.append({
		"item_id": _resolve_item_id(item_id),
		"slot": slot
	})

func consume_pending_equips() -> Array[Dictionary]:
	var equips = _pending_equips.duplicate(true)
	_pending_equips.clear()
	return equips

func queue_ammo(ammo_type: String, count: int) -> void:
	_pending_ammo.append({
		"ammo_type": _resolve_item_id(ammo_type),
		"count": count
	})

func consume_pending_ammo() -> Array[Dictionary]:
	var ammo = _pending_ammo.duplicate(true)
	_pending_ammo.clear()
	return ammo

func _ready():
	print("[GameState] Initialized")
	_ensure_player_attributes_initialized()
	
	# 延迟初始化，等待其他系统自动加载
	call_deferred("_connect_systems")

func _connect_systems():
	# 获取系统引用
	_time_manager = get_node_or_null("/root/TimeManager")
	_xp_system = get_node_or_null("/root/ExperienceSystem")
	_attr_system = get_node_or_null("/root/AttributeSystem")
	_skill_system = get_node_or_null("/root/SkillSystem")
	_risk_system = get_node_or_null("/root/DayNightRiskSystem")
	_survival_status = get_node_or_null("/root/SurvivalStatusSystem")
	
	# 连接信号
	if _xp_system:
		_xp_system.level_up.connect(_on_level_up)
		_xp_system.xp_gained.connect(_on_xp_gained)
	
	if _attr_system:
		if _attr_system.attribute_changed.is_connected(_on_attribute_changed) == false:
			_attr_system.attribute_changed.connect(_on_attribute_changed)
		_set_player_attributes_container(_player_attributes)
	
	if _survival_status:
		_survival_status.status_warning_triggered.connect(_on_status_warning)
	
	# 同步数据到新系统
	_sync_to_systems()

# ===== 与新系统同步数据 =====

func _sync_to_systems():
	# 将GameState数据同步到各系统
	if _time_manager:
		_time_manager.set_time(game_day, game_hour, game_minute)
	
	if _attr_system:
		_set_player_attributes_container(_player_attributes)

func _sync_from_systems():
	# 从各系统同步数据到GameState
	if _time_manager:
		game_day = _time_manager.current_day
		game_hour = _time_manager.current_hour
		game_minute = _time_manager.current_minute
	
	if _xp_system:
		player_level = _xp_system.current_level
		player_xp = _xp_system.current_xp
		player_total_xp = _xp_system.total_xp_earned
		var points = _xp_system.get_available_points()
		player_available_stat_points = points.stat_points
		player_available_skill_points = points.skill_points
	
	if _attr_system:
		_player_attributes = _attr_system.get_player_attributes_container()

# ===== 信号处理 =====

func _on_level_up(new_level: int, rewards: Dictionary):
	player_level = new_level
	
	# 应用状态恢复
	if rewards.has("hp_restored"):
		heal_player(ValueUtils.to_int(_get_player_attribute_value_as_int("max_hp", 100) * rewards.hp_restored / 100.0))
	if rewards.has("stamina_restored"):
		player_stamina = mini(100, player_stamina + ValueUtils.to_int(100 * rewards.stamina_restored / 100.0))
	if rewards.has("mental_restored"):
		player_mental = mini(100, player_mental + ValueUtils.to_int(100 * rewards.mental_restored / 100.0))
	
	print("[GameState] 玩家升级到等级 %d" % new_level)

func _on_xp_gained(amount: int, source: String, total_xp: int):
	player_xp = total_xp
	player_total_xp += amount

func _on_attribute_changed(attr_name: String, new_value: int, old_value: int):
	_player_attributes = _attr_system.get_player_attributes_container() if _attr_system else _player_attributes

func _on_status_warning(warning_type: String, severity: String):
	# 状态警告通过EventBus传播
	EventBus.emit(EventBus.EventType.STATUS_WARNING, {
		"type": warning_type,
		"severity": severity,
		"location": player_position
	})

# ===== 经验值接口 =====

func add_xp(amount: int, source: String = "unknown") -> Dictionary:
	if _xp_system:
		return _xp_system.gain_xp(amount, source)
	return {"success": false, "reason": "系统未初始化"}

func add_combat_xp(enemy_strength: String = "normal") -> Dictionary:
	return add_xp(_calculate_combat_xp(enemy_strength), "combat_" + enemy_strength)

func _calculate_combat_xp(enemy_strength: String) -> int:
	match enemy_strength:
		"weak": return 10
		"normal": return 25
		"strong": return 50
		"elite": return 100
		"boss": return 250
		_: return 15

# ===== 时间接口 =====

func advance_time(minutes: int):
	if _time_manager:
		_time_manager.advance_minutes(minutes)
		_sync_from_systems()

func get_formatted_time() -> String:
	if _time_manager:
		return _time_manager.get_full_datetime()
	return "第 %d 天 %02d:%02d" % [game_day, game_hour, game_minute]

func is_night() -> bool:
	if _time_manager:
		return _time_manager.is_night()
	return game_hour < 6 or game_hour >= 18

# ===== 生存状态接口 =====

func get_body_temperature() -> float:
	if _survival_status:
		return _survival_status.body_temperature
	return 37.0

func get_immunity() -> float:
	if _survival_status:
		return _survival_status.immunity
	return 100.0

func get_fatigue() -> int:
	if _survival_status:
		return _survival_status.fatigue
	return 0

func get_temperature_status() -> String:
	if _survival_status:
		return _survival_status.get_temperature_status()
	return "体温正常"

func get_immunity_status() -> String:
	if _survival_status:
		return _survival_status.get_immunity_status()
	return "免疫良好"

func get_fatigue_status() -> String:
	if _survival_status:
		return _survival_status.get_fatigue_status()
	return "精神良好"

# ===== 便捷方法 =====

func damage_player(amount: int):
	var snapshot: Dictionary = _get_player_snapshot()
	var defense_value: float = float(snapshot.get("defense", 0.0))
	var damage_reduction: float = float(snapshot.get("damage_reduction", 0.0))
	var actual_damage := maxi(1, ValueUtils.to_int(round(float(amount) - defense_value * 0.5)))
	actual_damage = maxi(1, ValueUtils.to_int(round(float(actual_damage) * (1.0 - damage_reduction))))
	_set_player_resource_current("hp", maxi(0, _get_player_resource_value_as_int("hp", 100.0) - actual_damage))

	# 减少装备耐久
	var equip_system = get_equipment_system()
	if equip_system:
		equip_system.on_damage_taken(actual_damage)
	
	# 受伤影响生存状态
	if _survival_status:
		_survival_status.immunity = maxf(0, _survival_status.immunity - 5.0)
		_survival_status.fatigue = mini(_survival_status.FATIGUE_MAX, _survival_status.fatigue + 10)

	EventBus.emit(EventBus.EventType.PLAYER_HURT, {"hp": _get_player_resource_value_as_int("hp", 100.0), "damage": actual_damage})

func heal_player(amount: int):
	_set_player_resource_current(
		"hp",
		mini(
			_get_player_attribute_value_as_int("max_hp", 100),
			_get_player_resource_value_as_int("hp", 100.0) + amount
		)
	)
	EventBus.emit(EventBus.EventType.PLAYER_HEALED, {"hp": _get_player_resource_value_as_int("hp", 100.0), "amount": amount})

func add_item(item_id: String, count: int = 1) -> bool:
	var resolved_id = _resolve_item_id(str(item_id))
	if resolved_id.is_empty() or count <= 0:
		return false

	if _skill_system and _skill_system.get_loot_bonus_chance() > 0:
		if randf() < _skill_system.get_loot_bonus_chance():
			count += 1
			print("[GameState] 拾荒技能触发，额外获得1个物品")

	var simulated_items: Array[Dictionary] = inventory_items.duplicate(true)
	var simulated_counter: int = _inventory_instance_counter
	var remaining: int = count
	var is_stackable: bool = ItemDatabase.is_stackable(resolved_id) if ItemDatabase else true
	var max_stack: int = maxi(1, ItemDatabase.get_max_stack(resolved_id) if ItemDatabase else 99)

	if is_stackable:
		for entry_variant in simulated_items:
			var entry: Dictionary = entry_variant
			_normalize_inventory_entry(entry)
			if str(entry.get("id", "")) != resolved_id:
				continue
			if not str(entry.get("equipped_slot", "")).is_empty():
				continue
			var current_count: int = ValueUtils.to_int(entry.get("count", 1), 1)
			var free_space: int = max_stack - current_count
			if free_space <= 0:
				continue
			var to_add: int = mini(remaining, free_space)
			entry["count"] = current_count + to_add
			remaining -= to_add
			if remaining <= 0:
				break

	while remaining > 0:
		var stack_count: int = mini(remaining, max_stack if is_stackable else 1)
		simulated_items.append(_build_inventory_entry(resolved_id, stack_count, simulated_counter))
		simulated_counter += 1
		remaining -= stack_count

	var layout: Dictionary = _resolve_inventory_layout(
		simulated_items,
		inventory_grid_width,
		inventory_grid_height,
		inventory_max_slots,
		true
	)
	if not bool(layout.get("success", false)):
		return false

	inventory_items = layout.get("items", simulated_items)
	_inventory_instance_counter = simulated_counter
	_apply_inventory_capacity(layout.get("width", inventory_grid_width), layout.get("height", inventory_grid_height), layout.get("active_cells", inventory_max_slots))
	_emit_inventory_changed()
	return true

func remove_item(item_id: String, count: int = 1, include_equipped: bool = false) -> bool:
	var resolved_id = _resolve_item_id(str(item_id))
	if resolved_id.is_empty() or count <= 0:
		return false
	if get_item_count(resolved_id, include_equipped) < count:
		return false

	var simulated_items: Array[Dictionary] = inventory_items.duplicate(true)
	var remaining: int = count
	var equipped_removed: Array[Dictionary] = []
	var visible_order: Array[int] = []
	var equipped_order: Array[int] = []

	for i in range(simulated_items.size()):
		var entry: Dictionary = simulated_items[i]
		_normalize_inventory_entry(entry)
		var is_equipped: bool = not str(entry.get("equipped_slot", "")).is_empty()
		if str(entry.get("id", "")) != resolved_id:
			continue
		if is_equipped and not include_equipped:
			continue
		if not is_equipped:
			visible_order.append(i)
	for i in range(simulated_items.size()):
		var entry: Dictionary = simulated_items[i]
		_normalize_inventory_entry(entry)
		if str(entry.get("id", "")) != resolved_id:
			continue
		var is_equipped: bool = not str(entry.get("equipped_slot", "")).is_empty()
		if is_equipped and include_equipped:
			equipped_order.append(i)

	visible_order.reverse()
	equipped_order.reverse()
	var removal_order: Array[int] = visible_order + equipped_order
	for index in removal_order:
		if remaining <= 0:
			break
		var entry: Dictionary = simulated_items[index]
		var entry_count: int = ValueUtils.to_int(entry.get("count", 1), 1)
		var to_remove: int = mini(entry_count, remaining)
		entry["count"] = entry_count - to_remove
		remaining -= to_remove
		if ValueUtils.to_int(entry.get("count", 0)) <= 0:
			if not str(entry.get("equipped_slot", "")).is_empty():
				equipped_removed.append({
					"instance_id": str(entry.get("instance_id", "")),
					"slot": str(entry.get("equipped_slot", "")),
					"item_id": str(entry.get("id", ""))
				})
			simulated_items.remove_at(index)

	var layout: Dictionary = _resolve_inventory_layout(
		simulated_items,
		inventory_grid_width,
		inventory_grid_height,
		inventory_max_slots,
		true
	)
	if not bool(layout.get("success", false)):
		return false

	inventory_items = layout.get("items", simulated_items)
	for removed_entry in equipped_removed:
		var equip_system = get_equipment_system()
		if equip_system and equip_system.has_method("on_inventory_item_removed"):
			equip_system.on_inventory_item_removed(
				str(removed_entry.get("instance_id", "")),
				str(removed_entry.get("slot", "")),
				str(removed_entry.get("item_id", ""))
			)
	_apply_inventory_capacity(layout.get("width", inventory_grid_width), layout.get("height", inventory_grid_height), layout.get("active_cells", inventory_max_slots))
	_emit_inventory_changed()
	return true

func has_item(item_id: String, count: int = 1, include_equipped: bool = true) -> bool:
	return get_item_count(item_id, include_equipped) >= count

func get_item_count(item_id: String, include_equipped: bool = true) -> int:
	var resolved_id = _resolve_item_id(str(item_id))
	var total: int = 0
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("id", "")) != resolved_id:
			continue
		if not include_equipped and not str(entry.get("equipped_slot", "")).is_empty():
			continue
		total += ValueUtils.to_int(entry.get("count", 1), 1)
	return total

func get_inventory_dimensions() -> Vector2i:
	return Vector2i(inventory_grid_width, inventory_grid_height)

func get_visible_inventory_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if not str(entry.get("equipped_slot", "")).is_empty():
			continue
		result.append(entry.duplicate(true))
	return result

func get_inventory_item(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("instance_id", "")) == instance_id:
			return entry
	return {}

func find_first_available_item_instance(item_id: String) -> String:
	var resolved_id = _resolve_item_id(str(item_id))
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("id", "")) != resolved_id:
			continue
		if not str(entry.get("equipped_slot", "")).is_empty():
			continue
		return str(entry.get("instance_id", ""))
	return ""

func get_equipped_item_instance(slot: String) -> String:
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("equipped_slot", "")) == slot:
			return str(entry.get("instance_id", ""))
	return ""

func set_inventory_item_equipped_slot(instance_id: String, slot: String) -> bool:
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("instance_id", "")) != instance_id:
			continue
		entry["equipped_slot"] = slot
		return true
	return false

func move_item_instance(instance_id: String, target_cell: Vector2i) -> bool:
	if instance_id.is_empty():
		return false
	var active_cells: int = inventory_max_slots
	var entry := get_inventory_item(instance_id)
	if entry.is_empty():
		return false
	if not str(entry.get("equipped_slot", "")).is_empty():
		return false
	if not _can_place_entry_at(entry, target_cell, inventory_grid_width, inventory_grid_height, active_cells, instance_id):
		return false
	for entry_variant in inventory_items:
		var inventory_entry: Dictionary = entry_variant
		if str(inventory_entry.get("instance_id", "")) == instance_id:
			inventory_entry["grid_position"] = {
				"x": target_cell.x,
				"y": target_cell.y
			}
			_emit_inventory_changed()
			return true
	return false

func refresh_inventory_capacity(preserve_positions: bool = true, emit_event: bool = true) -> bool:
	var capacity: Dictionary = _resolve_inventory_capacity()
	var layout: Dictionary = _resolve_inventory_layout(
		inventory_items.duplicate(true),
		ValueUtils.to_int(capacity.get("width", inventory_grid_width), inventory_grid_width),
		ValueUtils.to_int(capacity.get("height", inventory_grid_height), inventory_grid_height),
		ValueUtils.to_int(capacity.get("active_cells", inventory_max_slots), inventory_max_slots),
		preserve_positions
	)
	if not bool(layout.get("success", false)):
		return false
	inventory_items = layout.get("items", inventory_items)
	_apply_inventory_capacity(
		ValueUtils.to_int(layout.get("width", inventory_grid_width), inventory_grid_width),
		ValueUtils.to_int(layout.get("height", inventory_grid_height), inventory_grid_height),
		ValueUtils.to_int(layout.get("active_cells", inventory_max_slots), inventory_max_slots)
	)
	if emit_event:
		_emit_inventory_changed()
	return true

func set_inventory_from_save(
	items: Array,
	active_cells: int = DEFAULT_INVENTORY_GRID_WIDTH * DEFAULT_INVENTORY_GRID_HEIGHT,
	grid_width: int = DEFAULT_INVENTORY_GRID_WIDTH,
	grid_height: int = DEFAULT_INVENTORY_GRID_HEIGHT,
	instance_counter: int = 1
) -> void:
	inventory_items.clear()
	for entry_variant in items:
		if entry_variant is Dictionary:
			var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
			_normalize_inventory_entry(entry)
			inventory_items.append(entry)
	_inventory_instance_counter = maxi(1, instance_counter)
	_apply_inventory_capacity(maxi(1, grid_width), maxi(1, grid_height), maxi(1, active_cells))
	_refresh_inventory_instance_counter()
	var layout: Dictionary = _resolve_inventory_layout(
		inventory_items.duplicate(true),
		inventory_grid_width,
		inventory_grid_height,
		inventory_max_slots,
		true
	)
	if bool(layout.get("success", false)):
		inventory_items = layout.get("items", inventory_items)

func _build_inventory_entry(item_id: String, count: int, instance_seed: int) -> Dictionary:
	return {
		"instance_id": "inv_%d" % instance_seed,
		"id": item_id,
		"count": count,
		"grid_position": {"x": -1, "y": -1},
		"rotated": false,
		"equipped_slot": ""
	}

func _normalize_inventory_entry(entry: Dictionary) -> void:
	var resolved_id = _resolve_item_id(str(entry.get("id", "")))
	entry["id"] = resolved_id
	entry["count"] = maxi(1, ValueUtils.to_int(entry.get("count", 1), 1))
	if not entry.has("instance_id") or str(entry.get("instance_id", "")).is_empty():
		entry["instance_id"] = "inv_%d" % _inventory_instance_counter
		_inventory_instance_counter += 1
	if not entry.has("grid_position") or not (entry.get("grid_position", {}) is Dictionary):
		entry["grid_position"] = {"x": -1, "y": -1}
	var grid_position: Dictionary = entry.get("grid_position", {})
	entry["grid_position"] = {
		"x": ValueUtils.to_int(grid_position.get("x", -1), -1),
		"y": ValueUtils.to_int(grid_position.get("y", -1), -1)
	}
	entry["rotated"] = bool(entry.get("rotated", false))
	entry["equipped_slot"] = str(entry.get("equipped_slot", ""))

func _emit_inventory_changed() -> void:
	if EventBus:
		EventBus.emit(EventBus.EventType.INVENTORY_CHANGED, {})

func _resolve_inventory_capacity() -> Dictionary:
	var width: int = inventory_grid_width
	var height: int = inventory_grid_height
	var active_cells: int = inventory_max_slots
	var equip_system = get_equipment_system()
	if equip_system and ItemDatabase:
		var base_size: Vector2i = ItemDatabase.get_default_inventory_grid_size()
		var backpack_id = str(equip_system.get_equipped("back"))
		if not backpack_id.is_empty():
			base_size = ItemDatabase.get_backpack_grid_size(backpack_id)
		width = maxi(1, base_size.x)
		var bonus_slots: int = 0
		if equip_system.has_method("get_total_stats"):
			bonus_slots = maxi(0, ValueUtils.to_int(equip_system.get_total_stats().get("inventory_slots", 0)))
		active_cells = maxi(1, base_size.x * base_size.y + bonus_slots)
		height = maxi(base_size.y, ceili(float(active_cells) / float(width)))
	return {
		"width": width,
		"height": height,
		"active_cells": active_cells
	}

func _apply_inventory_capacity(width: int, height: int, active_cells: int) -> void:
	inventory_grid_width = maxi(1, width)
	inventory_grid_height = maxi(1, height)
	inventory_max_slots = maxi(1, active_cells)

func _resolve_inventory_layout(
	items: Array[Dictionary],
	width: int,
	height: int,
	active_cells: int,
	preserve_positions: bool
) -> Dictionary:
	var occupancy: Dictionary = {}
	var deferred_entries: Array[Dictionary] = []
	if preserve_positions:
		for entry_variant in items:
			var entry: Dictionary = entry_variant
			_normalize_inventory_entry(entry)
			if not str(entry.get("equipped_slot", "")).is_empty():
				continue
			var position := _get_entry_grid_position(entry)
			if _can_place_entry_at(entry, position, width, height, active_cells, str(entry.get("instance_id", "")), occupancy):
				_occupy_entry(entry, occupancy, width)
			else:
				entry["grid_position"] = {"x": -1, "y": -1}
				deferred_entries.append(entry)
	else:
		for entry_variant in items:
			var entry: Dictionary = entry_variant
			_normalize_inventory_entry(entry)
			if not str(entry.get("equipped_slot", "")).is_empty():
				continue
			entry["grid_position"] = {"x": -1, "y": -1}
			deferred_entries.append(entry)

	deferred_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var size_a: Vector2i = ItemDatabase.get_inventory_footprint(str(a.get("id", ""))) if ItemDatabase else Vector2i.ONE
		var size_b: Vector2i = ItemDatabase.get_inventory_footprint(str(b.get("id", ""))) if ItemDatabase else Vector2i.ONE
		var area_a: int = size_a.x * size_a.y
		var area_b: int = size_b.x * size_b.y
		if area_a == area_b:
			if size_a.y == size_b.y:
				return str(a.get("id", "")) < str(b.get("id", ""))
			return size_a.y > size_b.y
		return area_a > area_b
	)

	for entry in deferred_entries:
		var fit_position: Vector2i = _find_first_fit_position(entry, occupancy, width, height, active_cells)
		if fit_position.x < 0 or fit_position.y < 0:
			return {"success": false}
		entry["grid_position"] = {
			"x": fit_position.x,
			"y": fit_position.y
		}
		_occupy_entry(entry, occupancy, width)

	return {
		"success": true,
		"items": items,
		"width": width,
		"height": height,
		"active_cells": active_cells
	}

func _find_first_fit_position(
	entry: Dictionary,
	occupancy: Dictionary,
	width: int,
	height: int,
	active_cells: int
) -> Vector2i:
	for y in range(height):
		for x in range(width):
			var candidate := Vector2i(x, y)
			if _can_place_entry_at(entry, candidate, width, height, active_cells, str(entry.get("instance_id", "")), occupancy):
				return candidate
	return Vector2i(-1, -1)

func _can_place_entry_at(
	entry: Dictionary,
	position: Vector2i,
	width: int,
	height: int,
	active_cells: int,
	ignore_instance_id: String = "",
	occupancy_override: Dictionary = {}
) -> bool:
	if position.x < 0 or position.y < 0:
		return false
	var occupancy: Dictionary = occupancy_override if not occupancy_override.is_empty() else _build_inventory_occupancy(ignore_instance_id)
	var footprint: Vector2i = ItemDatabase.get_inventory_footprint(str(entry.get("id", ""))) if ItemDatabase else Vector2i.ONE
	for local_y in range(footprint.y):
		for local_x in range(footprint.x):
			var cell := Vector2i(position.x + local_x, position.y + local_y)
			if not _is_inventory_cell_active(cell, width, height, active_cells):
				return false
			var cell_key: int = _inventory_cell_index(cell, width)
			if occupancy.has(cell_key):
				var occupied_by: String = str(occupancy.get(cell_key, ""))
				if ignore_instance_id.is_empty() or occupied_by != ignore_instance_id:
					return false
	return true

func _build_inventory_occupancy(ignore_instance_id: String = "") -> Dictionary:
	var occupancy: Dictionary = {}
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if not str(entry.get("equipped_slot", "")).is_empty():
			continue
		if str(entry.get("instance_id", "")) == ignore_instance_id:
			continue
		var position := _get_entry_grid_position(entry)
		if position.x < 0 or position.y < 0:
			continue
		_occupy_entry(entry, occupancy, inventory_grid_width)
	return occupancy

func _occupy_entry(entry: Dictionary, occupancy: Dictionary, width: int) -> void:
	var position := _get_entry_grid_position(entry)
	var footprint: Vector2i = ItemDatabase.get_inventory_footprint(str(entry.get("id", ""))) if ItemDatabase else Vector2i.ONE
	for local_y in range(footprint.y):
		for local_x in range(footprint.x):
			var cell := Vector2i(position.x + local_x, position.y + local_y)
			occupancy[_inventory_cell_index(cell, width)] = str(entry.get("instance_id", ""))

func _is_inventory_cell_active(cell: Vector2i, width: int, height: int, active_cells: int) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	return _inventory_cell_index(cell, width) < active_cells

func _inventory_cell_index(cell: Vector2i, width: int) -> int:
	return cell.y * width + cell.x

func _get_entry_grid_position(entry: Dictionary) -> Vector2i:
	var position: Dictionary = entry.get("grid_position", {})
	return Vector2i(
		ValueUtils.to_int(position.get("x", -1), -1),
		ValueUtils.to_int(position.get("y", -1), -1)
	)

func _refresh_inventory_instance_counter() -> void:
	for entry_variant in inventory_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)

func travel_to(location_id: String):
	player_position = location_id
	active_outdoor_location_id = location_id
	active_scene_kind = SCENE_KIND_OUTDOOR_ROOT
	
	# 通知风险系统
	if _risk_system:
		# 风险系统会通过EventBus自动处理
		pass
	
	# 更新生存系统的环境
	if _survival_status:
		var weather_module = get_node_or_null("/root/WeatherModule")
		if weather_module:
			_survival_status.ambient_temperature = weather_module.current_temperature
	
	EventBus.emit(EventBus.EventType.LOCATION_CHANGED, {"location": location_id})

# ===== 货币系统接口 =====

func add_money(amount: int) -> bool:
	if amount <= 0:
		return false
	player_money += amount
	print("[GameState] 获得金钱: %d (当前: %d)" % [amount, player_money])
	return true

func remove_money(amount: int) -> bool:
	if amount <= 0:
		return false
	if player_money < amount:
		return false
	player_money -= amount
	print("[GameState] 花费金钱: %d (剩余: %d)" % [amount, player_money])
	return true

func has_money(amount: int) -> bool:
	return player_money >= amount

func set_money(amount: int):
	player_money = maxi(0, amount)

# ===== 保存/加载 =====

func get_save_data() -> Dictionary:
	_sync_from_systems()
	_player_attributes = _get_player_attributes_container()
	
	var save_data = {
		# 基础状态
		"player_attributes": _player_attributes.duplicate(true),
		"player_hunger": player_hunger,
		"player_thirst": player_thirst,
		"player_stamina": player_stamina,
		"player_mental": player_mental,
		"player_position": player_position,
		"player_position_3d": var_to_str(player_position_3d),
		"player_grid_position": var_to_str(player_grid_position),
		"player_local_position": var_to_str(player_local_position),
		"world_mode": world_mode,
		"active_scene_kind": active_scene_kind,
		"active_outdoor_location_id": active_outdoor_location_id,
		"active_outdoor_spawn_id": active_outdoor_spawn_id,
		"overworld_pawn_cell": var_to_str(overworld_pawn_cell),
		"camera_zoom_level": camera_zoom_level,
		"current_subscene_location_id": current_subscene_location_id,
		"return_outdoor_location_id": return_outdoor_location_id,
		"return_outdoor_spawn_id": return_outdoor_spawn_id,
		"outdoor_resume_mode": outdoor_resume_mode,
		"player_money": player_money,
		
		# 等级与经验
		"player_level": player_level,
		"player_xp": player_xp,
		"player_total_xp": player_total_xp,
		
		# 时间
		"game_day": game_day,
		"game_hour": game_hour,
		"game_minute": game_minute,
		
		# 背包
		"inventory_items": inventory_items,
		"inventory_max_slots": inventory_max_slots,
		"inventory_grid_width": inventory_grid_width,
		"inventory_grid_height": inventory_grid_height,
		"inventory_instance_counter": _inventory_instance_counter,
		
		# 世界状态
		"world_weather": world_weather,
		"world_unlocked_locations": world_unlocked_locations,
		"fog_of_war_by_map": fog_of_war_by_map.duplicate(true),
		
		# 任务
		"quest_active": quest_active,
		"quest_completed": quest_completed,
		
		# 各系统数据
		"systems": {
			"time_manager": _time_manager.serialize() if _time_manager else {},
			"xp_system": _xp_system.serialize() if _xp_system else {},
			"skill_system": _skill_system.serialize() if _skill_system else {},
			"risk_system": _risk_system.serialize() if _risk_system else {}
		}
	}
	
	# 添加生存状态系统数据
	if _survival_status:
		save_data["systems"]["survival_status"] = _survival_status.serialize()
	
	return save_data

func load_save_data(data: Dictionary):
	# 基础状态
	player_hunger = data.get("player_hunger", 100)
	player_thirst = data.get("player_thirst", 100)
	player_stamina = data.get("player_stamina", 100)
	player_mental = data.get("player_mental", 100)
	player_position = data.get("player_position", "safehouse")
	player_position_3d = _deserialize_vector3(
		data.get("player_position_3d", var_to_str(Vector3.ZERO)),
		Vector3.ZERO
	)
	player_grid_position = _deserialize_vector3i(
		data.get("player_grid_position", var_to_str(Vector3i.ZERO)),
		Vector3i.ZERO
	)
	player_local_position = _deserialize_vector3(
		data.get("player_local_position", var_to_str(Vector3(0.5, 0.0, 0.5))),
		Vector3(0.5, 0.0, 0.5)
	)
	world_mode = str(data.get("world_mode", WORLD_MODE_OVERWORLD))
	active_scene_kind = str(data.get("active_scene_kind", SCENE_KIND_OUTDOOR_ROOT))
	active_outdoor_location_id = str(data.get("active_outdoor_location_id", player_position))
	active_outdoor_spawn_id = str(data.get("active_outdoor_spawn_id", "default_spawn"))
	overworld_pawn_cell = _deserialize_vector2i(
		data.get("overworld_pawn_cell", var_to_str(Vector2i.ZERO)),
		Vector2i.ZERO
	)
	camera_zoom_level = float(data.get("camera_zoom_level", 11.0))
	current_subscene_location_id = str(data.get("current_subscene_location_id", ""))
	return_outdoor_location_id = str(data.get("return_outdoor_location_id", active_outdoor_location_id))
	return_outdoor_spawn_id = str(data.get("return_outdoor_spawn_id", "default_spawn"))
	outdoor_resume_mode = str(data.get("outdoor_resume_mode", WORLD_MODE_LOCAL))
	player_money = data.get("player_money", 0)
	
	# 等级与经验
	player_level = data.get("player_level", 1)
	player_xp = data.get("player_xp", 0)
	player_total_xp = data.get("player_total_xp", 0)
	_player_attributes = AttributeSystemScript.normalize_attribute_container(data.get("player_attributes", {}))
	
	# 时间
	game_day = data.get("game_day", 1)
	game_hour = data.get("game_hour", 8)
	game_minute = data.get("game_minute", 0)
	
	# 背包
	set_inventory_from_save(
		data.get("inventory_items", []),
		ValueUtils.to_int(data.get("inventory_max_slots", inventory_max_slots), inventory_max_slots),
		ValueUtils.to_int(data.get("inventory_grid_width", inventory_grid_width), inventory_grid_width),
		ValueUtils.to_int(data.get("inventory_grid_height", inventory_grid_height), inventory_grid_height),
		ValueUtils.to_int(data.get("inventory_instance_counter", _inventory_instance_counter), _inventory_instance_counter)
	)
	
	# 世界状态
	world_weather = data.get("world_weather", "clear")
	world_unlocked_locations = data.get("world_unlocked_locations", ["safehouse"])
	fog_of_war_by_map = data.get("fog_of_war_by_map", {})
	
	# 任务
	quest_active = data.get("quest_active", [])
	quest_completed = data.get("quest_completed", [])
	
	# 加载各系统数据
	var systems_data = data.get("systems", {})
	
	if _time_manager and systems_data.has("time_manager"):
		_time_manager.deserialize(systems_data.time_manager)
	if _xp_system and systems_data.has("xp_system"):
		_xp_system.deserialize(systems_data.xp_system)
	if _skill_system and systems_data.has("skill_system"):
		_skill_system.deserialize(systems_data.skill_system)
	if _risk_system and systems_data.has("risk_system"):
		_risk_system.deserialize(systems_data.risk_system)
	if _survival_status and systems_data.has("survival_status"):
		_survival_status.deserialize(systems_data.survival_status)
	
	# 再次同步以确保一致性
	_sync_to_systems()
	refresh_inventory_capacity(true, false)
	
	print("[GameState] 存档数据已加载")
