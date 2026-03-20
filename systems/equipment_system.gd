extends Node
# EquipmentSystem - 统一装备系统
# 合并武器和装备，支持10个槽位

# 装备槽位枚举
enum EquipmentSlot {
	HEAD,       # 头部
	BODY,       # 身体
	HANDS,      # 手部
	LEGS,       # 腿部
	FEET,       # 脚部
	BACK,       # 背部
	MAIN_HAND,  # 主手（武器）
	OFF_HAND,   # 副手（武器/盾牌）
	ACCESSORY_1,# 饰品1
	ACCESSORY_2 # 饰品2
}

const SLOT_NAMES = {
	"head": "头部",
	"body": "身体",
	"hands": "手部",
	"legs": "腿部",
	"feet": "脚部",
	"back": "背部",
	"main_hand": "主手",
	"off_hand": "副手",
	"accessory_1": "饰品1",
	"accessory_2": "饰品2"
}
# ===== 信号 =====
signal item_equipped(slot: String, item_id: String)
signal item_unequipped(slot: String, item_id: String)
signal item_broken(slot: String, item_id: String)
signal durability_changed(slot: String, durability_percent: float)
signal ammo_changed(ammo_type: String, current: int, max_ammo: int)

var _equipped_items: Dictionary = {
	"head": "",
	"body": "",
	"hands": "",
	"legs": "",
	"feet": "",
	"back": "",
	"main_hand": "",
	"off_hand": "",
	"accessory_1": "",
	"accessory_2": ""
}
var _equipped_instance_ids: Dictionary = {
	"head": "",
	"body": "",
	"hands": "",
	"legs": "",
	"feet": "",
	"back": "",
	"main_hand": "",
	"off_hand": "",
	"accessory_1": "",
	"accessory_2": ""
}
var _item_instances: Dictionary = {}

func _ready():
	if GameState:
		GameState.set_equipment_system(self)
	print("[EquipmentSystem] 装备系统已初始化")
	var loaded_from_save = false
	if GameState:
		var pending_save = GameState.consume_pending_equipment_save_data()
		if not pending_save.is_empty():
			load_save_data(pending_save)
			loaded_from_save = true
	
	if not loaded_from_save:
		# 确保主手有默认武器
		if not _equipped_items.main_hand:
			_equip_item_internal("main_hand", "1001")
		
		if GameState:
			var pending_ammo = GameState.consume_pending_ammo()
			for entry in pending_ammo:
				add_ammo(str(entry.ammo_type), int(entry.count))
			
			var pending_equips = GameState.consume_pending_equips()
			for entry in pending_equips:
				equip(str(entry.item_id), str(entry.slot))

# ===== 核心接口 =====

## 装备物品
func equip(item_id: String, slot: String = ""):
	var resolved_id = ItemDatabase.resolve_item_id(item_id)
	if not ItemDatabase.has_item(resolved_id):
		print("[Equipment] 物品不存在: " + item_id)
		return false
	
	var target_instance_id: String = ""
	if resolved_id != "1001":
		if not GameState or not GameState.has_method("find_first_available_item_instance"):
			return false
		target_instance_id = GameState.find_first_available_item_instance(resolved_id)
		if target_instance_id.is_empty():
			print("[Equipment] 没有该物品: " + item_id)
			return false

	return _equip_resolved_item(resolved_id, target_instance_id, slot)

func equip_instance(instance_id: String, slot: String = "") -> bool:
	if instance_id.is_empty() or GameState == null or not GameState.has_method("get_inventory_item"):
		return false

	var entry: Dictionary = GameState.get_inventory_item(instance_id)
	if entry.is_empty():
		return false
	if not str(entry.get("equipped_slot", "")).is_empty():
		return false

	var item_id: String = str(entry.get("id", ""))
	if item_id.is_empty():
		return false
	return _equip_resolved_item(item_id, instance_id, slot)

