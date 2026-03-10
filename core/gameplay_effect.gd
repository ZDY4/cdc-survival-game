extends RefCounted
## GameplayEffect - 统一效果基类

class_name GameplayEffect

# 1. Public variables
var id: String = ""
var source_id: String = ""
var source_type: String = ""
var category: String = "neutral"
var duration: float = 0.0
var is_infinite: bool = false
var is_stackable: bool = false
var max_stacks: int = 1
var stack_mode: String = "refresh"
var tick_interval: float = 0.0
var modifiers: Dictionary = {}
var special_effects: Array = []
var visual_effect: String = ""
var color_tint: String = ""


# 2. Public methods
func configure(definition: Dictionary) -> void:
	id = str(definition.get("id", id))
	source_id = str(definition.get("source_id", source_id))
	source_type = str(definition.get("source_type", source_type))
	category = str(definition.get("category", category))
	duration = float(definition.get("duration", duration))
	is_infinite = bool(definition.get("is_infinite", is_infinite))
	is_stackable = bool(definition.get("is_stackable", is_stackable))
	max_stacks = int(definition.get("max_stacks", max_stacks))
	stack_mode = str(definition.get("stack_mode", stack_mode))
	tick_interval = float(definition.get("tick_interval", tick_interval))

	var raw_modifiers: Variant = definition.get("stat_modifiers", definition.get("modifiers", {}))
	if raw_modifiers is Dictionary:
		modifiers = raw_modifiers.duplicate(true)
	else:
		modifiers = {}

	var raw_special: Variant = definition.get("special_effects", [])
	if raw_special is Array:
		special_effects = raw_special.duplicate(true)
	else:
		special_effects = []

	visual_effect = str(definition.get("visual_effect", visual_effect))
	color_tint = str(definition.get("color_tint", color_tint))


func get_modifiers() -> Dictionary:
	return modifiers.duplicate(true)


func set_modifiers(value: Dictionary) -> void:
	modifiers = value.duplicate(true)


func on_apply(_entity_id: String, _context: Dictionary = {}) -> void:
	pass


func on_remove(_entity_id: String, _context: Dictionary = {}) -> void:
	pass


func on_tick(_entity_id: String, _context: Dictionary = {}) -> void:
	pass
