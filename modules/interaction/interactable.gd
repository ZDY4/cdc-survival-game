extends Area2D
class_name Interactable

signal interacted

@export var object_name: String = "Object"
@export var interaction_name: String = ""
@export_multiline var interaction_description: String = ""
@export var interaction_type: String = "examine"
@export var loot_table: Array[Dictionary] = []

# New interaction system: options are configurable resources.
@export var interaction_options: Array[InteractionOption] = []
@export var emit_interacted_signal: bool = true
@export var enable_context_menu: bool = true

var _outline_material: ShaderMaterial
var _sprite: Sprite2D
var _context_menu: PopupMenu
var _context_menu_options: Array[InteractionOption] = []
var _context_menu_legacy_mode: bool = false

func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D")
	_create_outline_material()
	_update_outline(false)
	
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	if OS.has_feature("web") or OS.has_feature("mobile"):
		if TouchInputHandler:
			TouchInputHandler.touch_pressed.connect(_on_touch_pressed)
		input_event.connect(_on_touch_input_event)
	
	_setup_context_menu()

func _exit_tree() -> void:
	if TouchInputHandler and TouchInputHandler.touch_pressed.is_connected(_on_touch_pressed):
		TouchInputHandler.touch_pressed.disconnect(_on_touch_pressed)
	if _context_menu and is_instance_valid(_context_menu):
		_context_menu.queue_free()

func _setup_context_menu() -> void:
	if not enable_context_menu:
		return
	_context_menu = PopupMenu.new()
	_context_menu.name = "%s_ContextMenu" % name
	_context_menu.hide_on_item_selection = true
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	call_deferred("_attach_context_menu_to_root")

func _attach_context_menu_to_root() -> void:
	if not _context_menu or not is_instance_valid(_context_menu):
		return
	if _context_menu.get_parent() != null:
		return
	get_tree().root.add_child(_context_menu)

func _create_outline_material() -> void:
	var outline_shader := Shader.new()
	outline_shader.code = """
	shader_type canvas_item;
	uniform bool outline_enabled = false;
	void fragment() {
		if (outline_enabled) {
			COLOR = vec4(1.0, 1.0, 0.0, 1.0);
		}
	}
	"""
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = outline_shader

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_show_interaction_menu(mouse_event.global_position)

func _on_touch_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_on_left_click()

func _on_touch_pressed(position: Vector2) -> void:
	var shape := get_node_or_null("CollisionShape2D")
	if not shape or not shape.shape:
		return
	var local_pos := to_local(position)
	if shape.shape is RectangleShape2D:
		var rect_shape := shape.shape as RectangleShape2D
		var rect := Rect2(-rect_shape.size / 2.0, rect_shape.size)
		if rect.has_point(local_pos):
			_on_left_click()

func _on_mouse_entered() -> void:
	_update_outline(true)

func _on_mouse_exited() -> void:
	_update_outline(false)

# Backward compatibility for tests/tools that call this method directly.
func _on_click() -> void:
	_on_left_click()

func _on_left_click() -> void:
	_emit_interacted_signal()
	var option := _get_primary_option()
	if option:
		_execute_option(option)
		return
	_execute_legacy_interaction()

func _on_right_click() -> void:
	_show_interaction_menu(get_viewport().get_mouse_position())

func _show_interaction_menu(screen_pos: Vector2) -> void:
	if not enable_context_menu:
		return
	if not _context_menu or not is_instance_valid(_context_menu):
		return
	
	_context_menu.clear()
	_context_menu_options = _get_available_options()
	_context_menu_legacy_mode = _context_menu_options.is_empty()
	
	if _context_menu_legacy_mode:
		var legacy_name := get_interaction_name()
		if legacy_name.is_empty():
			return
		_context_menu.add_item(legacy_name, 0)
		if not interaction_description.is_empty():
			_context_menu.set_item_tooltip(0, interaction_description)
	else:
		for i in range(_context_menu_options.size()):
			var option := _context_menu_options[i]
			_context_menu.add_item(option.get_option_name(self), i)
			if not option.description.is_empty():
				_context_menu.set_item_tooltip(i, option.description)
	
	_context_menu.position = Vector2i(screen_pos)
	_context_menu.reset_size()
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	_emit_interacted_signal()
	if _context_menu_legacy_mode:
		_execute_legacy_interaction()
		return
	if id < 0 or id >= _context_menu_options.size():
		return
	_execute_option(_context_menu_options[id])

func _get_available_options() -> Array[InteractionOption]:
	var available: Array[InteractionOption] = []
	for option in interaction_options:
		if option == null:
			continue
		if option.is_available(self):
			available.append(option)
	available.sort_custom(_sort_options_by_priority)
	return available

func _get_primary_option() -> InteractionOption:
	var available := _get_available_options()
	if available.is_empty():
		return null
	return available[0]

func _sort_options_by_priority(a: InteractionOption, b: InteractionOption) -> bool:
	if a.priority == b.priority:
		return a.get_option_name(self) < b.get_option_name(self)
	return a.priority > b.priority

func _execute_option(option: InteractionOption) -> void:
	if option == null:
		return
	option.execute(self)

func _execute_legacy_interaction() -> void:
	match interaction_type:
		"search":
			_search()
		"move":
			_move()
		"talk":
			_talk()
		"sleep":
			_sleep()
		_:
			pass

func _emit_interacted_signal() -> void:
	if emit_interacted_signal:
		interacted.emit()

func get_interaction_name() -> String:
	var primary := _get_primary_option()
	if primary:
		return primary.get_option_name(self)
	if not interaction_name.is_empty():
		return interaction_name
	return interaction_type

func _search() -> void:
	var loot := _generate_loot()
	if not loot.is_empty():
		for item in loot:
			var item_id := str(item.get("id", ""))
			var count := int(item.get("count", 1))
			if not item_id.is_empty():
				InventoryModule.add_item(item_id, count)
		EventBus.emit(EventBus.EventType.ITEM_ACQUIRED, {"items": loot})
	DialogModule.show_dialog("You searched " + object_name + ".")

func _move() -> void:
	var location := _get_target_location()
	if location.is_empty():
		return
	var scene_path := "res://scenes/locations/" + location + ".tscn"
	get_tree().change_scene_to_file(scene_path)

func _talk() -> void:
	DialogModule.show_dialog("You talk to " + object_name + ", but they don't respond.")

func _sleep() -> void:
	DialogModule.show_dialog("You feel very tired and need to rest.")
	var choice := await DialogModule.show_choices(["Sleep here", "Continue exploring"])
	if choice == 0:
		SaveSystem.save_game()
		GameState.heal_player(50)
		DialogModule.show_dialog("You slept well. HP restored.")

func _generate_loot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in loot_table:
		var drop_chance := float(entry.get("drop_chance", 0.0))
		if randf() >= drop_chance:
			continue
		var item_id := str(entry.get("id", ""))
		var min_count := int(entry.get("min_count", 1))
		var max_count := int(entry.get("max_count", min_count))
		result.append({
			"id": item_id,
			"count": randi_range(min_count, max_count)
		})
	return result

func _get_target_location() -> String:
	match object_name:
		"Door to Street A":
			return "street_a"
		"Door to Street B":
			return "street_b"
		"Door to Safehouse":
			return "safehouse"
		_:
			return ""

func _update_outline(visible_outline: bool) -> void:
	if not _sprite:
		return
	if visible_outline:
		_sprite.material = _outline_material
	else:
		_sprite.material = null