func _equip_resolved_item(item_id: String, instance_id: String, slot: String = "") -> bool:
	var resolved_id = ItemDatabase.resolve_item_id(item_id)
	if not ItemDatabase.has_item(resolved_id):
		return false

	var item_data = ItemDatabase.get_item(resolved_id)
	var target_slot: String = slot if not slot.is_empty() else str(item_data.get("slot", ""))

	# 检查槽位是否匹配
	var item_slot: String = str(item_data.get("slot", ""))
	if item_slot != target_slot and not _is_compatible_slot(item_slot, target_slot):
		print("[Equipment] 物品不能装备到该槽位: " + resolved_id + " -> " + target_slot)
		return false

	# 检查等级要求
	var required_level: int = int(item_data.get("level_requirement", item_data.get("required_level", 0)))
	if required_level > _get_player_level():
		print("[Equipment] 等级不足")
		return false
	if resolved_id != "1001" and instance_id.is_empty():
		return false

	var inventory_snapshot: Array[Dictionary] = GameState.inventory_items.duplicate(true) if GameState else []
	var equipped_snapshot: Dictionary = _equipped_items.duplicate(true)
	var instance_snapshot: Dictionary = _equipped_instance_ids.duplicate(true)
	var durability_snapshot: Dictionary = _item_instances.duplicate(true)

	var previous_item_id: String = str(_equipped_items.get(target_slot, ""))
	var previous_instance_id: String = str(_equipped_instance_ids.get(target_slot, ""))
	if not previous_instance_id.is_empty() and GameState:
		GameState.set_inventory_item_equipped_slot(previous_instance_id, "")

	_set_slot_assignment(target_slot, resolved_id, instance_id)
	if not instance_id.is_empty() and GameState:
		GameState.set_inventory_item_equipped_slot(instance_id, target_slot)
	_ensure_item_instance(instance_id, resolved_id)

	if GameState and not GameState.refresh_inventory_capacity(true, false):
		GameState.inventory_items = inventory_snapshot
		_equipped_items = equipped_snapshot
		_equipped_instance_ids = instance_snapshot
		_item_instances = durability_snapshot
		return false

	if not previous_item_id.is_empty():
		item_unequipped.emit(target_slot, previous_item_id)
	item_equipped.emit(target_slot, resolved_id)
	print("[Equipment] 装备: " + resolved_id + " to " + target_slot)

	if CarrySystem:
		CarrySystem.on_equipment_changed()
	_apply_stats_to_game_state()
	return true
## 卸下装备
func unequip(slot: String):
	if not _equipped_items.has(slot):
		return false
	
	var current_id = str(_equipped_items.get(slot, ""))
	var current_instance_id = str(_equipped_instance_ids.get(slot, ""))
	if not current_id:
		return true  # 本来就没有装备

	var inventory_snapshot: Array[Dictionary] = GameState.inventory_items.duplicate(true) if GameState else []
	var equipped_snapshot: Dictionary = _equipped_items.duplicate(true)
	var instance_snapshot: Dictionary = _equipped_instance_ids.duplicate(true)

	if not current_instance_id.is_empty() and GameState:
		GameState.set_inventory_item_equipped_slot(current_instance_id, "")

	if slot == "main_hand":
		_set_slot_assignment("main_hand", "1001", "")
	else:
		_set_slot_assignment(slot, "", "")

	if GameState and not GameState.refresh_inventory_capacity(true, false):
		GameState.inventory_items = inventory_snapshot
		_equipped_items = equipped_snapshot
		_equipped_instance_ids = instance_snapshot
		return false

	item_unequipped.emit(slot, current_id)
	if slot == "main_hand":
		item_equipped.emit("main_hand", "1001")
	print("[Equipment] 卸下: " + current_id + " from " + slot)
	if CarrySystem:
		CarrySystem.on_equipment_changed()
	_apply_stats_to_game_state()
	return true

