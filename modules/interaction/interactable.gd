extends Area2D

class_name Interactable

signal interacted

@export var object_name: String = "Object"
@export var interaction_name: String = ""
@export var interaction_description: String = ""
@export var interaction_type: String = "examine"
@export var loot_table: Array = []

var _outline_material: ShaderMaterial
var _sprite: Sprite2D

func _ready():
	print("[Interactable] '" + object_name + "' initialized at " + str(global_position))
	
	# Get Sprite2D reference
	_sprite = get_node_or_null("Sprite2D")
	if not _sprite:
		push_error("[Interactable] Sprite2D not found for '" + object_name + "'")
		return
	
	print("[Interactable] Sprite2D found for '" + object_name + "'")
	
	# Create outline shader material
	_create_outline_material()
	
	# Initially hide outline
	_update_outline(false)
	
	# Connect signals
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Web/移动端：连接触摸信号
	if OS.has_feature("web") or OS.has_feature("mobile"):
		if TouchInputHandler:
			TouchInputHandler.touch_pressed.connect(_on_touch_pressed)
		
		# 触摸设备上直接连接触摸事件
		input_event.connect(_on_touch_input_event)
	
	print("[Interactable] '" + object_name + "' ready for interaction")

func _on_touch_input_event(viewport: Node, event: InputEvent, shape_idx: int):
	# 处理触摸事件
	if event is InputEventScreenTouch:
		if event.pressed:
			print("[Interactable] Touch detected on '" + object_name + "'")
			_on_click()

func _on_touch_pressed(position: Vector2):
	# 检查触摸点是否在这个对象上
	var shape = get_node_or_null("CollisionShape2D")
	if shape and shape.shape:
		var local_pos = to_local(position)
		if shape.shape is RectangleShape2D:
			var rect = Rect2(-shape.shape.size / 2, shape.shape.size)
			if rect.has_point(local_pos):
				print("[Interactable] Touch pressed on '" + object_name + "'")
				_on_click()

func _create_outline_material(item: Dictionary = {}):
	var outline_shader = Shader.new()
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

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int):
	print("[Interactable] Input event on '" + object_name + "': " + str(event))
	if event is InputEventMouseButton && event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			print("[Interactable] Left click detected on '" + object_name + "'")
			_on_click()

func _on_mouse_entered():
	print("[Interactable] Mouse entered '" + object_name + "'")
	_update_outline(true)

func _on_mouse_exited():
	print("[Interactable] Mouse exited '" + object_name + "'")
	_update_outline(false)

func _on_click():
	print("[Interactable] Clicked on '" + object_name + "' (type: " + interaction_type + ")")
	interacted.emit()
	match interaction_type:
		"search": _search()
		"move": _move()
		"talk": _talk()
		"sleep": _sleep()
		_:
			print("[Interactable] Unknown interaction type: " + interaction_type)

func _search(search_data: Dictionary = {}):
	print("[Interactable] Searching '" + object_name + "'")
	var loot = _generate_loot()
	print("[Interactable] Generated loot: " + str(loot))
	if loot.size() > 0:
		for item in loot:
			InventoryModule.add_item(item.id, item.count)
			print("[Interactable] Added item: " + item.id + " x" + str(item.count))
		EventBus.emit(EventBus.EventType.ITEM_ACQUIRED, {"items": loot})
	else:
		print("[Interactable] No loot found")
	
	DialogModule.show_dialog("You searched " + object_name + " && found some items.")

func _move():
	print("[Interactable] Moving through '" + object_name + "'")
	var location = _get_target_location()
	print("[Interactable] Target location: " + location)
	if location:
		var scene_path = "res://scenes/locations/" + location + ".tscn"
		print("[Interactable] Changing scene to: " + scene_path)
		get_tree().change_scene_to_file(scene_path)
	else:
		push_error("[Interactable] No target location found for '" + object_name + "'")

func _talk():
	print("[Interactable] Talking to '" + object_name + "'")
	DialogModule.show_dialog("You talk to " + object_name + ", but they don't respond.")

func _sleep():
	print("[Interactable] Sleeping at '" + object_name + "'")
	DialogModule.show_dialog("You feel very tired && need to rest.")
	var choice = await DialogModule.show_choices(["Sleep here", "Continue exploring"])
	print("[Interactable] Sleep choice: " + str(choice))
	if choice == 0:
		print("[Interactable] Player chose to sleep")
		SaveSystem.save_game()
		GameState.heal_player(50)
		DialogModule.show_dialog("You slept well. HP restored.")
	else:
		print("[Interactable] Player chose not to sleep")

func _generate_loot(loot_item: Dictionary = {}):
	var result = []
	for entry in loot_table:
		if randf() < entry.drop_chance:
			result.append({
				"id": entry.id,
				"count": randi_range(entry.min_count, entry.max_count)
			})
	return result

func _get_target_location():
	match object_name:
		"Door to Street A":
			return "street_a"
		"Door to Street B":
			return "street_b"
		"Door to Safehouse":
			return "safehouse"
	return ""

func _update_outline(visible_outline: bool):
	if not _sprite:
		return
	
	if visible_outline:
		_sprite.material = _outline_material
	else:
		_sprite.material = null
