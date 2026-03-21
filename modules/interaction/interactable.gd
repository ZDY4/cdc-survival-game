extends Node3D
## Unified interactable component for 3D scenes.

class_name Interactable

const InteractionOptionScript = preload("res://modules/interaction/options/interaction_option.gd")

# 2. Exports
@export var interaction_name: String = ""
@export var options: Array = []
@export var hover_outline_target_path: NodePath = NodePath()

# 4. Private variables
var _runtime_options: Array = []

# 5. Signals
signal interacted

# 6. Public methods
func set_options(new_options: Array) -> void:
	options = new_options
	_build_runtime_options()

func get_interaction_name() -> String:
	if not interaction_name.is_empty():
		return interaction_name
	var primary_option: Variant = get_primary_option()
	if primary_option:
		return primary_option.get_option_name(self)
	return name

func get_available_options() -> Array:
	return _get_available_options()

func get_primary_option():
	var available: Array = _get_available_options()
	if available.is_empty():
		return null
	return available[0]

func get_hover_outline_target() -> Node:
	if not hover_outline_target_path.is_empty():
		var explicit_target := get_node_or_null(hover_outline_target_path)
		if explicit_target != null:
			return explicit_target
	var parent := get_parent()
	if parent != null:
		return parent
	return self

func execute_option(option) -> void:
	_execute_option(option)

func _get_available_options() -> Array:
	if _runtime_options.is_empty() and not options.is_empty():
		_build_runtime_options()
	var available: Array = []
	for option in _runtime_options:
		if option and option.is_available(self):
			available.append(option)
	available.sort_custom(func(a, b): return a.get_priority(self) > b.get_priority(self))
	return available

func _execute_option(option) -> void:
	if option:
		option.execute(self)

func interact_primary() -> bool:
	var primary_option: Variant = get_primary_option()
	if primary_option == null:
		return false
	_execute_option(primary_option)
	return true

# 7. Private methods
func _ready() -> void:
	add_to_group("interactable")
	_build_runtime_options()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)

func _on_left_click() -> void:
	interact_primary()

func _on_click() -> void:
	interact_primary()

func _on_interacted() -> void:
	interact_primary()

func _build_runtime_options() -> void:
	_runtime_options.clear()
	for option in options:
		if not option:
			continue
		var copy: Variant = option.duplicate(true)
		if copy == null or not (copy is InteractionOptionScript):
			continue
		if copy:
			_runtime_options.append(copy)