func unequip_to_cell(slot: String, target_cell: Vector2i) -> bool:
	if not _equipped_items.has(slot):
		return false

	var current_id: String = str(_equipped_items.get(slot, ""))
	var current_instance_id: String = str(_equipped_instance_ids.get(slot, ""))
	if current_id.is_empty() or current_instance_id.is_empty():
		return false

	var inventory_snapshot: Array[Dictionary] = GameState.inventory_items.duplicate(true) if GameState else []
	var equipped_snapshot: Dictionary = _equipped_items.duplicate(true)
	var instance_snapshot: Dictionary = _equipped_instance_ids.duplicate(true)

	if GameState:
		GameState.set_inventory_item_equipped_slot(current_instance_id, "")

	if slot == "main_hand":
		_set_slot_assignment("main_hand", "1001", "")
	else:
		_set_slot_assignment(slot, "", "")

	if GameState == null or not GameState.refresh_inventory_capacity(true, false):
		if GameState:
			GameState.inventory_items = inventory_snapshot
		_equipped_items = equipped_snapshot
		_equipped_instance_ids = instance_snapshot
		return false

	if not GameState.move_item_instance(current_instance_id, target_cell):
		GameState.inventory_items = inventory_snapshot
		_equipped_items = equipped_snapshot
		_equipped_instance_ids = instance_snapshot
		return false

	item_unequipped.emit(slot, current_id)
	if slot == "main_hand":
		item_equipped.emit("main_hand", "1001")
	print("[Equipment] 卸下到背包: " + current_id + " from " + slot)
	if CarrySystem:
		CarrySystem.on_equipment_changed()
	_apply_stats_to_game_state()
	return true

func move_equipped_item(source_slot: String, target_slot: String) -> bool:
	if not _equipped_items.has(source_slot) or not _equipped_items.has(target_slot):
		return false
	if source_slot == target_slot:
		return true

	var source_item_id: String = str(_equipped_items.get(source_slot, ""))
	var source_instance_id: String = str(_equipped_instance_ids.get(source_slot, ""))
	if source_item_id.is_empty() or source_instance_id.is_empty():
		return false
	if not _can_item_fit_slot(source_item_id, target_slot):
		return false

	var target_item_id: String = str(_equipped_items.get(target_slot, ""))
	var target_instance_id: String = str(_equipped_instance_ids.get(target_slot, ""))
	var can_swap: bool = not target_item_id.is_empty() and not target_instance_id.is_empty() and _can_item_fit_slot(target_item_id, source_slot)

	var inventory_snapshot: Array[Dictionary] = GameState.inventory_items.duplicate(true) if GameState else []
	var equipped_snapshot: Dictionary = _equipped_items.duplicate(true)
	var instance_snapshot: Dictionary = _equipped_instance_ids.duplicate(true)

	if GameState:
		GameState.set_inventory_item_equipped_slot(source_instance_id, "")
		if not target_instance_id.is_empty():
			GameState.set_inventory_item_equipped_slot(target_instance_id, "")

	_set_slot_assignment(target_slot, source_item_id, source_instance_id)
	if GameState:
		GameState.set_inventory_item_equipped_slot(source_instance_id, target_slot)

	if can_swap:
		_set_slot_assignment(source_slot, target_item_id, target_instance_id)
		if GameState:
			GameState.set_inventory_item_equipped_slot(target_instance_id, source_slot)
	else:
		if source_slot == "main_hand":
			_set_slot_assignment("main_hand", "1001", "")
		else:
			_set_slot_assignment(source_slot, "", "")

	if GameState == null or not GameState.refresh_inventory_capacity(true, false):
		if GameState:
			GameState.inventory_items = inventory_snapshot
		_equipped_items = equipped_snapshot
		_equipped_instance_ids = instance_snapshot
		return false

	item_unequipped.emit(source_slot, source_item_id)
	if not target_item_id.is_empty():
		item_unequipped.emit(target_slot, target_item_id)
	if can_swap:
		item_equipped.emit(source_slot, target_item_id)
	elif source_slot == "main_hand":
		item_equipped.emit("main_hand", "1001")
	item_equipped.emit(target_slot, source_item_id)
	print("[Equipment] 装备槽调整: " + source_slot + " -> " + target_slot)

	if CarrySystem:
		CarrySystem.on_equipment_changed()
	_apply_stats_to_game_state()
	return true

