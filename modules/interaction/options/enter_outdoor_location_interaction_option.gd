extends "res://modules/interaction/options/interaction_option.gd"
class_name EnterOutdoorLocationInteractionOption
## LEGACY AUTHORITY BOUNDARY:
## Travel option wiring remains a Godot-side compatibility path for now.
## Do not grow map-travel authority here; final travel/context decisions should
## come from Rust runtime/protocol and be consumed as client-side transitions.

@export var target_location_id: String = ""
@export var required_distance: float = 1.4

func _init() -> void:
	option_id = "enter_outdoor_location"
	display_name = "进入地点"
	priority = 870

func is_available(_interactable: Node) -> bool:
	if not enabled:
		return false
	if target_location_id.is_empty():
		return false
	if MapModule != null and MapModule.has_method("is_location_unlocked"):
		return bool(MapModule.is_location_unlocked(target_location_id))
	return true

func requires_proximity(_interactable: Node) -> bool:
	return true

func get_required_distance(_interactable: Node) -> float:
	return required_distance

func execute(_interactable: Node) -> void:
	if target_location_id.is_empty():
		if DialogModule != null:
			DialogModule.show_dialog("大地图地点未配置。", "提示", "")
		return

	var current_scene := _interactable.get_tree().current_scene if _interactable != null else null
	if current_scene != null and current_scene.has_method("request_enter_outdoor_location"):
		if current_scene.request_enter_outdoor_location(target_location_id):
			return

	if DialogModule != null:
		DialogModule.show_dialog("当前无法进入该露天地点。", "提示", "")
