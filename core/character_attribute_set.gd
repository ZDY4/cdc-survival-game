extends RefCounted
# CharacterAttributeSet - 角色属性集合
# 管理角色的基础属性：HP、饥饿、口渴、体力、精神等
# 可以被玩家、NPC、敌人等任何角色使用

signal attribute_changed(attribute_name: String, new_value: float, old_value: float)
signal attribute_max_changed(attribute_name: String, new_max: float)
signal attribute_depleted(attribute_name: String)  # 属性归零时触发

# ===== 基础属性 =====
var hp: float = 100.0
var max_hp: float = 100.0

var hunger: float = 100.0
var max_hunger: float = 100.0

var thirst: float = 100.0
var max_thirst: float = 100.0

var stamina: float = 100.0
var max_stamina: float = 100.0

var mental: float = 100.0
var max_mental: float = 100.0

# ===== 战斗属性 =====
var defense: float = 0.0
var attack_power: float = 10.0
var speed: float = 10.0

# ===== 可选属性 =====
var body_temperature: float = 36.5  # 体温
var radiation_level: float = 0.0    # 辐射值
var disease_resistance: float = 0.0 # 疾病抗性

# ===== 属性标签（用于特殊效果）=====
var active_effects: Array[Dictionary] = []

func _init(initial_values: Dictionary = {}):
	# 使用传入的初始值设置属性
	for key in initial_values.keys():
		if key in self:
			set(key, initial_values[key])

# ===== HP 管理 =====

func damage(amount: float) -> float:
	var old_hp = hp
	
	# 计算防御减免
	var actual_damage = maxf(1.0, amount - defense / 2.0)
	
	hp = maxf(0.0, hp - actual_damage)
	attribute_changed.emit("hp", hp, old_hp)
	
	if hp <= 0.0:
		attribute_depleted.emit("hp")
	
	return actual_damage

func heal(amount: float) -> void:
	var old_hp = hp
	hp = minf(max_hp, hp + amount)
	attribute_changed.emit("hp", hp, old_hp)

func set_max_hp(new_max: float) -> void:
	var old_max = max_hp
	max_hp = new_max
	hp = minf(hp, max_hp)  # 确保当前HP不超过新最大值
	attribute_max_changed.emit("hp", max_hp)

func is_alive():
	return hp > 0.0

func get_hp_percent() -> float:
	return (hp / max_hp) if max_hp > 0 else 0.0

# ===== 饥饿管理 =====

func consume_hunger(amount: float) -> void:
	var old_hunger = hunger
	hunger = maxf(0.0, hunger - amount)
	attribute_changed.emit("hunger", hunger, old_hunger)
	
	if hunger <= 0.0:
		attribute_depleted.emit("hunger")

func restore_hunger(amount: float) -> void:
	var old_hunger = hunger
	hunger = minf(max_hunger, hunger + amount)
	attribute_changed.emit("hunger", hunger, old_hunger)

func is_starving() -> bool:
	return hunger <= 0.0

func get_hunger_percent() -> float:
	return (hunger / max_hunger) if max_hunger > 0 else 0.0

# ===== 口渴管理 =====

func consume_thirst(amount: float) -> void:
	var old_thirst = thirst
	thirst = maxf(0.0, thirst - amount)
	attribute_changed.emit("thirst", thirst, old_thirst)
	
	if thirst <= 0.0:
		attribute_depleted.emit("thirst")

func restore_thirst(amount: float) -> void:
	var old_thirst = thirst
	thirst = minf(max_thirst, thirst + amount)
	attribute_changed.emit("thirst", thirst, old_thirst)

func is_dehydrated() -> bool:
	return thirst <= 0.0

func get_thirst_percent() -> float:
	return (thirst / max_thirst) if max_thirst > 0 else 0.0

# ===== 体力管理 =====

func consume_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	
	var old_stamina = stamina
	stamina = maxf(0.0, stamina - amount)
	attribute_changed.emit("stamina", stamina, old_stamina)
	
	if stamina <= 0.0:
		attribute_depleted.emit("stamina")
	
	return true

func restore_stamina(amount: float) -> void:
	var old_stamina = stamina
	stamina = minf(max_stamina, stamina + amount)
	attribute_changed.emit("stamina", stamina, old_stamina)

func has_enough_stamina(amount: float) -> bool:
	return stamina >= amount

func get_stamina_percent() -> float:
	return (stamina / max_stamina) if max_stamina > 0 else 0.0

# ===== 精神管理 =====

func damage_mental(amount: float) -> void:
	var old_mental = mental
	mental = maxf(0.0, mental - amount)
	attribute_changed.emit("mental", mental, old_mental)
	
	if mental <= 0.0:
		attribute_depleted.emit("mental")