## 获取当前装备
func get_equipped(slot: String):
	var value = _equipped_items.get(slot, "")
	return "" if value == null else str(value)

## 兼容旧接口
func get_equipped_item(slot: String):
	return get_equipped(slot)

## 获取装备数据
func get_item_data(item_id: String):
	return ItemDatabase.get_item(item_id)

## 获取槽位中的完整数据
func get_equipped_data(slot: String):
	var item_id = str(_equipped_items.get(slot, ""))
	if not item_id:
		return {}
	
	var base_data = ItemDatabase.get_item(item_id).duplicate()
	base_data.id = item_id
	
	# 添加实例数据（耐久等）
	var instance_id: String = str(_equipped_instance_ids.get(slot, ""))
	if not instance_id.is_empty():
		base_data.instance_id = instance_id
	if _item_instances.has(instance_id):
		base_data.current_durability = _item_instances[instance_id].durability
	
	return base_data

# ===== 战斗属性计算 =====

## 计算战斗属性
func calculate_combat_stats():
	var stats = {
		"damage": 0,
		"attack_speed": 1.0,
		"range": 1,
		"defense": 0,
		"crit_chance": 0.05,
		"crit_multiplier": 1.5,
		"stamina_cost": 0,
		"carry_bonus": 0.0
	}
	
	# 主手武器
	var main_hand_data = get_equipped_data("main_hand")
	if main_hand_data && main_hand_data.get("type") == "weapon":
		var weapon = main_hand_data.get("weapon_data", {})
		stats.damage = weapon.get("damage", 0)
		stats.attack_speed = weapon.get("attack_speed", 1.0)
		stats.range = weapon.get("range", 1)
		stats.crit_chance = weapon.get("crit_chance", 0.05)
		stats.crit_multiplier = weapon.get("crit_multiplier", 1.5)
		stats.stamina_cost = weapon.get("stamina_cost", 0)
	
	# 防具加成
	for slot in _equipped_items.keys():
		var item_data = get_equipped_data(slot)
		if item_data && item_data.size() > 0:
			var bonuses = _get_attributes_bonus(item_data)
			stats.defense += bonuses.get("defense", 0)

	stats.carry_bonus = calculate_carry_bonus()
	
	return stats

## 计算总负重
func calculate_total_weight():
	var total = 0.0
	for slot in _equipped_items.keys():
		var item_id = _equipped_items[slot]
		if item_id && ItemDatabase.has_item(item_id):
			total += ItemDatabase.get_item_weight(item_id)
	return total

## 计算负重加成
func calculate_carry_bonus():
	var bonus = 0.0
	
	for slot in _equipped_items.keys():
		var item_data = get_equipped_data(slot)
		if item_data && item_data.size() > 0:
			var bonuses = _get_attributes_bonus(item_data)
			bonus += bonuses.get("carry_bonus", 0.0)
	
	return bonus

# ===== 耐久度系统 =====

## 消耗耐久
func consume_durability(slot: String, amount: int = 1):
	var item_id = str(_equipped_items.get(slot, ""))
	var instance_id = str(_equipped_instance_ids.get(slot, ""))
	if item_id.is_empty() or instance_id.is_empty() or not _item_instances.has(instance_id):
		return
	
	var instance = _item_instances[instance_id]
	instance.durability = maxi(0, instance.durability - amount)
	
	var max_dur = ItemDatabase.get_max_durability(item_id)
	if max_dur <= 0:
		return
	var percent = float(instance.durability) / max_dur
	durability_changed.emit(slot, percent)
	
	if instance.durability <= 0:
		_item_broken(slot, item_id)

