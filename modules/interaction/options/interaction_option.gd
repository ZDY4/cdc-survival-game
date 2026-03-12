extends Resource
class_name InteractionOption

@export var option_id: String = "interact"
@export var display_name: String = "Interact"
@export_multiline var description: String = ""
@export var priority: int = 100
@export var enabled: bool = true
@export var cursor_icon: Texture2D
@export var cursor_hotspot: Vector2 = Vector2(16.0, 16.0)

func get_option_name(_interactable: Node) -> String:
	if not display_name.is_empty():
		return display_name
	return option_id.capitalize()

func is_available(_interactable: Node) -> bool:
	return enabled

func get_cursor_texture(_interactable: Node) -> Texture2D:
	return cursor_icon

func get_cursor_hotspot(_interactable: Node) -> Vector2:
	return cursor_hotspot

func execute(_interactable: Node) -> void:
	push_warning("InteractionOption.execute() should be overridden by subclasses.")
