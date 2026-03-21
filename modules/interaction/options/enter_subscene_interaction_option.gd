extends "res://modules/interaction/options/interaction_option.gd"
class_name EnterSubsceneInteractionOption

@export var target_location_id: String = ""
@export var return_spawn_id: String = "default_spawn"
@export var required_distance: float = 1.4

func _init() -> void:
	option_id = "enter_subscene"
	display_name = "进入室内"
	priority = 860

func requires_proximity(_interactable: Node) -> bool:
	return true

func get_required_distance(_interactable: Node) -> float:
	return required_distance

func execute(_interactable: Node) -> void:
	if target_location_id.is_empty():
		if DialogModule != null:
			DialogModule.show_dialog("入口未配置目标场景。", "提示", "")
		return
	if MapModule != null and MapModule.has_method("enter_subscene_location"):
		if MapModule.enter_subscene_location(target_location_id, return_spawn_id):
			return
	if DialogModule != null:
		DialogModule.show_dialog("当前无法进入该室内场景。", "提示", "")