## 修复装备
func repair(slot: String):
	var item_id = str(_equipped_items.get(slot, ""))
	var instance_id = str(_equipped_instance_ids.get(slot, ""))
	if not item_id:
		return false
	
	var item_data = ItemDatabase.get_item(item_id)
	var repair_materials = item_data.get("repair_materials", [])
	var max_durability = ItemDatabase.get_max_durability(item_id)
	
	# 检查材料
	for material in repair_materials:
		var material_id = ItemDatabase.resolve_item_id(material.item)
		if not InventoryModule.has_item(material.item, material.count) and not InventoryModule.has_item(material_id, material.count):
			return false
	
	# 消耗材料
	for material in repair_materials:
		var material_id = ItemDatabase.resolve_item_id(material.item)
		if InventoryModule.has_item(material.item, material.count):
			InventoryModule.remove_item(material.item, material.count)
		else:
			InventoryModule.remove_item(material_id, material.count)
	
	# 恢复耐久
	if instance_id.is_empty():
		return false
	if not _item_instances.has(instance_id):
		_item_instances[instance_id] = {"durability": max_durability}
	else:
		_item_instances[instance_id].durability = max_durability
	
	print("[Equipment] 修复: " + item_id)
	return true

## 修复指定物品（不要求已装备）
func repair_item(item_id: String, instance_id: String = ""):
	var resolved_id = ItemDatabase.resolve_item_id(item_id)
	if not ItemDatabase.has_item(resolved_id):
		return false
	var item_data = ItemDatabase.get_item(resolved_id)
	var repair_materials = item_data.get("repair_materials", [])
	var max_durability = ItemDatabase.get_max_durability(resolved_id)
	
	for material in repair_materials:
		var material_id = ItemDatabase.resolve_item_id(material.item)
		if not InventoryModule.has_item(material.item, material.count) and not InventoryModule.has_item(material_id, material.count):
			return false
	
	for material in repair_materials:
		var material_id = ItemDatabase.resolve_item_id(material.item)
		if InventoryModule.has_item(material.item, material.count):
			InventoryModule.remove_item(material.item, material.count)
		else:
			InventoryModule.remove_item(material_id, material.count)
	
	var resolved_instance_id: String = instance_id
	if resolved_instance_id.is_empty():
		resolved_instance_id = _find_instance_for_item(resolved_id)
	if resolved_instance_id.is_empty():
		return false
	_item_instances[resolved_instance_id] = {"durability": max_durability}
	return true

# ===== 弹药系统 =====

## 当前弹药
var _current_ammo: Dictionary = {
	"1009": 0,   # ammo_pistol
	"1021": 0,   # ammo_shotgun
	"1022": 0,   # ammo_rifle
	"1023": 999  # stone 无限
}

## 添加弹药
func add_ammo(ammo_type: String, count: int = 1):
	var resolved = ItemDatabase.resolve_item_id(ammo_type)
	_current_ammo[resolved] = _current_ammo.get(resolved, 0) + count
	var max_ammo = _get_max_ammo_capacity(resolved)
	ammo_changed.emit(resolved, _current_ammo[resolved], max_ammo)

## 消耗弹药
func consume_ammo(ammo_type: String, count: int = 1):
	var resolved = ItemDatabase.resolve_item_id(ammo_type)
	if _current_ammo.get(resolved, 0) >= count:
		_current_ammo[resolved] -= count
		var max_ammo = _get_max_ammo_capacity(resolved)
		ammo_changed.emit(resolved, _current_ammo[resolved], max_ammo)
		return true
	return false

## 获取当前弹药
func get_ammo(ammo_type: String):
	var resolved = ItemDatabase.resolve_item_id(ammo_type)
	return _current_ammo.get(resolved, 0)

## 获取总属性
func get_total_stats():
	var stats = {
		"damage": 0,
		"defense": 0,
		"damage_reduction": 0.0,
		"carry_bonus": 0.0,
		"insulation": 0.0,
		"speed_bonus": 0.0,
		"speed_penalty": 0.0,
		"accuracy": 0,
		"crit_chance": 0.0,
		"max_hp": 0,
		"melee_damage": 0.0,
		"inventory_slots": 0,
		"radiation_resistance": 0.0,
		"disease_resistance": 0.0,
		"stamina_efficiency": 0.0,
		"hunger_efficiency": 0.0,
		"thirst_efficiency": 0.0,
		"headshot_protection": 0.0,
		"noise_reduction": 0.0,
		"reload_speed": 0.0,
		"ammo_capacity": 0.0
	}
	
	# 主手武器伤害
	var main_hand_data = get_equipped_data("main_hand")
	if main_hand_data && main_hand_data.get("type") == "weapon":
		stats.damage = main_hand_data.get("weapon_data", {}).get("damage", 0)
	
	# 防具加成
	for slot in _equipped_items.keys():
		var item_data = get_equipped_data(slot)
		if item_data && item_data.size() > 0:
			var bonuses = _get_attributes_bonus(item_data)
			for key in bonuses.keys():
				if stats.has(key):
					stats[key] += bonuses[key]
	
	# 负重加成
	stats.carry_bonus = calculate_carry_bonus()
	
	return stats