func restore_mental(amount: float) -> void:
	var old_mental = mental
	mental = minf(max_mental, mental + amount)
	attribute_changed.emit("mental", mental, old_mental)

func is_insane() -> bool:
	return mental <= 0.0

func get_mental_percent() -> float:
	return (mental / max_mental) if max_mental > 0 else 0.0

# ===== 属性效果 =====

func add_effect(effect: Dictionary) -> void:
	active_effects.append(effect)
	_apply_effect(effect)

func remove_effect(effect_id: String) -> void:
	for i in range(active_effects.size()):
		if active_effects[i].get("id") == effect_id:
			_remove_effect(active_effects[i])
			active_effects.remove_at(i)
			break

func _apply_effect(effect: Dictionary) -> void:
	match effect.get("type"):
		"max_hp_boost":
			set_max_hp(max_hp + effect.get("amount", 0))
		"defense_boost":
			defense += effect.get("amount", 0)
		"speed_boost":
			speed += effect.get("amount", 0)
		"regeneration":
			# 由外部定时调用
			pass

func _remove_effect(effect: Dictionary) -> void:
	match effect.get("type"):
		"max_hp_boost":
			set_max_hp(max_hp - effect.get("amount", 0))
		"defense_boost":
			defense -= effect.get("amount", 0)
		"speed_boost":
			speed -= effect.get("amount", 0)

func update_effects(delta: float) -> void:
	for effect in active_effects:
		if effect.get("type") == "regeneration":
			heal(effect.get("amount_per_second", 0) * delta)
		elif effect.get("type") == "poison":
			damage(effect.get("damage_per_second", 0) * delta)

# ===== 批量恢复 =====

func rest(full: bool = false) -> void:
	if full:
		heal(max_hp)
		restore_hunger(max_hunger * 0.2)
		restore_thirst(max_thirst * 0.2)
		restore_stamina(max_stamina)
		restore_mental(max_mental * 0.3)
	else:
		heal(max_hp * 0.3)
		restore_stamina(max_stamina * 0.5)

func full_restore() -> void:
	heal(max_hp)
	restore_hunger(max_hunger)
	restore_thirst(max_thirst)
	restore_stamina(max_stamina)
	restore_mental(max_mental)

# ===== 获取状态摘要 =====

func get_status_summary() -> Dictionary:
	return {
		"hp": {"current": hp, "max": max_hp, "percent": get_hp_percent()},
		"hunger": {"current": hunger, "max": max_hunger, "percent": get_hunger_percent()},
		"thirst": {"current": thirst, "max": max_thirst, "percent": get_thirst_percent()},
		"stamina": {"current": stamina, "max": max_stamina, "percent": get_stamina_percent()},
		"mental": {"current": mental, "max": max_mental, "percent": get_mental_percent()},
		"is_alive": is_alive(),
		"is_starving": is_starving(),
		"is_dehydrated": is_dehydrated(),
		"has_critical_status": hp < max_hp * 0.2 or hunger < 10 or thirst < 10
	}

# ===== 序列化 =====

func serialize() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"hunger": hunger,
		"max_hunger": max_hunger,
		"thirst": thirst,
		"max_thirst": max_thirst,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"mental": mental,
		"max_mental": max_mental,
		"defense": defense,
		"attack_power": attack_power,
		"speed": speed,
		"body_temperature": body_temperature,
		"radiation_level": radiation_level,
		"disease_resistance": disease_resistance,
		"active_effects": active_effects
	}

func deserialize(data: Dictionary) -> void:
	hp = data.get("hp", 100.0)
	max_hp = data.get("max_hp", 100.0)
	hunger = data.get("hunger", 100.0)
	max_hunger = data.get("max_hunger", 100.0)
	thirst = data.get("thirst", 100.0)
	max_thirst = data.get("max_thirst", 100.0)
	stamina = data.get("stamina", 100.0)
	max_stamina = data.get("max_stamina", 100.0)
	mental = data.get("mental", 100.0)
	max_mental = data.get("max_mental", 100.0)
	defense = data.get("defense", 0.0)
	attack_power = data.get("attack_power", 10.0)
	speed = data.get("speed", 10.0)
	body_temperature = data.get("body_temperature", 36.5)
	radiation_level = data.get("radiation_level", 0.0)
	disease_resistance = data.get("disease_resistance", 0.0)
	active_effects = data.get("active_effects", [])

func _to_string():
	return "CharacterAttributeSet[HP:%.0f/%.0f, Hunger:%.0f%%, Thirst:%.0f%%]" % [
		hp, max_hp, get_hunger_percent() * 100, get_thirst_percent() * 100
	]
