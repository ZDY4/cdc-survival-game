extends "res://modules/interaction/options/interaction_option.gd"
class_name EnterOverworldInteractionOption
## LEGACY AUTHORITY BOUNDARY:
## This is a temporary Godot-side travel option shim. Keep behavior limited to
## client transition requests and UI feedback; avoid adding new authority logic
## that should belong to Rust runtime/protocol.

@export var required_distance: float = 1.4

func _init() -> void:
	option_id = "enter_overworld"
	display_name = "进入大地图"
	priority = 850

func requires_proximity(_interactable: Node) -> bool:
	return true

func get_required_distance(_interactable: Node) -> float:
	return required_distance

func execute(_interactable: Node) -> void:
	var current_scene := _interactable.get_tree().current_scene if _interactable != null else null
	if current_scene != null and current_scene.has_method("request_enter_overworld"):
		if current_scene.request_enter_overworld():
			return
	if DialogModule != null:
		DialogModule.show_dialog("当前无法进入大地图。", "提示", "")