func get_attribute_modifier_payload() -> Dictionary:
	var total_stats: Dictionary = get_total_stats()
	var combat_stats: Dictionary = calculate_combat_stats()
	var flat: Dictionary = {
		"attack_power": float(total_stats.get("damage", 0)),
		"defense": float(total_stats.get("defense", 0)),
		"accuracy": float(total_stats.get("accuracy", 0)),
		"crit_chance": float(total_stats.get("crit_chance", 0.0)),
		"max_hp": float(total_stats.get("max_hp", 0)),
		"damage_reduction": float(total_stats.get("damage_reduction", 0.0)),
		"carry_weight": float(total_stats.get("carry_bonus", 0.0))
	}
	var crit_multiplier: float = float(combat_stats.get("crit_multiplier", 1.5))
	if crit_multiplier > 1.5:
		flat["crit_damage"] = crit_multiplier - 1.5
	var mult: Dictionary = {}
	if float(total_stats.get("speed_bonus", 0.0)) != 0.0:
		mult["speed"] = float(mult.get("speed", 0.0)) + float(total_stats.get("speed_bonus", 0.0))
	if float(total_stats.get("speed_penalty", 0.0)) != 0.0:
		mult["speed"] = float(mult.get("speed", 0.0)) - float(total_stats.get("speed_penalty", 0.0))
	if float(total_stats.get("melee_damage", 0.0)) != 0.0:
		mult["attack_power"] = float(mult.get("attack_power", 0.0)) + float(total_stats.get("melee_damage", 0.0))
	return {
		"flat": flat,
		"mult": mult,
		"resources": {}
	}

## 当受到伤害时（消耗装备耐久）
func on_damage_taken(damage: int):
	var slots = ["head", "body", "hands", "legs", "feet"]
	for slot in slots:
		if _equipped_items.get(slot):
			var durability_loss = int(damage * 0.1)  # 10%伤害转化为耐久损失
			if durability_loss > 0:
				consume_durability(slot, durability_loss)

## 装填弹药
func reload_weapon():
	var main_hand = get_equipped_data("main_hand")
	if not main_hand || main_hand.get("type") != "weapon":
		return {"success": false, "message": "没有装备武器"}
	
	var weapon_data = main_hand.get("weapon_data", {})
	var ammo_type = ItemDatabase.resolve_item_id(str(weapon_data.get("ammo_type", "")))
	
	if not ammo_type:
		return {"success": false, "message": "不需要弹药"}
	
	var max_ammo = weapon_data.get("max_ammo", 0)
	var current_ammo = _current_ammo.get(ammo_type, 0)
	
	if current_ammo <= 0:
		return {"success": false, "message": "没有弹药"}
	
	var to_load = mini(current_ammo, max_ammo)
	_current_ammo[ammo_type] -= to_load
	
	# 这里应该跟踪武器中的弹药，简化处理
	ammo_changed.emit(ammo_type, _current_ammo[ammo_type], max_ammo)
	
	return {"success": true, "ammo_loaded": to_load}

# ===== 私有方法 =====

func _equip_item_internal(slot: String, item_id: String, instance_id: String = ""):
	_set_slot_assignment(slot, item_id, instance_id)
	_ensure_item_instance(instance_id, item_id)
	item_equipped.emit(slot, item_id)
	if CarrySystem:
		CarrySystem.on_equipment_changed()
	_apply_stats_to_game_state()
	return true

