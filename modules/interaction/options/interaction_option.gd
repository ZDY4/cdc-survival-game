extends Resource
class_name InteractionOption

const DANGEROUS_DISPLAY_COLOR: Color = Color(0.86, 0.26, 0.26, 1.0)
const NO_DISPLAY_COLOR: Color = Color(0.0, 0.0, 0.0, 0.0)

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

func get_priority(_interactable: Node) -> int:
	return priority

func is_available(_interactable: Node) -> bool:
	return enabled

func is_dangerous(_interactable: Node) -> bool:
	return false

func get_display_color(interactable: Node) -> Color:
	if is_dangerous(interactable):
		return DANGEROUS_DISPLAY_COLOR
	return NO_DISPLAY_COLOR

func get_cursor_texture(_interactable: Node) -> Texture2D:
	return cursor_icon

func get_cursor_hotspot(_interactable: Node) -> Vector2:
	return cursor_hotspot

func get_action_type(_interactable: Node) -> String:
	return "interact"

func uses_external_action_flow(_interactable: Node) -> bool:
	return false

func requires_proximity(_interactable: Node) -> bool:
	return false

func get_required_distance(_interactable: Node) -> float:
	return 0.0

func get_interaction_anchor_position(interactable: Node) -> Vector3:
	if interactable is Node3D:
		return (interactable as Node3D).global_position
	return Vector3.ZERO

func execute(_interactable: Node) -> void:
	push_warning("InteractionOption.execute() should be overridden by subclasses.")
