extends Node
# GameState - 游戏全局状态管理
# 最佳实践: 不使用 class_name，直接暴露变量

# ===== 玩家状态 =====
var player_hp: int = 100
var player_max_hp: int = 100
var player_hunger: int = 100
var player_thirst: int = 100
var player_stamina: int = 100
var player_mental: int = 100
var player_position: String = "safehouse"
var player_position_3d: Vector3 = Vector3.ZERO
var player_grid_position: Vector3i = Vector3i.ZERO
var is_player_moving: bool = false
var player_defense: int = 0  # 装备提供的防御力

func save_3d_position(pos: Vector3, grid_pos: Vector3i) -> void:
	player_position_3d = pos
	player_grid_position = grid_pos

func get_saved_3d_position() -> Vector3:
	return player_position_3d

# ===== 货币系统 =====
var player_money: int = 0

# ===== 新系统：等级与经验值 =====
var player_level: int = 1
var player_xp: int = 0
var player_total_xp: int = 0
var player_available_stat_points: int = 0
var player_available_skill_points: int = 0

# ===== 新系统：属性点 =====
var player_strength: int = 5
var player_agility: int = 5
var player_constitution: int = 5

# ===== 新系统：时间 =====
var game_day: int = 1
var game_hour: int = 8
var game_minute: int = 0

# ===== 背包状态 =====
var inventory_items: Array[Dictionary] = []
var inventory_max_slots: int = 20

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

func _ready():
	print("[GameState] Initialized")
	
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
		_attr_system.attribute_changed.connect(_on_attribute_changed)
	
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
		_attr_system.set_attributes(player_strength, player_agility, player_constitution)

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
		player_strength = _attr_system.strength
		player_agility = _attr_system.agility
		player_constitution = _attr_system.constitution

# ===== 信号处理 =====

func _on_level_up(new_level: int, rewards: Dictionary):
	player_level = new_level
	
	# 应用状态恢复
	if rewards.has("hp_restored"):
		heal_player(int(player_max_hp * rewards.hp_restored / 100.0))
	if rewards.has("stamina_restored"):
		player_stamina = mini(100, player_stamina + int(100 * rewards.stamina_restored / 100.0))
	if rewards.has("mental_restored"):
		player_mental = mini(100, player_mental + int(100 * rewards.mental_restored / 100.0))
	
	print("[GameState] 玩家升级到等级 %d" % new_level)

func _on_xp_gained(amount: int, source: String, total_xp: int):
	player_xp = total_xp
	player_total_xp += amount

func _on_attribute_changed(attr_name: String, new_value: int, old_value: int):
	# 更新GameState中的属性值
	match attr_name:
		"strength":
			player_strength = new_value
			# 更新最大负重等
		"agility":
			player_agility = new_value
			# 更新闪避等
		"constitution":
			player_constitution = new_value
			# 更新最大HP
			_update_max_hp_from_constitution()

func _on_status_warning(warning_type: String, severity: String):
	# 状态警告通过EventBus传播
	EventBus.emit(EventBus.EventType.STATUS_WARNING, {
		"type": warning_type,
		"severity": severity,
		"location": player_position
	})

func _update_max_hp_from_constitution():
	if _attr_system:
		var old_max = player_max_hp
		player_max_hp = 100 + _attr_system.calculate_hp_bonus()
		# 按比例调整当前HP
		if old_max > 0:
			player_hp = int(player_hp * player_max_hp / old_max)
		else:
			player_hp = player_max_hp

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
	# 计算防御减免
	var actual_damage = amount
	if player_defense > 0:
		actual_damage = maxi(1, amount - player_defense / 2)  # 每2点防御减免1点伤害
	
	# 检查装备的伤害减免效果
	var equipment_stats = EquipmentSystem.get_total_stats()
	if equipment_stats.damage_reduction > 0:
		actual_damage = int(actual_damage * (1.0 - equipment_stats.damage_reduction))
	
	# 应用属性系统的伤害减免
	if _attr_system:
		actual_damage = int(actual_damage * (1.0 - _attr_system.calculate_damage_reduction()))
	
	player_hp = maxi(0, player_hp - actual_damage)
	
	# 减少装备耐久
	EquipmentSystem.on_damage_taken(actual_damage)
	
	# 受伤影响生存状态
	if _survival_status:
		_survival_status.immunity = maxf(0, _survival_status.immunity - 5.0)
		_survival_status.fatigue = mini(_survival_status.FATIGUE_MAX, _survival_status.fatigue + 10)
	
	EventBus.emit(EventBus.EventType.PLAYER_HURT, {"hp": player_hp, "damage": actual_damage})

func heal_player(amount: int):
	player_hp = mini(player_max_hp, player_hp + amount)
	EventBus.emit(EventBus.EventType.PLAYER_HEALED, {"hp": player_hp, "amount": amount})