func _is_compatible_slot(item_slot: String, target_slot: String):
	# 武器可以装备到主手或副手
	if item_slot == "main_hand" && target_slot in ["main_hand", "off_hand"]:
		return true
	# 饰品可以装备到饰品槽
	if item_slot == "accessory" && target_slot in ["accessory_1", "accessory_2"]:
		return true
	return item_slot == target_slot

func _can_item_fit_slot(item_id: String, target_slot: String) -> bool:
	if item_id.is_empty():
		return false
	var item_slot: String = ItemDatabase.get_equip_slot(item_id)
	return _is_compatible_slot(item_slot, target_slot)

func _item_broken(slot: String, item_id: String):
	item_broken.emit(slot, item_id)
	print("[Equipment] 装备损坏: " + item_id)
	# 卸下损坏的装备
	unequip(slot)

func _get_player_level():
	# 简化实现
	return 1

func _get_max_ammo_capacity(ammo_type: String):
	var main_hand = get_equipped_data("main_hand")
	if main_hand && main_hand.get("type") == "weapon":
		var weapon_ammo = ItemDatabase.resolve_item_id(str(main_hand.get("weapon_data", {}).get("ammo_type", "")))
		if weapon_ammo == ammo_type:
			return main_hand.get("weapon_data", {}).get("max_ammo", 0)
	return 0

func _get_attributes_bonus(item_data: Dictionary) -> Dictionary:
	if item_data.has("attributes_bonus") and item_data.attributes_bonus is Dictionary:
		return item_data.attributes_bonus
	if item_data.has("armor_data") and item_data.armor_data is Dictionary:
		return item_data.armor_data
	return {}

func _apply_stats_to_game_state():
	if GameState:
		GameState.apply_player_attribute_delta("equipment_system", get_attribute_modifier_payload())
		if GameState.has_method("refresh_inventory_capacity"):
			GameState.refresh_inventory_capacity(true, false)

func _set_slot_assignment(slot: String, item_id: String, instance_id: String) -> void:
	_equipped_items[slot] = item_id
	_equipped_instance_ids[slot] = instance_id

func _ensure_item_instance(instance_id: String, item_id: String) -> void:
	if instance_id.is_empty() or item_id.is_empty():
		return
	if _item_instances.has(instance_id):
		return

	var max_dur = ItemDatabase.get_max_durability(item_id)
	var legacy_key = item_id if _item_instances.has(item_id) else ""
	if not legacy_key.is_empty():
		var legacy_data: Dictionary = _item_instances.get(legacy_key, {}).duplicate(true)
		_item_instances.erase(legacy_key)
		_item_instances[instance_id] = {
			"durability": int(legacy_data.get("durability", max_dur if max_dur > 0 else -1)),
			"enhancements": legacy_data.get("enhancements", []).duplicate(true)
		}
		return

	_item_instances[instance_id] = {
		"durability": max_dur if max_dur > 0 else -1,
		"enhancements": []
	}

func _find_instance_for_item(item_id: String) -> String:
	for slot in _equipped_items.keys():
		if str(_equipped_items.get(slot, "")) == item_id:
			return str(_equipped_instance_ids.get(slot, ""))
	if GameState and GameState.has_method("find_first_available_item_instance"):
		return str(GameState.find_first_available_item_instance(item_id))
	return ""

func on_inventory_item_removed(instance_id: String, slot: String, item_id: String) -> void:
	if instance_id.is_empty() or slot.is_empty():
		return
	if str(_equipped_instance_ids.get(slot, "")) != instance_id:
		return
	if slot == "main_hand":
		_set_slot_assignment("main_hand", "1001", "")
		item_equipped.emit("main_hand", "1001")
	else:
		_set_slot_assignment(slot, "", "")
	item_unequipped.emit(slot, item_id)
	if CarrySystem:
		CarrySystem.on_equipment_changed()
	_apply_stats_to_game_state()

# ===== 存档接口 =====

func get_save_data():
	return {
		"equipped_items": _equipped_items.duplicate(),
		"equipped_instance_ids": _equipped_instance_ids.duplicate(),
		"item_instances": _item_instances.duplicate(),
		"current_ammo": _current_ammo.duplicate()
	}

func load_save_data(data: Dictionary):
	_equipped_items = data.get("equipped_items", _equipped_items)
	_equipped_instance_ids = data.get("equipped_instance_ids", _equipped_instance_ids)
	_item_instances = data.get("item_instances", {})
	for slot in _equipped_items.keys():
		var raw_item = _equipped_items.get(slot, "")
		_equipped_items[slot] = "" if raw_item == null else str(raw_item)
		var raw_instance = _equipped_instance_ids.get(slot, "")
		_equipped_instance_ids[slot] = "" if raw_instance == null else str(raw_instance)
	var loaded_ammo: Dictionary = data.get("current_ammo", _current_ammo)
	_current_ammo = {}
	for ammo_key in loaded_ammo.keys():
		var resolved_key = ItemDatabase.resolve_item_id(str(ammo_key))
		_current_ammo[resolved_key] = loaded_ammo[ammo_key]
	
	# 确保主手有武器
	if not _equipped_items.get("main_hand"):
		_set_slot_assignment("main_hand", "1001", "")

	for slot in _equipped_items.keys():
		var item_id: String = str(_equipped_items.get(slot, ""))
		if item_id.is_empty() or item_id == "1001":
			_equipped_instance_ids[slot] = ""
			continue
		var instance_id: String = str(_equipped_instance_ids.get(slot, ""))
		if instance_id.is_empty() and GameState and GameState.has_method("get_equipped_item_instance"):
			instance_id = str(GameState.get_equipped_item_instance(slot))
		if instance_id.is_empty() and GameState and GameState.has_method("find_first_available_item_instance"):
			instance_id = str(GameState.find_first_available_item_instance(item_id))
		_equipped_instance_ids[slot] = instance_id
		if not instance_id.is_empty() and GameState and GameState.has_method("set_inventory_item_equipped_slot"):
			GameState.set_inventory_item_equipped_slot(instance_id, slot)
		_ensure_item_instance(instance_id, item_id)

	if GameState and GameState.has_method("refresh_inventory_capacity"):
		GameState.refresh_inventory_capacity(true, false)
	_apply_stats_to_game_state()
	
	print("[EquipmentSystem] 装备数据已加载")

## 执行攻击 (兼容旧WeaponSystem接口)
func perform_attack():
	var main_hand = get_equipped_data("main_hand")
	if not main_hand || main_hand.get("type") != "weapon":
		return {"success": false, "message": "没有装备武器"}
	
	var weapon_data = main_hand.get("weapon_data", {})
	var ammo_type = ItemDatabase.resolve_item_id(str(weapon_data.get("ammo_type", "")))
	
	# 检查弹药
	if ammo_type && ammo_type != "":
		if _current_ammo.get(ammo_type, 0) <= 0:
			return {"success": false, "message": "没有弹药"}
		_current_ammo[ammo_type] -= 1
		ammo_changed.emit(ammo_type, _current_ammo[ammo_type], weapon_data.get("max_ammo", 0))
	
	# 计算伤害
	var damage = weapon_data.get("damage", 5)
	var crit_chance = weapon_data.get("crit_chance", 0.05)
	var is_critical = randf() < crit_chance
	
	if is_critical:
		damage = int(damage * weapon_data.get("crit_multiplier", 1.5))
	
	# 消耗耐久
	consume_durability("main_hand", 1)
	
	# 应用特效
	var effects_applied = []
	for effect in main_hand.get("special_effects", []):
		match effect:
			"bleeding":
				effects_applied.append({"type": "bleeding", "damage": main_hand.get("effect_data", {}).get("bleeding_damage", 2)})
			"stun":
				if randf() < main_hand.get("effect_data", {}).get("stun_chance", 0.2):
					effects_applied.append({"type": "stun", "duration": 1})
	
	return {
		"success": true,
		"damage": damage,
		"is_critical": is_critical,
		"effects_applied": effects_applied
	}