func add_item(item_id: String, count: int = 1):
	# 应用拾荒技能加成
	if _skill_system and _skill_system.get_loot_bonus_chance() > 0:
		if randf() < _skill_system.get_loot_bonus_chance():
			count += 1
			print("[GameState] 拾荒技能触发，额外获得1个物品")
	
	# 查找是否已存在
	for item in inventory_items:
		if item.id == item_id:
			item.count += count
			EventBus.emit(EventBus.EventType.INVENTORY_CHANGED, {})
			return true
	
	# 检查背包空间
	if inventory_items.size() >= inventory_max_slots:
		return false
	
	inventory_items.append({"id": item_id, "count": count})
	EventBus.emit(EventBus.EventType.INVENTORY_CHANGED, {})
	return true

func remove_item(item_id: String, count: int = 1):
	for i in range(inventory_items.size()):
		if inventory_items[i].id == item_id:
			inventory_items[i].count -= count
			if inventory_items[i].count <= 0:
				inventory_items.remove_at(i)
			EventBus.emit(EventBus.EventType.INVENTORY_CHANGED, {})
			return true
	return false

func has_item(item_id: String, count: int = 1):
	for item in inventory_items:
		if item.id == item_id and item.count >= count:
			return true
	return false

func travel_to(location_id: String):
	player_position = location_id
	
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
	
	var save_data = {
		# 基础状态
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"player_hunger": player_hunger,
		"player_thirst": player_thirst,
		"player_stamina": player_stamina,
		"player_mental": player_mental,
		"player_position": player_position,
		"player_defense": player_defense,
		"player_money": player_money,
		
		# 等级与经验
		"player_level": player_level,
		"player_xp": player_xp,
		"player_total_xp": player_total_xp,
		
		# 属性
		"player_strength": player_strength,
		"player_agility": player_agility,
		"player_constitution": player_constitution,
		
		# 时间
		"game_day": game_day,
		"game_hour": game_hour,
		"game_minute": game_minute,
		
		# 背包
		"inventory_items": inventory_items,
		
		# 世界状态
		"world_weather": world_weather,
		"world_unlocked_locations": world_unlocked_locations,
		
		# 任务
		"quest_active": quest_active,
		"quest_completed": quest_completed,
		
		# 各系统数据
		"systems": {
			"time_manager": _time_manager.serialize() if _time_manager else {},
			"xp_system": _xp_system.serialize() if _xp_system else {},
			"attr_system": _attr_system.serialize() if _attr_system else {},
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
	player_hp = data.get("player_hp", 100)
	player_max_hp = data.get("player_max_hp", 100)
	player_hunger = data.get("player_hunger", 100)
	player_thirst = data.get("player_thirst", 100)
	player_stamina = data.get("player_stamina", 100)
	player_mental = data.get("player_mental", 100)
	player_position = data.get("player_position", "safehouse")
	player_defense = data.get("player_defense", 0)
	player_money = data.get("player_money", 0)
	
	# 等级与经验
	player_level = data.get("player_level", 1)
	player_xp = data.get("player_xp", 0)
	player_total_xp = data.get("player_total_xp", 0)
	
	# 属性
	player_strength = data.get("player_strength", 5)
	player_agility = data.get("player_agility", 5)
	player_constitution = data.get("player_constitution", 5)
	
	# 时间
	game_day = data.get("game_day", 1)
	game_hour = data.get("game_hour", 8)
	game_minute = data.get("game_minute", 0)
	
	# 背包
	inventory_items = data.get("inventory_items", [])
	
	# 世界状态
	world_weather = data.get("world_weather", "clear")
	world_unlocked_locations = data.get("world_unlocked_locations", ["safehouse"])
	
	# 任务
	quest_active = data.get("quest_active", [])
	quest_completed = data.get("quest_completed", [])
	
	# 加载各系统数据
	var systems_data = data.get("systems", {})
	
	if _time_manager and systems_data.has("time_manager"):
		_time_manager.deserialize(systems_data.time_manager)
	if _xp_system and systems_data.has("xp_system"):
		_xp_system.deserialize(systems_data.xp_system)
	if _attr_system and systems_data.has("attr_system"):
		_attr_system.deserialize(systems_data.attr_system)
	if _skill_system and systems_data.has("skill_system"):
		_skill_system.deserialize(systems_data.skill_system)
	if _risk_system and systems_data.has("risk_system"):
		_risk_system.deserialize(systems_data.risk_system)
	if _survival_status and systems_data.has("survival_status"):
		_survival_status.deserialize(systems_data.survival_status)
	
	# 再次同步以确保一致性
	_sync_to_systems()
	
	print("[GameState] 存档数据已加载")
